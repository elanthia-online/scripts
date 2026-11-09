# frozen_string_literal: true

# Child-process driver for loot_be_gone_spec.rb. Run as:
#
#   ruby jar_driver.rb <lich-5 checkout> <loot-be-gone.lic> <scenario.json>
#
# It loads lich-5's real Settings and CharSettings (backed by a temporary
# lich.db3) and lich-5's NilClass patch, as the Lich runtime does, then runs
# loot-be-gone.lic's real stockpile and raid_stockpile procs against a small
# simulated locker. It prints one JSON object: the :jars row read back from
# the database through a separate SQLite connection, the gem counts actually
# in each simulated jar, and anything the script echoed.
#
# This runs in its own process because it defines top-level Lich, Script,
# XMLData and GameObj stand-ins and loads lich-5's Lich::Common::Settings,
# none of which may leak into the rest of the suite.
#
# The game replies below are shaped to match loot-be-gone's own regexes
# (/^You add .* filling it/, /is full/, /^Inside .*? you see ([0-9]+) portion/
# and so on); they are not quoted from the game.

require 'json'
require 'tmpdir'
require 'fileutils'
require 'sequel'
require 'sqlite3'

lich5_root, lic_path, scenario_path = ARGV
abort 'usage: jar_driver.rb <lich-5 checkout> <loot-be-gone.lic> <scenario.json>' unless scenario_path

SCENARIO = JSON.parse(File.read(scenario_path))
DATA_DIR = Dir.mktmpdir('loot-be-gone-jars')
at_exit { FileUtils.remove_entry(DATA_DIR) }

module Lich
  def self.log(msg) = (LOG << msg.to_s)
  def self.sqlite_busy_timeout_ms = 5000

  def self.open_sequel_sqlite(path)
    db = Sequel.sqlite(path)
    db.run("PRAGMA busy_timeout = #{sqlite_busy_timeout_ms}")
    db
  end

  def self.open_sqlite_db(path)
    db = SQLite3::Database.new(path)
    db.busy_timeout(sqlite_busy_timeout_ms)
    db
  end
end

LOG = []

# Settings reports failed or refused writes through Lich::Messaging (and
# Lich.log); both are collected and printed so a spec can see them.
module Lich
  module Messaging
    def self.msg(type, text) = (LOG << "#{type}: #{text}")
  end
end

class Script
  Current = Struct.new(:name)

  def self.current
    @current ||= Current.new('loot-be-gone')
  end
end

module XMLData
  def self.game = 'GSIV'
  def self.name = 'Tester'
end

# lich-5's lib/lich.rb creates the table at startup, before Settings loads.
SQLite3::Database.new(File.join(DATA_DIR, 'lich.db3')).tap do |db|
  db.execute('CREATE TABLE IF NOT EXISTS script_auto_settings (script TEXT NOT NULL, scope TEXT, hash BLOB, PRIMARY KEY(script, scope));')
end.close

$LOAD_PATH.unshift(File.join(lich5_root, 'lib'))
require File.join(lich5_root, 'lib/common/settings.rb')
require File.join(lich5_root, 'lib/common/settings/charsettings.rb')
CharSettings = Lich::Common::CharSettings
SCOPE = 'GSIV:Tester'

def stored_row
  db = SQLite3::Database.new(File.join(DATA_DIR, 'lich.db3'))
  blob = db.get_first_value('SELECT hash FROM script_auto_settings WHERE script = ? AND scope = ?', ['loot-be-gone', SCOPE])
  blob ? Marshal.load(blob) : nil
ensure
  db&.close
end

# A previous run's saved settings, written straight to the database so the
# process cache starts cold, the way it does when the script starts.
def seed_row(row)
  db = SQLite3::Database.new(File.join(DATA_DIR, 'lich.db3'))
  db.execute('INSERT OR REPLACE INTO script_auto_settings (script, scope, hash) VALUES (?, ?, ?)',
             ['loot-be-gone', SCOPE, SQLite3::Blob.new(Marshal.dump(row))])
ensure
  db&.close
end

# -- the simulated game ----------------------------------------------------

class FakeObj
  attr_accessor :id, :noun, :name, :type, :after_name, :gem, :count, :capacity

  def initialize(**attrs)
    attrs.each { |k, v| public_send("#{k}=", v) }
  end

  def contents
    World.contents[id]&.dup
  end
end

module World
  LOCKER_ID = '100'
  LOOTSACK_ID = '900'

  class << self
    attr_accessor :right_hand, :left_hand, :echoes

    def contents
      @contents ||= {}
    end

    def objects
      contents.values.flatten + [right_hand, left_hand].compact
    end

    def find(id)
      objects.find { |o| o.id == id }
    end

    def take(id)
      obj = find(id)
      contents.each_value { |list| list.reject! { |o| o.id == id } }
      self.right_hand = nil if right_hand&.id == id
      self.left_hand = nil if left_hand&.id == id
      obj
    end

    def into(container_id, obj)
      take(obj.id)
      contents[container_id] << obj
    end

    def plural(gem)
      gem.sub(/y\z/, 'ie') + 's'
    end
  end
end

module GameObj
  def self.containers = World.contents.transform_values(&:dup)
  def self.right_hand = World.right_hand || FakeObj.new(id: nil)
  def self.left_hand = World.left_hand || FakeObj.new(id: nil)
end

def status_tags(*) = nil
def empty_hands = nil
def fill_hands = nil
def echo(msg) = World.echoes << msg.to_s

def drag_reply(gem, jar)
  if jar.count >= jar.capacity
    "The #{jar.noun} is full."
  else
    World.take(gem.id)
    jar.count += 1
    if jar.count == 1
      jar.gem = gem.name
      jar.after_name = "containing #{World.plural(gem.name)}"
      "You put #{gem.name} into the #{jar.noun}."
    elsif jar.count == jar.capacity
      "You add #{gem.name} to the #{jar.noun}, filling it."
    else
      "You add #{gem.name} to the #{jar.noun}."
    end
  end
end

def dothistimeout(cmd, _timeout, _regex)
  case cmd
  when 'open locker'
    %(You open <a exist="#{World::LOCKER_ID}" noun="locker">a locker</a>.)
  when 'close locker'
    'You close the locker.'
  when /\A_drag #(\d+) #(\d+)\z/
    drag_reply(World.find(Regexp.last_match(1)), World.find(Regexp.last_match(2)))
  when /\Aget #(\d+)(?: from #\d+)?\z/
    World.right_hand = World.take(Regexp.last_match(1))
    'You remove it.'
  when /\Aput #(\d+) in #(\d+)\z/
    World.into(Regexp.last_match(2), World.find(Regexp.last_match(1)))
    'You put it away.'
  when /\Alook in #(\d+) from #\d+\z/
    jar = World.find(Regexp.last_match(1))
    "Inside the #{jar.noun} you see #{jar.count} portions.#{' It is full.' if jar.count >= jar.capacity}"
  when /\Ashake #(\d+)\z/
    jar = World.find(Regexp.last_match(1))
    jar.count -= 1
    World.left_hand = FakeObj.new(id: (700_000 + rand(200_000)).to_s, noun: jar.gem, name: jar.gem, type: 'gem')
    jar.after_name = nil if jar.count.zero?
    'You shake a gem out.'
  else
    raise "jar_driver: unexpected command #{cmd.inspect}"
  end
end

# -- the scenario ------------------------------------------------------------

World.echoes = []
World.contents[World::LOCKER_ID] = SCENARIO.fetch('locker').map do |j|
  count = j.fetch('count', 0)
  FakeObj.new(id: j.fetch('id'), noun: 'jar', name: 'glass jar', type: 'jar', gem: j['gem'], count: count,
              capacity: j.fetch('capacity'), after_name: count.positive? ? "containing #{World.plural(j.fetch('gem'))}" : nil)
end
World.contents[World::LOOTSACK_ID] = SCENARIO.fetch('lootsack', []).map do |g|
  FakeObj.new(id: g.fetch('id'), noun: g.fetch('name'), name: g.fetch('name'), type: 'gem')
end
seed_row(SCENARIO['saved'].transform_keys(&:to_sym).tap { |row| row[:jars] = row[:jars]&.map { |j| j.transform_keys(&:to_sym) } }) if SCENARIO['saved']

lootsack = FakeObj.new(id: World::LOOTSACK_ID, noun: 'sack', name: 'sack')
lootsack_list = [lootsack]
lootsack_put = proc { |obj| World.into(World::LOOTSACK_ID, obj) unless lootsack.contents.any? { |o| o.id == obj.id } }
lic = File.read(lic_path)
put_regex = Regexp.new(lic[/^put_regex = \/(.*)\/$/, 1] || raise('jar_driver: put_regex not found'))
get_regex = Regexp.new(lic[/^get_regex = \/(.*)\/$/, 1] || raise('jar_driver: get_regex not found'))

# Everything between from_locker and the end of stockpile (need_to_stockpile,
# stockpile and any helpers the script defines for them), then raid_stockpile.
region = lic[/^from_locker = proc \{\n.*?^\}\n(.*?^stockpile = proc \{\n.*?^\}\n)/m, 1] || raise('jar_driver: stockpile not found')
raid = lic[/^raid_stockpile = proc \{.*?^\}\n/m] || raise('jar_driver: raid_stockpile not found')
script_binding = binding
eval(region, script_binding, lic_path, lic[0, lic.index(region)].count("\n") + 1)
eval(raid, script_binding, lic_path, lic[0, lic.index(raid)].count("\n") + 1)

require File.join(lich5_root, 'lib/common/class_exts/nilclass.rb')

SCENARIO.fetch('steps').each do |step|
  case step.fetch('run')
  when 'stockpile' then script_binding.local_variable_get(:stockpile).call
  when 'raid' then script_binding.local_variable_get(:raid_stockpile).call(+step.fetch('gem'), step.fetch('count'))
  else raise "jar_driver: unknown step #{step.inspect}"
  end
end

row = stored_row || {}
jars = row[:jars]
jar_objects = (World.contents[World::LOCKER_ID] + World.contents[World::LOOTSACK_ID]).select { |o| o.noun == 'jar' }
puts JSON.generate(
  'stored_jars' => jars.is_a?(Array) ? jars.map { |j| j.transform_keys(&:to_s) } : jars.inspect,
  'locker'      => jar_objects.map { |j| { 'id' => j.id, 'gem' => j.gem && World.plural(j.gem), 'count' => j.count, 'full' => j.count >= j.capacity } },
  'echoes'      => World.echoes,
  'log'         => LOG
)
