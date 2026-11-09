# frozen_string_literal: true

# Runs boon.lic's real stockpile and raid_stockpile procs against lich-5's real
# Settings stack, in a process of its own, for spec/scripts/boon/stockpile_spec.rb.
#
# Usage: ruby stockpile_worker.rb <lich5_root> <boon.lic> <data_dir>
#   stdin:  one JSON scenario (see FakeGame#initialize and run below)
#   stdout: one JSON line: { "jars", "empty_jar_count", "commands", "raided" }
#
# lich-5 is loaded the way the Lich runtime loads it: lib/lich.rb (init_db, so
# the settings table is the production one), class_exts/nilclass.rb (always
# loaded by the runtime), settings.rb and charsettings.rb, on a real lich.db3 in
# data_dir. It runs in its own process because loading the real Lich module and
# NilClass patch into the shared rspec process would change behaviour for every
# other spec.
#
# Only the game is faked. The game lines FakeGame returns are shaped to the
# patterns boon.lic itself waits for; they are not captured game output.

require 'json'
require 'sequel'
require 'sqlite3'

lich5_root, boon_path, data_dir = ARGV
abort 'usage: stockpile_worker.rb <lich5_root> <boon.lic> <data_dir>' unless data_dir

DATA_DIR = data_dir
LIB_ROOT = File.join(lich5_root, 'lib')

require File.join(LIB_ROOT, 'lich.rb')

module Lich
  def self.log(_msg); end

  def self.deprecated(*_args); end

  module Messaging
    def self.msg(_kind, _text); end
  end
end

require File.join(LIB_ROOT, 'common/class_exts/nilclass')

module XMLData
  class << self
    attr_accessor :game, :name
  end
end
XMLData.game = 'GSIV'
XMLData.name = 'Tester'

class Script
  Current = Struct.new(:name)

  class << self
    attr_accessor :current
  end
end
Script.current = Script::Current.new('boon')

Lich.init_db

require File.join(LIB_ROOT, 'common/settings')
require File.join(LIB_ROOT, 'common/settings/charsettings')

CharSettings = Lich::Common::CharSettings

Item = Struct.new(:id, :noun, :name, :after_name, :type)

# A locker of jars and a gem sack. A jar holds one kind of gem up to its
# capacity; its after_name is "containing <gem>s" once it holds any.
# The sack's contents are replaced, never changed in place: lich-5's
# GameObj#contents returns a copy, and boon iterates over it while it moves
# gems out.
class FakeGame
  LOCKER_ID = '900'
  SACK_ID = '800'

  attr_reader :commands, :locker, :sack, :right_hand, :left_hand

  def initialize(scenario)
    @commands = []
    @next_id = 1000
    @fill = {}
    @capacity = {}
    @locker = scenario.fetch('locker').map do |jar|
      item = Item.new(new_id, 'jar', 'glass jar', nil, 'jar')
      @capacity[item.id] = jar.fetch('capacity')
      @fill[item.id] = [jar['gem'], jar.fetch('count', 0)]
      item.after_name = "containing #{jar['gem']}s" if jar['gem']
      item
    end
    @sack = Item.new(SACK_ID, 'sack', 'gem sack', nil, 'container')
    @sack_contents = scenario.fetch('sack').map { |name| Item.new(new_id, name.split.last, name, nil, 'gem') }
    @bounty = scenario['bounty']
    @right_hand = Item.new(nil, nil, 'Empty', nil, nil)
    @left_hand = Item.new(nil, nil, 'Empty', nil, nil)
  end

  def sack_contents
    @sack_contents
  end

  def bounty
    @bounty
  end

  def find(id)
    (@locker + @sack_contents).find { |item| item.id == id }
  end

  def command(cmd)
    @commands << cmd
    case cmd
    when 'open locker'
      %(<container exist="#{LOCKER_ID}" noun="locker">)
    when 'close locker'
      'You close the locker.'
    when /\Alook in #(\d+) from #/
      gem, count = @fill.fetch(Regexp.last_match(1))
      full = count >= @capacity.fetch(Regexp.last_match(1)) ? ' It is full.' : ''
      "Inside the glass jar you see #{count} portions of #{gem}s.#{full}"
    when /\Aget #(\d+)/
      jar = find(Regexp.last_match(1))
      @sack_contents -= [jar]
      @left_hand = jar
      'You remove a glass jar.'
    when /\A_drag #(\d+) #(\d+)\z/
      drag(Regexp.last_match(1), Regexp.last_match(2))
    when /\Aput #(\d+) in ##{SACK_ID}\z/
      item = find(Regexp.last_match(1)) || hand_item(Regexp.last_match(1))
      @sack_contents += [item] unless @sack_contents.include?(item)
      @right_hand = Item.new(nil, nil, 'Empty', nil, nil) if @right_hand.id == item.id
      "You put #{item.name} in your gem sack."
    when /\Aput #(\d+) in ##{LOCKER_ID}\z/
      'You put a glass jar in the locker.'
    when /\Ashake #(\d+)\z/
      shake(Regexp.last_match(1))
    else
      raise "unexpected command: #{cmd}"
    end
  end

  private

  def new_id
    (@next_id += 1).to_s
  end

  def hand_item(id)
    @right_hand if @right_hand.id == id
  end

  def drag(gem_id, jar_id)
    gem = @sack_contents.find { |item| item.id == gem_id }
    jar = find(jar_id)
    kind, count = @fill.fetch(jar_id)
    return 'The glass jar is full.' if count >= @capacity.fetch(jar_id)

    @sack_contents -= [gem]
    if kind.nil?
      @fill[jar_id] = [gem.name, 1]
      jar.after_name = "containing #{gem.name}s"
      return "You put #{gem.name} into the glass jar."
    end

    @fill[jar_id] = [kind, count + 1]
    filling = count + 1 >= @capacity.fetch(jar_id) ? ', filling it' : ''
    "You add #{gem.name} to the glass jar#{filling}."
  end

  def shake(jar_id)
    kind, count = @fill.fetch(jar_id)
    @fill[jar_id] = [kind, count - 1]
    @right_hand = Item.new(new_id, kind.split.last, kind, nil, 'gem')
    "You shake the glass jar and #{kind} falls into your hand."
  end
end

# GameObj, as boon's stockpile procs use it.
module GameObj
  class << self
    attr_accessor :game

    def containers
      { FakeGame::LOCKER_ID => game.locker }
    end

    def right_hand
      game.right_hand
    end

    def left_hand
      game.left_hand
    end
  end
end

def status_tags(*_args); end

def empty_hands; end

def fill_hands; end

def echo(*_args); end

def fput(cmd)
  GameObj.game.command(cmd)
end

def dothistimeout(cmd, _timeout, _pattern)
  GameObj.game.command(cmd)
end

def bounty?
  GameObj.game.bounty
end

def checkbounty
  GameObj.game.bounty
end

scenario = JSON.parse($stdin.read)
game = FakeGame.new(scenario)
GameObj.game = game
game.sack.define_singleton_method(:contents) { game.sack_contents }

source = File.read(boon_path)
extract = lambda do |pattern, label|
  source[pattern] or abort("could not extract #{label} from #{boon_path}")
end
putregex_line = extract.call(/^putregex = .*$/, 'putregex')
stockpile_src = extract.call(/^stockpile = proc \{\n.*?^\}\n/m, 'stockpile')
raid_src = extract.call(/^raid_stockpile = proc \{\n.*?^\}\n/m, 'raid_stockpile')

sacks = { 'gem' => game.sack }
stockpile, raid_stockpile = eval(
  "#{putregex_line}\n#{stockpile_src}\n#{raid_src}\n[stockpile, raid_stockpile]",
  binding, boon_path
)

CharSettings[:jars] = scenario['jars'].map { |h| h.transform_keys(&:to_sym) } if scenario.key?('jars')
CharSettings[:empty_jar_count] = scenario['empty_jar_count'] if scenario.key?('empty_jar_count')

raided = nil
scenario.fetch('steps').each do |step|
  case step
  when 'stockpile' then stockpile.call
  when 'raid' then raided = raid_stockpile.call
  else raise "unknown step #{step}"
  end
end

# What a restart reads: the row as stored, not this process's cache.
row = Lich::Common::Settings.instance_variable_get(:@db_adapter).get_settings('boon', 'GSIV:Tester')
puts JSON.generate(
  'jars'            => row[:jars],
  'empty_jar_count' => row[:empty_jar_count],
  'commands'        => game.commands,
  'raided'          => raided
)
