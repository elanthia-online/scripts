# frozen_string_literal: true

# Child-process driver for analytics_spec.rb. Run as:
#
#   ruby analytics_driver.rb <analytics.lic> <scenario>
#
# It defines the Lich globals analytics.lic expects (XMLData, DATA_DIR,
# Script, DownstreamHook, ...) as top-level stand-ins, loads the real script
# up to its entry point, runs one named scenario against a temporary SQLite
# database, and prints one JSON object of what happened.
#
# This runs in its own process because those stand-ins are top-level and may
# not leak into the rest of the suite (the same reason as loot_be_gone's
# jar_driver.rb). The script is loaded for real, so every example exercises
# production code; the stand-ins only replace the game and the Lich runtime.

require 'json'
require 'tmpdir'
require 'fileutils'
require 'net/http'
require 'stringio'

lic_path, scenario = ARGV
abort 'usage: analytics_driver.rb <analytics.lic> <scenario>' unless scenario

DATA_DIR = Dir.mktmpdir('analytics-spec')
at_exit { FileUtils.rm_rf(DATA_DIR) }

OUT = []
def respond(text = '') = OUT << text.to_s
def echo(*texts) = texts.each { |text| OUT << "echo: #{text}" }
def before_dying(&) = nil
def fput(*) = nil
def checkdead = false
def checkright = nil
def checkleft = nil
def waitrt? = nil
def waitcastrt? = nil
def pause(*) = nil

module XMLData
  def self.game = 'GS3'
  def self.name = 'Splinter'
  def self.room_id = $room_id || 0
  # What the mindState progress bar carries (ProgressManager)
  def self.level = $level || 100
  def self.lumnis = $lumnis
  def self.rpa = nil
  def self.fashlonae = nil
end

class Script
  Current = Struct.new(:name, :vars)
  def self.running?(name) = ($running ||= []).include?(name.to_s)
  def self.current = Current.new('analytics', [''])
  def self.start(*) = nil
  def self.run(*) = nil
  def self.pause(*) = nil
  def self.unpause(*) = nil
end

module UserVars
  def self.op = {}
end

# Minimal stand-in for Lich's hook sets: runs every hook over the line.
class HookSet
  def initialize = @hooks = {}
  def add(name, action, **) = @hooks[name] = action
  def remove(name) = @hooks.delete(name)
  def run(line) = @hooks.values.reduce(line) { |text, hook| text && hook.call(text) }
  def names = @hooks.keys
end
DownstreamHook = HookSet.new
UpstreamHook = HookSet.new

module Char
  def self.percent_encumbrance = 12.5
end

module Experience
  def self.txp = 1_000_000
  def self.exp = $exp || 900_000
  def self.axp = 100_000
  def self.until_next = 1500
  def self.deeds = 12
  def self.lte = 59
  def self.deaths_sting = $sting || 'None'
  # When EXPERIENCE was last read (infomon); nil until set
  def self.updated_at = $read_at
  def self.fxp_current = 400
  def self.fxp_max = 800
  def self.fame = 5000
end

BANK_LINES = ['The Bank amounts on deposit:', 'Icemule Trace: 1,500,000',
              "Wehnimer's Landing: 2,100,000,000", 'Total: 2,101,500,000'].freeze
$bank_lines = BANK_LINES
$lich_char_regex = Regexp.union(',', ';')

# Stand-in for Lich's SQLite helper: Lich's busy timeout, and a record of
# every connection it set up (Lich's own after_connect installs its lock wait)
$sqlite_busy_ms = 5000
$sqlite_opened = []
$sqlite_hooked = []

module Lich
  def self.open_sequel_sqlite(path)
    $sqlite_opened << path
    Sequel.sqlite(path, timeout: $sqlite_busy_ms, after_connect: ->(conn) { $sqlite_hooked << conn.object_id })
  end

  module Messaging
    def self.msg(type, text) = OUT << "msg[#{type}]: #{text}"
  end

  module Util
    def self.quiet_command_xml(*)
      $bank_lines.each { |line| DownstreamHook.run(line) } if $feed_hook
      $bank_lines
    end
  end
end

class TaskStub
  attr_reader :type, :creature, :town, :requirements

  def initialize(type, creature, area, number, item = nil)
    @type = type
    @creature = creature
    @town = area
    @requirements = { area: area, number: number, type => item }.compact
  end

  def none? = type == :none
end

module Bounty
  def self.task = $task

  # Stand-in for Lich's Bounty::Parser, giving the same shapes for the
  # taskmaster lines the specs use. Like Lich's, it returns its table of
  # matchers, not nil, when nothing matches.
  class Parser
    TOWN = /task here from the town of (?<town>[^.]+)\./
    MATCHERS = {
      escort: /protective escort on (?:his|her) upcoming journey\.  Go to (?<start>[^.]+) and WAIT .* safety to (?<destination>[^.]+) as soon/,
      bandit_assignment: /It appears they have a bandit problem/,
      creature_assignment: /It appears they have a creature problem/,
      gem_assignment: /The local gem dealer, (?<npc_name>[^,]+), has an order/
    }.freeze

    def initialize(description) = @description = description

    def parse
      MATCHERS.each do |type, regex|
        next unless (found = regex.match(@description))

        needs = found.named_captures.transform_keys(&:to_sym)
        town = @description[TOWN, :town]
        needs[:town] = town if town
        return { type: type, requirements: needs, town: town }.compact
      end
    end
  end
end

source = File.read(lic_path).gsub("\r\n", "\n")
cut = source.index(/^# =+\n# Entry point/) or abort 'analytics.lic: entry point marker not found'
$VERBOSE = nil
eval(source[0...cut], TOPLEVEL_BINDING, lic_path)
A = GS4Analytics
WHO = A::Who.current
NOW = Time.now.to_i

def run_sql(statement, *params) = A::Database.db.run(Sequel.lit(statement, *params))
def lines(result) = result.join("\n")

# One completed hunt cycle (and, with +rest+, the rest after it) starting at +start+
def seed_cycles(who, start, rest: true, hunt_secs: 2700)
  hunt = A::Database.start_cycle(who, :hunt, 'bigshot', 'splinter_crags',
                                 { exp_total: 1_000_000, exp_field: 100, exp_max: 800, fame: 10, encumbrance: 20.0 })
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', start, hunt)
  A::Database.end_cycle(hunt, { exp_total: 1_100_000, exp_field: 700, exp_max: 800, fame: 20, encumbrance: 40.0 },
                        'Too many items')
  run_sql('UPDATE cycles SET end_time = ?, duration_seconds = ? WHERE cycle_id = ?', start + hunt_secs, hunt_secs, hunt)
  return unless rest

  rest_id = A::Database.start_cycle(who, :rest, 'my_rest', 'splinter_crags',
                                    { exp_total: 1_100_000, exp_field: 700, exp_max: 800, fame: 20, encumbrance: 40.0 })
  run_sql('UPDATE cycles SET start_time = ?, end_time = ?, duration_seconds = 400, ' \
          'exp_total_end = 1100000, rest_reason = ? WHERE cycle_id = ?', start + hunt_secs, start + hunt_secs + 400, 'Too many items', rest_id)
  A::Database.record_rest_steps(who, rest_id, start + hunt_secs, { 'travel' => 120.0, 'selling' => 80.5 })
end

# Three characters over the last few days: two games, one shared name
def seed_history
  [WHO, A::Who.new('GS3', 'April'), A::Who.new('GSF', 'Splinter')].each do |who|
    midnight = A::Util.midnight(Date.today)
    # A hunt (and rest, when there is room) earlier today, whatever the time of day, so it shows on the dashboard
    recent = [A::Util.midnight(Date.today), NOW - 5000].max
    hunt_secs = [2700, NOW - recent - 30].min
    seed_cycles(who, recent, rest: NOW - recent > 3200, hunt_secs: hunt_secs) if hunt_secs > 60
    3.downto(1) do |ago|
      seed_cycles(who, midnight - (ago * 86_400) + (8 * 3600))
      run_sql('INSERT INTO kill_stats (game, character, date, profile, creature, kill_count, total_silver, last_kill_at) ' \
              'VALUES (?,?,?,?,?,?,?,?) ON CONFLICT DO NOTHING',
              *who, (Date.today - ago).to_s, 'splinter_crags', 'kobold', 100, 5000, NOW - 100)
    end
  end
end

# Short lock waits, so a held lock costs milliseconds rather than seconds
def quick_busy_timeouts
  $sqlite_busy_ms = 200
  { BUSY_BACKOFF_START_S: 0.05, BUSY_BACKOFF_MAX_S: 0.1 }.each do |name, value|
    A::Database.send(:remove_const, name)
    A::Database.const_set(name, value)
  end
end

# Another Lich session holding the write lock (as ;analytics maintenance vacuum would)
def hold_write_lock
  lock = SQLite3::Database.new(A::Database.file)
  lock.execute('BEGIN IMMEDIATE')
  lock
end

result = {}

case scenario
when 'util'
  result = {
    'fmt'           => [A::Util.fmt(1_234_567), A::Util.fmt(-1234), A::Util.fmt(12)],
    'short'         => [A::Util.short(1_500_000), A::Util.short(-2_500_000_000), A::Util.short(950)],
    'hms'           => A::Util.hms(3725),
    'hm'            => [A::Util.hm(3725), A::Util.hm(0)],
    'mode'          => A::Util.mode([1, 2, 2, 3, 3]),
    'median'        => [A::Util.median([3, 1, 2]), A::Util.median([1, 2, 3, 4]), A::Util.median([])],
    'percent'       => [A::Util.percent(1, 4), A::Util.percent(1, 0)],
    'binary_string' => A::Util.norm('abc'.b).encoding.to_s,
    'who'           => [WHO.to_s, WHO.to_a, A::Who.parse('GS3:Splinter') == WHO, { WHO => 1 }[A::Who.parse('GS3:Splinter')],
                        A::Who.new('GSF', 'Splinter') == WHO],
    'version'       => [A::VERSION, source[/^\s+version: (\S+)$/, 1]]
  }

when 'settings'
  file = A::Settings.path(WHO)
  global = A::Settings.global_path
  defaults = A::Settings.load(WHO)
  written = [File.exist?(global), File.exist?(file)]
  read = ->(path) { YAML.safe_load_file(path, symbolize_names: true) }
  # What was written reads back: the defaults in the global file, every key blank in the character's
  global_back = read.call(global)
  char_back = read.call(file)
  blank = char_back.all? { |_, v| v.nil? || (v.is_a?(Hash) && v.values.all?(&:nil?)) }
  # every setting has its comment on its line (a map's entries, under it, are values)
  map_entry = ->(l) { l.start_with?('  ') && !l.include?(' # ') && A::Settings::DEFAULTS[:rest_steps].any? { |k, v| l.strip == "#{k}: #{v}" } }
  layout = File.readlines(global).reject { |l| l.start_with?('#') || l.strip.empty? || map_entry.call(l) }.all? { |l| l.include?(' # ') }
  # The global file sets two things; the character's overrides one alert, turns the rest script off, adds a room
  File.write(global, File.read(global).sub(/^rest_script:/, 'rest_script: shared_rest').sub(/^  no_kill_minutes: 10/, '  no_kill_minutes: 7'))
  File.write(file, File.read(file).sub(/^rest_script:/, 'rest_script: false').sub(/^  silver_drop_pct:/, '  silver_drop_pct: 30')
                                  .sub(/^profile_room_map:/, 'profile_room_map: { crags: 1234 }'))
  custom = A::Settings.load(WHO)
  File.write(file, File.read(file).sub(/^rest_script: false/, 'rest_script:'))
  inherited = A::Settings.load(WHO)
  File.write(file, "rest_script: [unclosed\n")
  broken = A::Settings.load(WHO)
  # Values of the wrong kind: the defaults instead, each reported; a number written as text is read
  File.write(file, "idle_warn_minutes: 8m\nmax_hunt_minutes: '30'\nparse_bank: maybe\nweapon_loadout: scepter\n" \
                   "alerts:\n  no_kill_minutes: ten\ndashboard:\n  port: '9090'\n")
  typed = A::Settings.load(WHO)
  typed_said = OUT.grep(/Setting \S+: .* isn't/).map { |line| line[/Setting (\S+):/, 1] }
  broken_said = OUT.any? { |line| line.include?('ERROR (settings') }
  # A group given one value (alerts: false): left out and said, so the groups still read
  OUT.clear
  File.write(file, "alerts: false\ndashboard: 8080\n")
  grouped = A::Settings.load(WHO)
  grouped_said = OUT.grep(/Setting \S+: .* isn't its settings/).map { |line| line[/Setting (\S+):/, 1] }
  result = {
    'path' => file.delete_prefix("#{DATA_DIR}/"), 'global_path' => global.delete_prefix("#{DATA_DIR}/"), 'written' => written,
    'default_hunt' => defaults[:hunt_script], 'default_rest' => defaults[:rest_script],
    'rest_steps_first' => defaults[:rest_steps].keys.first,
    'round_trip' => global_back.merge(rest_steps: global_back[:rest_steps].transform_keys(&:to_s)) == A::Settings::DEFAULTS,
    'char_keys' => char_back.keys == A::Settings::DEFAULTS.keys && char_back[:alerts].keys == A::Settings::DEFAULTS[:alerts].keys,
    'char_blank' => blank, 'inline_comments' => layout,
    'custom' => [custom[:rest_script], custom[:alerts][:no_kill_minutes], custom[:alerts][:silver_drop_pct],
                 custom[:alerts][:death], custom[:profile_room_map], custom[:hunt_script]],
    'inherited_rest' => inherited[:rest_script],
    'broken' => [broken[:rest_script], broken[:alerts][:no_kill_minutes], broken_said],
    'typed' => [typed[:idle_warn_minutes], typed[:max_hunt_minutes], typed[:parse_bank], typed[:weapon_loadout],
                typed[:alerts][:no_kill_minutes], typed[:dashboard][:port]],
    'typed_reported' => typed_said
  }
  result['grouped'] = [grouped[:alerts][:no_kill_minutes], grouped[:dashboard][:port], grouped_said]

when 'database'
  A::Database.connect!
  hunt = A::Database.start_cycle(WHO, :hunt, 'bigshot', 'splinter_crags', { exp_total: 100, exp_field: 10 })
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', NOW - 600, hunt)
  ended = A::Database.end_cycle(hunt, { exp_total: 5100, exp_field: 700, exp_max: 800, fame: 11, encumbrance: 35.0 }, 'Too many items')
  saved = A::Database.one('SELECT * FROM cycles WHERE cycle_id = ?', hunt)
  rest = A::Database.start_cycle(WHO, :rest, 'my_rest', 'splinter_crags', { exp_total: 5100 })
  run_sql('UPDATE cycles SET start_time = ?, rest_reason = ? WHERE cycle_id = ?', NOW - 300, 'Too many items', rest)
  A::Database.end_cycle(rest, {}, 'something else')
  A::Database.record_rest_steps(WHO, rest, NOW - 300, { 'travel' => 120.0, 'selling' => 80.5, 'waiting' => 0 })
  short = A::Database.start_cycle(WHO, :hunt, 'bigshot', nil, {})
  A::Database.record_kill(WHO, 'kobold', 'splinter_crags', 100)
  A::Database.record_kill(WHO, 'kobold', 'splinter_crags', 50)
  result = {
    'game_column' => saved['game'], 'character_column' => saved['character'],
    'duration_ok' => ended['duration_seconds'].between?(599, 602),
    'exp_end' => saved['exp_total_end'], 'rest_reason' => saved['rest_reason'],
    'rest_reason_kept' => A::Database.one('SELECT rest_reason FROM cycles WHERE cycle_id = ?', rest)['rest_reason'],
    'rest_steps' => A::Database.all('SELECT step FROM rest_steps ORDER BY step').map { |row| row['step'] },
    'short_dropped' => A::Database.end_cycle(short, {}, nil).nil? &&
                       A::Database.all('SELECT 1 FROM cycles WHERE cycle_id = ?', short).empty?,
    'kills' => A::Database.one('SELECT kill_count, total_silver FROM kill_stats').values,
    'db_in_data_dir' => A::Database.file.start_with?(DATA_DIR)
  }

  A::Database.close
  A::Database.connect!
  result['reconnect_rows'] = A::Database.one('SELECT COUNT(*) AS n FROM cycles')['n']

when 'busy_database'
  A::Database.connect!
  { BUSY_BACKOFF_START_S: 0.05, BUSY_BACKOFF_MAX_S: 0.1 }.each do |name, value|
    A::Database.send(:remove_const, name)
    A::Database.const_set(name, value)
  end
  A::Database.close
  A::Database.connect!
  order = []
  attempts = 0
  locked = lambda do
    raise SQLite3::BusyException, 'database is locked'
  rescue SQLite3::Exception
    raise Sequel::DatabaseError, 'wrapped'
  end
  A::Database.async do
    attempts += 1
    A::Database.db[:metadata].insert(key: 'retry.a', value: 'x', updated_at: 1)
    locked.call if attempts < 3
    order << :a
  end
  A::Database.async { order << :broken; raise('not a busy error') }
  A::Database.async do
    A::Database.db[:metadata].insert(key: 'retry.b', value: 'y', updated_at: 1)
    order << :b
  end
  deadline = Time.now + 10
  sleep 0.02 until order.include?(:b) || Time.now > deadline
  result = {
    'attempts' => attempts, 'order' => order,
    'rows' => A::Database.all("SELECT key FROM metadata WHERE key LIKE 'retry.%' ORDER BY key").map { |row| row['key'] },
    'busy_reported' => OUT.any? { |line| line.include?('ERROR (database busy)') },
    'failure_reported' => OUT.any? { |line| line.include?('ERROR (queued write): RuntimeError: not a busy error') },
    'busy_tells_apart' => [A::Database.send(:busy_error?, Sequel::DatabaseError.new('constraint')),
                           A::Database.send(:busy_error?, RuntimeError.new('other'))]
  }
  A::Database.close

when 'bounties'
  A::Database.connect!
  first = A::Database.start_bounty(WHO, nil, 'cull', 'kobold', 'Icemule Trace', 20)
  second = A::Database.start_bounty(WHO, nil, 'dangerous', 'troll', 'Wehnimer', nil)
  third = A::Database.start_bounty(WHO, nil, 'gem', nil, "Ta'Vaalor", 5)
  A::Database.complete_bounty(first, 11_066, 1100, 1106)
  A::Database.abandon_bounty(second)
  A::Database.expire_bounty(third)
  status = ->(id) { A::Database.one('SELECT * FROM bounties WHERE bounty_id = ?', id) }
  done = status.call(first)
  result = {
    'completed' => [done['status'], done['silver_reward'], done['exp_reward'], done['bp_reward'], done['count_required']],
    'abandoned' => status.call(second)['status'], 'expired' => status.call(third)['status'],
    'active' => A::Database.active_bounties(WHO).size
  }

when 'banks'
  A::Database.connect!
  A::SilverManager.start(WHO)
  A::SilverManager.take_snapshot
  A::Database.flush
  rows = A::Database.all('SELECT bank_name, balance FROM bank_snapshots ORDER BY bank_name')
  warned = OUT.any? { |line| line.include?('2.0B') }
  $bank_lines = ['The Bank amounts on deposit:', 'Icemule Trace: 2,500,000', 'Total: 2,500,000']
  A::SilverManager.take_snapshot
  A::Database.flush
  emptied = A::Database.one("SELECT balance FROM bank_snapshots WHERE bank_name = \"Wehnimer's Landing\" ORDER BY timestamp DESC, rowid DESC LIMIT 1")
  total = A::Database.one("SELECT balance, delta_silver FROM bank_snapshots WHERE bank_name = '__total__' ORDER BY timestamp DESC, rowid DESC LIMIT 1")
  result = {
    'banks' => rows.map { |row| row['bank_name'] }, 'warned' => warned, 'emptied_balance' => emptied['balance'],
    'total_delta' => total['delta_silver'], 'discord_spam' => OUT.grep(/msg\[/).size
  }

when 'collector'
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  sleep 0.2
  hook = DownstreamHook.names.include?('GS4Analytics::SilverManager')
  DownstreamHook.run('You search the halfling cannibal.')
  DownstreamHook.run('<pushBold/>The halfling cannibal had 1,234 silvers on him.')
  # Lines as the XML frontend sends them; this kill ends at the prompt, not at a decay line
  DownstreamHook.run('You search the <pushBold/><a exist="1" noun="sentinel">veiled sentinel</a><popBold/>.')
  DownstreamHook.run('<pushBold/><a exist="1" noun="sentinel">She</a><popBold/> had 345 silvers on <pushBold/>her<popBold/>.')
  DownstreamHook.run('<prompt time="1793074672">&gt;</prompt>')
  DownstreamHook.run('You search the <pushBold/><a exist="2" noun="lurk">shambling lurk</a><popBold/>.')
  DownstreamHook.run("It didn't carry any silver.")
  # Your own charm, then another character's in the same room (not yours)
  DownstreamHook.run('You summon a swarm of winged armored bugs from your shell fossil charm, which takes off in search of silvers inside an ' \
                     'ornate thanot box.  They locate a pile of 500 coins, reclaiming them and returning to you.  The winged armored bugs retreat.')
  DownstreamHook.run('Penny summons a swarm of painted lady moths from her silvery fossil charm, which takes off in search of silvers.  ' \
                     'They locate a pile of 5,000 coins on the floor, reclaiming them and returning to her.')
  DownstreamHook.run('You gather the remaining 250 coins from inside your box')
  # Coins off the floor (GET COINS); another line that only mentions coins isn't
  DownstreamHook.run('You gather the remaining 1,234 coins.')
  DownstreamHook.run('Bob says, "You gather the remaining 99 coins."')
  # A creature that melts when searched drops its coins and they're gathered
  # before the prompt: the corpse's silver, counted once with the kill. A second
  # gather of the same amount, and GET COINS for another pile, are floor silver.
  DownstreamHook.run('You search the <pushBold/><a exist="3" noun="monstrosity">flesh monstrosity</a><popBold/>.')
  DownstreamHook.run('<pushBold/><a exist="3" noun="monstrosity">It</a><popBold/> had 531 silvers on ' \
                     '<pushBold/><a exist="3" noun="monstrosity">it</a><popBold/>.')
  DownstreamHook.run('With a sound like a swamp bubble erupting, <pushBold/>a <a exist="3" noun="monstrosity">patchwork flesh ' \
                     'monstrosity</a><popBold/> melts into viscous glop.')
  DownstreamHook.run('You gather the remaining 531 <a exist="4" noun="coins">coins</a>.')
  DownstreamHook.run('You gather the remaining 531 <a exist="5" noun="coins">coins</a>.')
  DownstreamHook.run('You gather the remaining 242 <a exist="6" noun="coins">coins</a>.')
  DownstreamHook.run('<prompt time="1793074672">&gt;</prompt>')
  # A selling script reporting its own visits (only heard with track_shops off)
  A::Settings.instance_variable_set(:@current, cfg.merge(track_shops: false))
  A::SilverManager.record_vendor_visit('gemshop', NOW - 100, NOW - 50, 12_345)
  A::Database.record_item_sale(WHO, 'a black opal', 'opal', 5000, 'gemshop', 'Bob', 2)
  A::SilverManager.stop # records the kill still being read
  sleep 0.5
  kills = A::Database.all('SELECT creature, total_silver, game, character FROM kill_stats ORDER BY creature')
  result = {
    'hook_registered' => hook, 'cfg_hunt' => cfg[:hunt_script],
    'kills' => kills.map(&:values),
    'box' => A::Database.all("SELECT amount FROM silver_events WHERE source_category = 'box' ORDER BY amount").map { |r| r['amount'] },
    'floor' => A::Database.all("SELECT amount FROM silver_events WHERE source_category = 'floor'").map { |r| r['amount'] }.sort,
    'visit_seconds' => A::Database.one('SELECT duration_seconds FROM vendor_visits')['duration_seconds'],
    'unit_price' => A::Database.one('SELECT unit_price FROM item_sales')['unit_price']
  }
  result['hook_removed'] = !DownstreamHook.names.include?('GS4Analytics::SilverManager')

when 'reports'
  A::Database.connect!
  seed_history
  A::Database.reader do |conn|
    labels = A::Report.labels(conn)
    texts = {
      'character' => A::Report::Text.character_summary(conn),
      'exp'       => A::Report::Text.exp_summary(conn, 'weekly'),
      'bounty'    => A::Report::Text.bounty_summary(conn, WHO, 'monthly'),
      'cycle'     => A::Report::Text.cycle_summary(conn, WHO, 'weekly')
    }
    ranges = %w[daily weekly monthly ytd total].to_h do |range|
      [range, [A::Report::Text.exp_summary(conn, range), A::Report::Text.bounty_summary(conn, WHO, range),
               A::Report::Text.cycle_summary(conn, WHO, range)].map(&:size).min]
    end
    result = {
      'labels'             => labels,
      'lengths'            => texts.transform_values(&:size),
      'ascii'              => texts.values.all? { |text| text.join.ascii_only? },
      'widest'             => texts.values.flatten.map(&:length).max,
      'names_in_character' => texts['character'].join.scan(/Splinter|April/).uniq.sort,
      'range_lines'        => ranges,
      'bad_range'          => A::Report::Text.exp_summary(conn, 'bogus').first,
      # One 30-minute hunt and the 10-minute rest after it, both carrying the reason
      'reason_rows'        => A::Report::Text.reason_section(
        [{ 'cycle_type' => 'hunt', 'rest_reason' => 'encumbered.', 'duration_seconds' => 1800 },
         { 'cycle_type' => 'rest', 'rest_reason' => 'encumbered.', 'duration_seconds' => 600 },
         { 'cycle_type' => 'hunt', 'rest_reason' => 'unhandled exit', 'duration_seconds' => 300 }]
      ).grep(/encumbered|unhandled/).map { |line| line.split('|').map(&:strip).reject(&:empty?) }
    }
  end

when 'dashboard'
  # The API the hosted dashboard reads: /api/meta, /api/db, CORS for the site,
  # the redirect, and the request limits and Host check kept from before
  A::Database.connect!
  seed_history
  A::Database.flush
  port = 38_000 + (Process.pid % 1000)
  A::Dashboard.start(port)
  sleep 0.3
  site = 'https://analytics.elanthia.online'
  # [status, { lowercased header => value }, body] for a request sent as given
  raw = lambda do |verb, path, headers|
    socket = TCPSocket.new('127.0.0.1', port)
    socket.write("#{verb} #{path} HTTP/1.1\r\n#{headers.map { |h| "#{h}\r\n" }.join}Connection: close\r\n\r\n")
    head, body = socket.read.b.split("\r\n\r\n", 2)
    status, *fields = head.split("\r\n")
    [status.split[1], fields.to_h { |f| k, v = f.split(': ', 2); [k.downcase, v] }, body.to_s]
  ensure
    socket&.close
  end
  get = ->(path, *headers) { raw.call('GET', path, ['Host: 127.0.0.1'] + headers) }
  rows = lambda do |image|
    file = File.join(DATA_DIR, "image-#{rand(1_000_000)}.db")
    File.binwrite(file, image)
    db = Sequel.sqlite(file)
    db[:cycles].count.tap { db.disconnect }
  end

  _, _, meta_body = get.call('/api/meta')
  meta = JSON.parse(meta_body)
  db_status, db_headers, image = get.call("/api/db?token=#{meta['token']}")
  result = {
    'meta' => [meta['app'], meta['api'], meta['schema_version'] == A::Database::SCHEMA_VERSION, meta['script_version'] == A::VERSION,
               meta['db_bytes'] == image.bytesize],
    'db'   => [db_status, db_headers['content-type'], db_headers['x-analytics-token'] == meta['token'],
               rows.call(image) == A::Database.one('SELECT COUNT(*) AS n FROM cycles')['n']]
  }
  # No write: same token and the same image, not rebuilt. A write from the
  # collector (another connection): a new token, and the new row is in the
  # image even before a checkpoint moves it out of the WAL.
  first = A::Dashboard.snapshot
  again = A::Dashboard.snapshot
  before = rows.call(again.last)
  A::Database.start_cycle(WHO, :idle, 'idle', 'crags', {})
  wal_bytes = File.size?("#{A::Database.file}-wal").to_i
  after = A::Dashboard.snapshot
  result['token'] = [first.first == again.first, first.last.equal?(again.last), after.first != first.first,
                     rows.call(after.last) == before + 1, wal_bytes.positive?]
  # An older sqlite3 gem without Database#serialize: VACUUM INTO gives the same rows
  real = A::Database.api_reader
  no_serialize = SimpleDelegator.new(real)
  def no_serialize.synchronize = yield(Object.new)
  result['fallback'] = rows.call(A::Dashboard.send(:image_of, no_serialize)) == before + 1
  real.disconnect

  status_of = ->(response) { response[0] }
  cors_of = ->(response) { response[1].values_at('access-control-allow-origin', 'vary', 'access-control-expose-headers') }
  result['cors'] = {
    'site'         => [status_of.call(r = get.call('/api/meta', "Origin: #{site}")), *cors_of.call(r)],
    'local_copy'   => get.call('/api/meta', 'Origin: http://localhost:8000')[1]['access-control-allow-origin'],
    'evil'         => [status_of.call(r = get.call('/api/meta', 'Origin: https://evil.example')), r[1]['access-control-allow-origin']],
    'shared_pages' => status_of.call(get.call('/api/db', 'Origin: https://elanthia-online.github.io')),
    'no_origin'    => [status_of.call(r = get.call('/api/meta')), r[1]['access-control-allow-origin']],
    'two_origins'  => status_of.call(get.call('/api/meta', "Origin: #{site}", "Origin: #{site}"))
  }
  A::Settings.instance_variable_set(:@current, A::Settings::DEFAULTS.merge(
                                                 dashboard: A::Settings::DEFAULTS[:dashboard].merge(allowed_origins: ['https://someone.github.io/'], site_url: 'http://127.0.0.1:8000/')
                                               ))
  result['cors']['added'] = get.call('/api/meta', 'Origin: https://someone.github.io')[1]['access-control-allow-origin']
  redirect = get.call('/')
  A::Settings.instance_variable_set(:@current, A::Settings::DEFAULTS)
  default_redirect = get.call('/')
  preflight = raw.call('OPTIONS', '/api/db', ['Host: 127.0.0.1', "Origin: #{site}", 'Access-Control-Request-Private-Network: true'])
  result['preflight'] = [preflight[0], preflight[1]['access-control-allow-origin'], preflight[1]['access-control-allow-private-network'],
                         preflight[1]['access-control-allow-methods'], preflight[2]]
  result['redirect'] = [default_redirect[0], default_redirect[1]['location'], redirect[1]['location']]
  result['expected_location'] = "https://analytics.elanthia.online/?live=#{port}"
  result['custom_location'] = "http://127.0.0.1:8000/?live=#{port}"
  headers = db_headers
  result['headers'] = headers.values_at('x-content-type-options', 'cache-control', 'content-security-policy', 'cross-origin-resource-policy')
  result['http_missing'] = get.call('/nope')[0]
  result['http_post'] = raw.call('POST', '/api/meta', ['Host: 127.0.0.1', 'Content-Length: 1'])[0]

  # The status code of a GET with this Host header (nil sends none)
  status_for = ->(host) { raw.call('GET', '/api/meta', host ? ["Host: #{host}"] : [])[0] }
  hosts = ['attacker.example', 'attacker.example:8080', "localhost:#{port}", '127.0.0.1', '[::1]:8080', 'LOCALHOST', nil]
  result['local_hosts'] = hosts.map { |host| status_for.call(host) }
  raw_status = ->(headers, path = '/api/meta') { raw.call('GET', path, headers)[0] }
  pad = ->(size, tail) { "X-Pad: #{'a' * (size - tail.size - 7)}#{tail}" }
  result['split_headers'] = {
    # a long custom header whose cut-off tail reads as a Host header
    'padded_tail'       => raw_status.call(['Host: attacker.example', pad.call(4096 + 'host:localhost'.size, 'host:localhost')]),
    'padded_long'       => raw_status.call(['Host: attacker.example', pad.call(16_384 + 'host:localhost'.size, 'host:localhost')]),
    'two_hosts'         => raw_status.call(['Host: attacker.example', 'Host: localhost']),
    'two_local_hosts'   => raw_status.call(['Host: localhost', 'Host: localhost']),
    'long_cookie'       => raw_status.call(['Host: localhost', "Cookie: #{'c' * 12_000}"]),
    'too_long_line'     => raw_status.call(['Host: localhost', "Cookie: #{'c' * 20_000}"]),
    'too_many'          => raw_status.call(['Host: localhost'] + Array.new(150) { |i| "X-#{i}: 1" }),
    'long_request_line' => raw_status.call(['Host: localhost'], "/api/meta?x=#{'a' * 5000}")
  }
  # An unexpected error answers 500, still readable by the site (CORS), so it isn't taken for a script that's not running
  A::Dashboard.singleton_class.send(:alias_method, :real_meta, :meta)
  A::Dashboard.define_singleton_method(:meta) { raise 'boom' }
  status500, headers500, = get.call('/api/meta', "Origin: #{site}")
  result['error_500'] = [status500, headers500['access-control-allow-origin']]
  A::Dashboard.singleton_class.send(:alias_method, :meta, :real_meta)
  A::Dashboard.stop
  # lan is refused with an explanation, and the server still binds this computer only
  OUT.clear
  A::CLI.send(:start_dashboard, port, true)
  result['lan'] = [OUT.any? { |line| line.include?('lan is no longer supported') }, A::Dashboard.instance_variable_get(:@server).addr[3],
                   OUT.any? { |line| line.include?("https://analytics.elanthia.online/?live=#{port}") }]
  A::Dashboard.stop
  # a port that can't be listened on is said, and the script goes on
  OUT.clear
  result['bad_port'] = begin
    A::CLI.send(:start_dashboard, 99_999, false)
    [A::Dashboard.running?, OUT.any? { |line| line.include?("can't listen on port 99999") }]
  rescue StandardError => e
    e.class.name
  end
  result['stopped'] = [!A::Dashboard.running?, A::Dashboard.instance_variable_get(:@api_conn).nil?]

when 'autostart'
  # dashboard.autostart: starts the API unless it already runs, here or in
  # another session (stood in for by a listener that answers as analytics.lic)
  A::Database.connect!
  port = 39_000 + (Process.pid % 1000)
  cli = A::CLI
  default = A::Settings::DEFAULTS[:dashboard][:autostart]
  OUT.clear
  cli.send(:autostart_dashboard, port)
  fresh = [A::Dashboard.running?, OUT.any? { |l| l.include?("live=#{port}") }]
  OUT.clear
  cli.send(:autostart_dashboard, port) # again in this session: nothing to do
  again = [A::Dashboard.running?, OUT.empty?]
  A::Dashboard.stop
  # another session's API on the port
  other = lambda do |body|
    server = TCPServer.new('127.0.0.1', port)
    thread = Thread.new do
      loop do
        client = server.accept
        client.readpartial(4096)
        client.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n#{body}")
        client.close
      end
    rescue IOError, Errno::EBADF
      nil
    end
    [server, thread]
  end
  server, thread = other.call(JSON.generate('app' => 'analytics', 'api' => 1))
  OUT.clear
  cli.send(:autostart_dashboard, port)
  elsewhere = [A::Dashboard.running?, OUT.any? { |l| l.include?('already fed by another session') }]
  # the other session took the port between this one's check and its start
  OUT.clear
  cli.send(:start_dashboard, port, false)
  raced = [A::Dashboard.running?, OUT.any? { |l| l.include?('already fed by another session') }, OUT.none? { |l| l.include?('Try ;') }]
  server.close
  thread.kill
  # something else holds the port: said, not taken for analytics.lic
  server, thread = other.call('{"app":"something else"}')
  OUT.clear
  cli.send(:autostart_dashboard, port)
  taken = [A::Dashboard.running?, OUT.any? { |l| l.include?("Port #{port} is already in use") }]
  server.close
  thread.kill
  result = { 'default' => default, 'fresh' => fresh, 'again' => again, 'elsewhere' => elsewhere, 'raced' => raced, 'taken' => taken,
             'nobody' => A::Dashboard.answering?(port, wait: 0.5) }

when 'cli'
  A::Database.connect!
  seed_history
  cli = A::CLI
  cli.send(:execute, %w[report cycle weekly])
  report = lines(OUT)
  OUT.clear
  cli.send(:execute, %w[status])
  status = lines(OUT)
  OUT.clear
  cli.send(:execute, %w[maintenance stats])
  stats = lines(OUT)
  OUT.clear
  cli.send(:execute, %w[help])
  help = lines(OUT)
  cli.send(:install_hook)
  caught = [UpstreamHook.run(';analytics report exp'), UpstreamHook.run('<c>;analytics status')]
  queue = cli.instance_variable_get(:@commands)
  queue.clear
  dashboard = [';analytics --dashboard', ';analytics --dashboard=9000 --lan', ';analytics --lan'].map do |line|
    [UpstreamHook.run(line), (queue.empty? ? nil : queue.pop)]
  end
  queue.clear
  UpstreamHook.run(';analytics report exp')
  UpstreamHook.run('<c>;analytics status')
  passed = ['look', ';other thing', ';analytics'].map { |line| UpstreamHook.run(line) }
  result = {
    'report' => report.include?('Summary'), 'status' => status.include?('Database:'),
    'stats' => stats.include?('cycles:') && stats.include?('combat_stats:') && stats.include?('pool_depth:'), 'help' => help.include?('Usage'),
    'help_paths' => [help.include?("Settings: #{File.join(DATA_DIR, 'analytics.yaml')} (every character)") &&
      help.include?("#{File.join(DATA_DIR, 'GS3', 'Splinter', 'analytics.yaml')} (this character's overrides)"),
                     help.include?("Database: #{File.join(DATA_DIR, 'analytics.db')}"), help.include?('<Lich data>')],
    'caught' => caught, 'dashboard' => dashboard, 'passed' => passed,
    'queued' => cli.instance_variable_get(:@commands).size
  }

when 'standalone'
  # No collector: the reader opens through Lich's helper (so it gets Lich's
  # lock waits), reports work from it, and a missing file is reported
  A::Database.connect!
  seed_history
  A::Database.close
  result['connected'] = A::Database.connected?
  $sqlite_opened.clear
  $sqlite_hooked.clear
  A::Database.reader do |conn|
    result['report_lines'] = A::Report::Text.character_summary(conn).size
  end
  result['opened'] = $sqlite_opened == [A::Database.file]
  result['hooked'] = !$sqlite_hooked.empty?
  A::Database.close
  FileUtils.rm_f(A::Database.file)
  result['missing'] = begin
    A::Database.reader
    false
  rescue A::Database::Missing
    true
  end

when 'game_text'
  # Vendor sales and bank balances read from the game text, in the XML frontend's format
  A::Database.connect!
  A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  feed = ->(*lines) { lines.each { |line| DownstreamHook.run(line) } }
  count = ->(table) { A::Database.one("SELECT COUNT(*) AS n FROM #{table}")['n'] }
  settle = -> { sleep 0.4 }

  feed.call(
    'The <pushBold/><a exist="1" noun="Kahlyr">jeweler Kahlyr</a><popBold/> takes the <a exist="2" noun="ingot">gold ingot</a>, ' \
    'gives it a careful examination and hands you 1,250 silver for it.',
    'Walsor Gryhm takes your <a exist="3" noun="orb">quartz orb</a>, glances at it briefly, then hands you 410 silver coins.',
    'The pawnbroker takes your <a exist="4" noun="crystal">ayanad crystal</a>, glances at it briefly, then hands you 77 silver coins.',
    'The <pushBold/><a exist="5" noun="Jyhm">locksmith Jyhm</a><popBold/> accepts your silvers.',
    'The teller carefully records the transaction, hands you 2,500 silvers, and says, "This brings your total to 357,850,148 silvers."'
  )
  settle.call
  sales = A::Database.all("SELECT vendor_type, vendor_name, amount FROM silver_events WHERE source_category = 'sale' ORDER BY amount")
  items = A::Database.all('SELECT item_name, item_noun, total_price, vendor_type, vendor_name FROM item_sales ORDER BY total_price')
  withdraw_rows = count.call('bank_snapshots')
  hook_ignored = (A::SilverManager.record_vendor_silver(999, 'gemshop', 'Bob'); A::Database.flush; count.call('silver_events'))

  # A BANK ACCOUNT block names the bank, so later deposits update it
  feed.call('You currently have the following amounts on deposit:', '', '<output class="mono"/>',
            '      Vornavis Bank of Solhaven: 422,471,304', '                          Total: 422,471,304',
            '<output class=""/>', 'You currently have 0 inter-town bank transfer options available.')
  settle.call
  feed.call('You deposit 4,812 silvers into your account.  The teller carefully records the transaction and says, ' \
            '"Thank you, <a exist="-1" noun="Tysong">Tysong</a>.  This brings your total to 422,476,116 silvers.  Have a nice day!"')
  settle.call
  one_bank = A::Database.all('SELECT bank_name, balance, delta_silver, snapshot_type FROM bank_snapshots ORDER BY rowid').map(&:values)

  # With two banks the deposit's bank is unknown; the total still moves by the amount
  feed.call('You currently have the following amounts on deposit:', '      Bank A: 100', '      Bank B: 200', '      Total: 300')
  settle.call
  rows_before = count.call('bank_snapshots')
  feed.call('You deposit 50 silvers into your account.  The teller carefully records the transaction and says, ' \
            '"Thank you, Tysong.  This brings your total to 250 silvers.  Have a nice day!"')
  settle.call
  two_bank_deposit = A::Database.all('SELECT bank_name, balance, delta_silver FROM bank_snapshots WHERE rowid > ' \
                                     '(SELECT MAX(rowid) FROM bank_snapshots) - ? ORDER BY rowid',
                                     count.call('bank_snapshots') - rows_before).map(&:values)

  # take_snapshot reads the same output the hook sees, and must not record it twice
  $bank_lines = ['You currently have the following amounts on deposit:', '      Bank A: 100', '      Bank B: 250', '      Total: 350']
  $feed_hook = true
  rows_before = count.call('bank_snapshots')
  A::SilverManager.take_snapshot
  settle.call
  command_rows = count.call('bank_snapshots') - rows_before
  $feed_hook = false

  # Both readers can be turned off
  A::Settings.current[:parse_sales] = false
  A::Settings.current[:parse_bank] = false
  before = [count.call('silver_events'), count.call('item_sales'), count.call('bank_snapshots')]
  feed.call('The pawnbroker takes your <a exist="4" noun="crystal">ayanad crystal</a>, glances at it briefly, then hands you 77 silver coins.',
            'You deposit 50 silvers into your account.  The teller carefully records the transaction and says, ' \
            '"Thank you, Tysong.  This brings your total to 999 silvers.  Have a nice day!"')
  settle.call
  disabled = [count.call('silver_events'), count.call('item_sales'), count.call('bank_snapshots')] == before
  A::SilverManager.record_vendor_silver(999, 'gemshop', 'Bob')
  A::Database.flush
  hook_when_off = count.call('silver_events') - before.first

  result = {
    'sales' => sales.map(&:values), 'items' => items.map(&:values),
    'withdraw_rows' => withdraw_rows, 'hook_ignored' => hook_ignored,
    'one_bank' => one_bank, 'two_bank_deposit' => two_bank_deposit, 'command_rows' => command_rows,
    'disabled' => disabled, 'hook_when_off' => hook_when_off
  }
  A::SilverManager.stop

when 'bank_moves'
  # Deposits and withdrawals move the total by the amount moved, never by the
  # balance they quote, which belongs to one bank
  A::Database.connect!
  A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  feed = ->(*lines) { lines.each { |line| DownstreamHook.run(line) } }
  settle = -> { sleep 0.4 }
  earned = lambda do
    A::Database.one("SELECT COALESCE(SUM(delta_silver), 0) AS s FROM bank_snapshots WHERE bank_name = '__total__'")['s']
  end
  deposit = ->(amount, total) { "You deposit #{amount} silvers into your account.  The teller carefully records the transaction and says, \"Thank you, Tysong.  This brings your total to #{total} silvers.  Have a nice day!\"" }
  withdraw = ->(amount, total) { "The teller carefully records the transaction, hands you #{amount} silvers, and says, \"This brings your total to #{total} silvers.\"" }

  # First bank line is a withdrawal; the listing then shows silver in a second town
  feed.call(withdraw.call('2,500', '97,500'))
  settle.call
  feed.call('You currently have the following amounts on deposit:', '      Bank of Icemule: 97,500',
            '      Bank of Solhaven: 5,000,000', '      Total: 5,097,500')
  settle.call
  first_listing = earned.call

  # A deposit at a third town, where the balance it quotes is that bank's only
  feed.call(deposit.call('1,000', '1,000'))
  settle.call
  after_deposit = A::Database.one("SELECT balance, delta_silver FROM bank_snapshots WHERE bank_name = '__total__' ORDER BY rowid DESC LIMIT 1").values
  banks_after_deposit = A::Database.latest_balances(WHO).except('__total__')
  feed.call('You currently have the following amounts on deposit:', '      Bank of Icemule: 97,500',
            '      Bank of Solhaven: 5,000,000', '      Bank of Teras: 1,000', '      Total: 5,098,500')
  settle.call
  feed.call(withdraw.call('500', '96,000'))
  settle.call
  result = {
    'first_listing_earned' => first_listing, 'after_deposit' => after_deposit,
    'banks_after_deposit' => banks_after_deposit, 'earned' => earned.call,
    'last_total' => A::Database.latest_balances(WHO)['__total__']
  }
  A::SilverManager.stop

when 'locked_cycle'
  # A hunt -> rest change while another session holds the write lock
  quick_busy_timeouts
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  manager = A::CycleManager
  A::Database.flush
  hunt = A::Database.start_cycle(WHO, :hunt, 'bigshot', 'splinter_crags', { exp_total: 100 })
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', NOW - 1800, hunt)
  { :@who => WHO, :@cfg => cfg, :@current_state => :hunt, :@current_cycle_id => hunt,
    :@rest_steps => Hash.new(0.0), :@last_bigshot_status => :resting }.each { |name, value| manager.instance_variable_set(name, value) }
  bounty = A::BountyManager
  bounty.instance_variable_set(:@who, WHO)
  $task = nil
  $running = ['bigshot']
  $rest_reason = 'encumbered.'

  lock = hold_write_lock
  changed_at = Time.now.to_i
  manager.send(:transition_to, :rest)
  bounty.send(:handle_reward, 100, 200, 300)
  sleep 0.5
  during = { 'state' => manager.current_state.to_s, 'cycle' => !manager.current_cycle_id.nil?,
             'hunt_open' => A::Database.one('SELECT end_time FROM cycles WHERE cycle_id = ?', hunt)['end_time'].nil? }
  lock.execute('COMMIT')
  lock.close
  flushed = A::Database.flush(10)
  ended = A::Database.one('SELECT end_time, duration_seconds, rest_reason FROM cycles WHERE cycle_id = ?', hunt)
  rest = A::Database.one('SELECT cycle_type, start_time, rest_reason FROM cycles WHERE cycle_id = ?', manager.current_cycle_id)
  result = {
    'during' => during, 'flushed' => flushed,
    'hunt' => [ended['duration_seconds'].to_i.between?(1799, 1802), ended['rest_reason'], ended['end_time'].to_i <= changed_at + 1],
    'rest' => [rest['cycle_type'], rest['rest_reason'], rest['start_time'].to_i <= changed_at + 1],
    'bounty' => A::Database.one('SELECT status, silver_reward FROM bounties').values,
    'busy_reported' => OUT.any? { |line| line.include?('ERROR (database busy)') }
  }
  A::Database.close

when 'killed_writer'
  # ;kill stops the writer before before_dying runs. What it left, and what the
  # managers queue while stopping, is written by close, in order.
  quick_busy_timeouts
  A::Database.connect!
  A::Database.flush
  lock = hold_write_lock
  id = A::Database.new_id
  A::Database.async { A::Database.start_cycle(WHO, :hunt, 'bigshot', nil, {}, id: id, at: NOW - 600) }
  sleep 0.4 # the writer finds the lock and backs off
  A::Database.instance_variable_get(:@writer).kill
  sleep 0.1
  A::Database.async { A::Database.end_cycle(id, {}, 'killed', at: NOW) } # what CycleManager.stop queues
  lock.execute('COMMIT')
  lock.close
  A::Database.close
  A::Database.connect!
  row = A::Database.one('SELECT duration_seconds, rest_reason FROM cycles WHERE cycle_id = ?', id)
  result['written'] = [row['duration_seconds'], row['rest_reason']]
  result['lost_reported'] = OUT.any? { |line| line.include?('were lost') }

  # Still locked when it stops: one wait, then the count of what was lost
  lock = hold_write_lock
  3.times { |i| A::Database.async { A::Database.set_metadata("lost.#{i}", 'x') } }
  sleep 0.3
  A::Database.instance_variable_get(:@writer).kill
  started = Time.now
  A::Database.close
  result['stop_seconds'] = (Time.now - started).round(1)
  result['lost_line'] = OUT.grep(/were lost/).last.to_s.sub('[analytics] ', '')
  lock.execute('ROLLBACK')
  lock.close

when 'close_writes'
  db = A::Database
  db.connect!
  db.flush
  event = lambda do |tag|
    db.db[:silver_events].insert(event_id: db.new_id, game: 'GS3', character: 'Splinter', timestamp: NOW, source_category: tag, amount: 1)
  end
  count = ->(tag) { db.db[:silver_events].where(source_category: tag).count }
  # close drains the queue after closing it (#write_remaining); a hook still
  # running then (removed, but mid-line) queues a write: it is written in place
  db.instance_variable_get(:@queue).close
  db.async { event.call('late') }
  result['late'] = count.call('late')
  db.close
  db.connect!
  # Lich holds a ;kill back until COMMIT returns, so it lands after the
  # commit and before the queue is shifted: the job must not run again in close
  # ;kill comes from another thread (a thread can't defer killing itself)
  go = Queue.new
  killer = Thread.new do
    go.pop
    db.instance_variable_get(:@writer).kill
  end
  db.async do
    event.call('once')
    db.db.after_commit do
      go << :now unless go.closed? # the kill arrives the moment COMMIT returns...
      go.close
      sleep 0.3                    # ...while the job's bookkeeping is still to run
    end
  end
  killer.join(2)
  sleep 0.5
  result['writer_alive'] = db.instance_variable_get(:@writer)&.alive?
  db.close
  db.connect!
  result['once'] = count.call('once')

when 'baseline'
  # With no bank total yet, starting takes one listing; after that it doesn't
  A::Database.connect!
  A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  manager = A::SilverManager
  count = -> { A::Database.flush; A::Database.one('SELECT COUNT(*) AS n FROM bank_snapshots')['n'] }
  A::Settings.current[:parse_bank] = false
  off = [manager.take_baseline_now, count.call]
  A::Settings.current[:parse_bank] = true
  first = [manager.take_baseline_now, count.call]
  again = [manager.take_baseline_now, count.call]
  DownstreamHook.run('You deposit 1,000 silvers into your account.  The teller carefully records the transaction and says, ' \
                     '"Thank you, Splinter.  This brings your total to 1,501,000 silvers.  Have a nice day!"')
  sleep 0.4
  A::Database.flush
  result = {
    'off' => off, 'first' => first, 'again' => again,
    'types' => A::Database.all("SELECT DISTINCT snapshot_type FROM bank_snapshots WHERE snapshot_type = 'baseline'").map(&:values),
    'deposit' => A::Database.one("SELECT balance, delta_silver FROM bank_snapshots WHERE snapshot_type = 'deposit'").values
  }
  manager.stop

when 'notes'
  # Sales paid with promissory notes or with a gem pouch, note deposits, and
  # an eherbs note round trip that only the teller's balances reveal
  A::Database.connect!
  A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  feed = ->(*lines) { lines.each { |line| DownstreamHook.run(line) } }
  settle = -> { sleep 0.3; A::Database.flush }
  kahlyr = 'The <pushBold/><a exist="66987" noun="Kahlyr">jeweler Kahlyr</a><popBold/>'
  feed.call(
    "#{kahlyr} takes the <a exist=\"1968237\" noun=\"ring\">diamond ring</a>, gives it a careful examination and and says, " \
    '"I don\'t have that much spare silver, so I will have to give you a bank note for it."  She then hands you a ' \
    '<a exist="1979973" noun="note">Vornavis promissory note</a> for 22,555 silvers.',
    "#{kahlyr} takes the <a exist=\"1108966\" noun=\"pouch\">ruby red pouch</a>, inspects the contents carefully, and removes " \
    'the gems she is interested in.  She hands it back to you, along with 8,120 silver.',
    "#{kahlyr} takes the <a exist=\"1108967\" noun=\"pouch\">leather gem pouch</a>, inspects the contents carefully, and removes " \
    'the gems she is interested in.  She hands it back to you and says, "I don\'t have that much spare silver, so I will have ' \
    'to give you a <a exist="1200062" noun="note">Vornavis promissory note</a> for it."',
    "#{kahlyr} removes the gems and hands you a <a exist=\"1698202\" noun=\"note\">Vornavis promissory note</a> for 23,136 silvers.",
    # Someone else's pouch sale, then the 2026-11-05 lines the earlier patterns missed
    "#{kahlyr} takes the <a exist=\"1108968\" noun=\"pouch\">leather gem pouch</a>, inspects the contents carefully, and removes " \
    'the gems she is interested in.  She hands it back to April and says, "I don\'t have that much spare silver, so I will have ' \
    'to give you a <a exist="1200063" noun="note">Vornavis promissory note</a> for it."',
    "#{kahlyr} removes the gems and hands April a <a exist=\"1698203\" noun=\"note\">Vornavis promissory note</a>.",
    'You ask Ragnoz if he would like to buy the contents of an embroidered sage green silk cloak.',
    'Ragnoz takes the <a exist="20716945" noun="cloak">sage green silk cloak</a>, inspects the contents carefully and removes ' \
    'the item he is interested in.  Ragnoz hands it back to you, along with 819 silver.',
    "<inv id='stow'> a <a exist=\"2\" noun=\"wand\">wand</a></inv>You offer to sell your " \
    '<a exist="20748012" noun="shield">veil iron shield</a> to Walsor Gryhm.',
    '<pushBold/><a exist="10421" noun="Walsor Gryhm">Walsor Gryhm</a><popBold/> says, "I\'m afraid I don\'t have that much silver ' \
    'on hand, <a exist="-1" noun="Splinter">Splinter</a>, so I\'ll have to give you a <a exist="3" noun="note">Vornavis promissory note</a> for it."',
    'He scribbles out a <a exist="3" noun="note">Vornavis promissory note</a> for 23,760 silvers and hands it to you.',
    'You offer to sell your <a exist="1039576912" noun="grimoire">black leather grimoire</a> to the pawnbroker.',
    'The pawnbroker says, "I\'m afraid I don\'t have that much silver on hand, Splinter, so I\'ll have to give you a ' \
    '<a exist="4" noun="note">Vornavis promissory note</a> for it."',
    'He scribbles out a <a exist="4" noun="note">Vornavis promissory note</a> for 21,905 silvers and hands it to you.'
  )
  settle.call
  sales = A::Database.all('SELECT item_name, item_noun, total_price, vendor_name FROM item_sales ORDER BY rowid').map(&:values)
  vendors = A::Database.all('SELECT vendor_type, vendor_name, amount FROM silver_events ORDER BY rowid').map(&:values)

  total = -> { A::Database.latest_balances(WHO)['__total__'] }
  deposit = ->(amount, balance) { "You deposit #{amount} silvers into your account.  The teller carefully records the transaction and says, \"Thank you, Splinter.  This brings your total to #{balance} silvers.  Have a nice day!\"" }
  feed.call('You currently have the following amounts on deposit:', '      Bank A: 1,000,000', '      Bank B: 500,000',
            '      Total: 1,500,000')
  settle.call
  steps = []
  $room_id = 100 # Bank A's teller
  feed.call(deposit.call('15,750', '1,015,750'))
  settle.call
  steps << total.call
  feed.call('The teller purses her lips and says, "Hmm, we will have to give you a <a exist="1" noun="note">Vornavis promissory note</a> ' \
            'for that amount."  The teller makes some marks on a blank <a exist="1" noun="note">note</a> and hands it to you, ' \
            'saying "That is a 0 silver surcharge.  Have a nice day."')
  $room_id = 200 # the herbalist spends 90 of the 99
  $room_id = 100
  feed.call('You deposit your <a exist="1" noun="note">note</a> worth 9 into your account.  The teller carefully records the ' \
            'transaction and says, "Thank you, <a exist="-1" noun="Splinter">Splinter</a>.  This brings your total to 1,015,660 silvers.  Have a nice day!"')
  settle.call
  steps << total.call
  moves = A::Database.all("SELECT snapshot_type, delta_silver, timestamp FROM bank_snapshots WHERE bank_name = '__total__' " \
                          'ORDER BY rowid DESC LIMIT 3').reverse
  feed.call('<inv id="stow"> a <a exist="2" noun="wand">wand</a></inv>You hand over your notes to the teller, who nods, carefully ' \
            'recording each amount.  She says, "That\'s a total of 50,000 silvers, bringing your balance to 1,065,660 silvers."')
  settle.call
  steps << total.call
  $room_id = 300 # Bank B, in another town
  feed.call('The teller carefully records the transaction, hands you 2,500 silvers, and says, "This brings your total to 497,500 silvers."')
  settle.call
  steps << total.call
  feed.call('You currently have the following amounts on deposit:', '      Bank A: 1,065,660', '      Bank B: 497,500',
            '      Total: 1,563,160')
  settle.call
  listing = A::Database.one("SELECT balance, delta_silver FROM bank_snapshots WHERE bank_name = '__total__' ORDER BY rowid DESC LIMIT 1").values
  result = { 'sales' => sales, 'vendors' => vendors, 'totals' => steps, 'listing' => listing,
             'moves' => moves.map { |row| row.values_at('snapshot_type', 'delta_silver') },
             'one_stamp' => moves.last(2).map { |row| row['timestamp'] }.uniq.size }
  A::SilverManager.stop

when 'other_towns'
  # Wording from other towns (Cold River, Mist Harbor, Kraken's Fall, Icemule), each line ending in
  # "\r\n" as the game sends it
  A::Database.connect!
  A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  feed = ->(*lines) { lines.each { |line| DownstreamHook.run("#{line}\r\n") } }
  settle = -> { sleep 0.3; A::Database.flush }
  feed.call('You currently have the following amounts on deposit:', '      Mist Harbor: 1,000,000', '      Total: 1,000,000')
  settle.call
  feed.call(
    # The furrier pays a pouch of skins with "a note", the gemcutter with a bond note
    'Bramblefist takes the black cordovan apron, inspects the contents carefully and removes the items he is interested in.  ' \
    'Bramblefist hands it back to you and says, "I don\'t have that much spare silver, so I will have to give you a Northwatch bond note for it."',
    'Bramblefist removes the items and hands you a note for 122,375 silvers.',
    'The gemcutter takes the canvas bag, inspects the contents carefully, and removes the gems he is interested in.  He hands it back ' \
    'to you and says, "I don\'t have that much spare silver, so I will have to give you a Northwatch bond note for it."',
    'The gemcutter removes the gems and hands you a Northwatch bond note for 45,630 silvers.',
    # Someone else's pouch at the same jeweler: not ours
    'The jeweler Etaenia takes the climbing pack, inspects the contents carefully, and removes the gems she is interested in.  ' \
    'She hands it back to April and says, "I don\'t have that much spare silver, so I will have to give you a Mist Harbor promissory note for it."',
    # A locksmith who isn't introduced as "The locksmith"
    'You ring the chime, and ask Tisanoff if he can open your hickory chest.',
    'He looks over the hickory chest, frowns, and tells you, "Havin\' some trouble, eh?  Of course I could open this, but it\'ll cost ya.  ' \
    'Gimme 5,809 silvers, and I\'ll have it open before you know it."',
    'Tisanoff accepts your silvers.',
    # A purchase
    'Kelph exclaims, "Sold for 450 silvers!"', 'Kelph takes your promissory note and hands you a new one.',
    # The Four Winds teller states no balance for a deposit or a withdrawal
    'You deposit 30,000 silvers into your account.  The teller scribbles the transaction into a book and says, "Thank you, Splinter.  Have a fabulous day!"',
    'The teller scribbles the transaction into a book and hands you 25,000 silvers.',
    'You hand your notes to the teller, who glances over each one and scribbles the amounts in a book.  She says, "They add up to ' \
    '168,005 silvers, bringing your account balance up to 1,173,005."'
  )
  settle.call
  feed.call(
    # Kraken's Fall pays in kraken chits: a pouch, a single gem, and the pawnshop
    'The jeweler Krosane takes the canvas sack, inspects the contents carefully, and removes the gems he is interested in.  He hands it ' \
    'back to you and says, "I don\'t have that much spare silver, so I will have to give you a salt-stained kraken chit for it."',
    'The jeweler Krosane removes the gems and hands you a salt-stained kraken chit for 41,220 silvers.',
    'The jeweler Krosane takes the diamond earrings, gives it a careful examination and and says, "I don\'t have that much spare ' \
    'silver, so I will have to give you a bank note for it."  He then hands you a salt-stained kraken chit for 20,910 silvers.',
    'You offer to sell your faewood runestaff to Bushybrow.',
    'Bushybrow says, "I\'m afraid I don\'t have that much silver on hand, Splinter, so I\'ll have to give you a salt-stained kraken chit for it."',
    'He scribbles out a salt-stained kraken chit for 25,000 silvers and hands it to you.',
    # Icemule's locksmith is "The merchant", and the locksmith pools' workers
    'You ring the bell, and ask Blackfinger if he can open your mithril chest.',
    'He looks over the mithril chest, frowns, and tells you, "Havin\' some trouble, eh?  Of course I could open this, but it\'ll cost ya.  ' \
    'Gimme 5,896 silvers, and I\'ll have it open before you know it."',
    'The merchant Blackfinger accepts your silvers.',
    'The worker takes your trunk and says, "Your tip of 750 silvers has been recorded, and the 1,902 silver fee has been collected.  ' \
    'We\'ll get someone on that right away."',
    'Starling Swiftwhistle takes your coffer and says, "Your tip of 750 silvers has been recorded, and the 2,302 silver fee has been ' \
    'collected.  We\'ll get someone on that right away."',
    # A debt paid off at the town clerk
    'The town clerk accepts your silvers.',
    'The town clerk says, "Looks like 265 silvers clears up all your debts in Solhaven.  Good luck keeping it that way."',
    # A fossil charm: a box's coins are box silver. Coins on the ground are a
    # crumbled corpse's, already counted with its kill (this one or an earlier
    # one), or else floor silver. Another character's charm isn't ours.
    'You search the infernal death knight.', 'She had 322 silvers on her.', '<prompt time="1793074672">&gt;</prompt>',
    'You search the tatterdemalion ghast.', 'He had 513 silvers on him.', '<prompt time="1793074672">&gt;</prompt>',
    'You summon a swarm of winged armored bugs from your shell fossil charm, which takes off in search of silvers.  They locate a ' \
    'stack of 322 coins on the ground, reclaiming them and returning to you.  The winged armored bugs retreat back inside the charm.',
    'You summon a swarm of winged armored bugs from your shell fossil charm, which takes off in search of silvers.  They locate some ' \
    'loose 513 coins on the floor, reclaiming them and returning to you.  The winged armored bugs retreat back inside the charm.',
    'You summon a swarm of winged armored bugs from your shell fossil charm, which takes off in search of silvers.  They locate a ' \
    'stack of 322 coins on the ground, reclaiming them and returning to you.  The winged armored bugs retreat back inside the charm.',
    'You summon a swarm of winged armored bugs from your shell fossil charm, which takes off in search of silvers.  They locate a ' \
    'pile of 111 coins on the floor, reclaiming them and returning to you.  The winged armored bugs retreat back inside the charm.',
    'You summon a swarm of winged armored bugs from your shell fossil charm, which takes off in search of silvers inside a badly ' \
    'damaged silver box.  They locate a heap of 1,307 coins, reclaiming them and returning to you.  The winged armored bugs retreat.',
    'Raphael summons a swarm of winged armored bugs from his shell fossil charm, which takes off in search of silvers.  They locate ' \
    'a stack of 640 coins on the floor, reclaiming them and returning to him.'
  )
  settle.call
  result = {
    'sales' => A::Database.all("SELECT vendor_type, vendor_name, amount FROM silver_events WHERE source_category = 'sale' ORDER BY rowid").map(&:values),
    'spent' => A::Database.all("SELECT vendor_type, vendor_name, amount FROM silver_events WHERE source_category = 'expense' ORDER BY rowid").map(&:values),
    'bank'  => A::Database.all("SELECT snapshot_type, delta_silver, balance FROM bank_snapshots WHERE bank_name = '__total__' ORDER BY rowid").map(&:values),
    'coins' => A::Database.all("SELECT source_category, vendor_name, amount FROM silver_events WHERE source_category IN ('box', 'floor') " \
                               'ORDER BY rowid').map(&:values),
    'kills' => A::Database.all('SELECT creature, total_silver FROM kill_stats ORDER BY creature').map(&:values)
  }
  A::SilverManager.stop

when 'teller_listing'
  # A listing between two lines at the same teller already includes what
  # happened in between, so the second line must not count it again
  A::Database.connect!
  A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  feed = ->(*lines) { lines.each { |line| DownstreamHook.run(line) } }
  settle = -> { sleep 0.3; A::Database.flush }
  total = -> { A::Database.latest_balances(WHO)['__total__'] }
  listing = lambda do |bank_a, total_silver|
    feed.call('You currently have the following amounts on deposit:', "      Bank A: #{bank_a}", '      Bank B: 500,000',
              "      Total: #{total_silver}")
    settle.call
  end
  listing.call('1,000,000', '1,500,000')
  $room_id = 100
  feed.call('You deposit 15,750 silvers into your account.  The teller carefully records the transaction and says, ' \
            '"Thank you, Splinter.  This brings your total to 1,015,750 silvers.  Have a nice day!"')
  settle.call
  # a 99,000 note withdrawn (its line names no amount), then a listing
  listing.call('916,750', '1,416,750')
  feed.call('You deposit your <a exist="1" noun="note">note</a> worth 9,000 into your account.  The teller carefully records ' \
            'the transaction and says, "Thank you, Splinter.  This brings your total to 925,750 silvers.  Have a nice day!"')
  settle.call
  after_note = total.call
  listing.call('925,750', '1,425,750')
  last_delta = -> { A::Database.one("SELECT delta_silver FROM bank_snapshots WHERE bank_name = '__total__' ORDER BY rowid DESC LIMIT 1")['delta_silver'] }
  result = { 'after_note' => after_note, 'next_listing' => last_delta.call }

  # The same through take_snapshot (the first-run listing and the public hook)
  feed.call('You deposit 1,000 silvers into your account.  The teller carefully records the transaction and says, ' \
            '"Thank you, Splinter.  This brings your total to 926,750 silvers.  Have a nice day!"')
  settle.call
  $bank_lines = ['You currently have the following amounts on deposit:', '      Bank A: 827,750', '      Bank B: 500,000',
                 '      Total: 1,327,750']
  A::SilverManager.take_snapshot
  feed.call('You deposit your <a exist="1" noun="note">note</a> worth 9,000 into your account.  The teller carefully records ' \
            'the transaction and says, "Thank you, Splinter.  This brings your total to 836,750 silvers.  Have a nice day!"')
  settle.call
  result['after_snapshot'] = total.call
  A::SilverManager.stop

when 'cycle_edges'
  # The collector's first moments, and a hunt that ends in a death
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  manager = A::CycleManager
  $running = []
  # Left open by the last login: its connection dropped 8 minutes ago, mid-hunt
  # (the login was last seen then), and an older rest a crash left behind
  A::Database.record_login(WHO, NOW - 7200, NOW - 7200)
  A::Database.touch_login(WHO, NOW - 7200, NOW - 480)
  dropped = A::Database.start_cycle(WHO, :hunt, 'bigshot', 'splinter_crags', {})
  older = A::Database.start_cycle(WHO, :rest, 'rest', 'splinter_crags', {})
  after = A::Database.start_cycle(WHO, :hunt, 'bigshot', 'splinter_crags', {})
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', NOW - 720, dropped)
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', NOW - 3000, older)
  run_sql('UPDATE cycles SET start_time = ?, end_time = ? WHERE cycle_id = ?', NOW - 2900, NOW - 1000, after)
  manager.start(WHO, cfg)
  A::Database.flush
  result['reopened'] = [dropped, older].map { |id| A::Database.one('SELECT end_time - start_time AS s FROM cycles WHERE cycle_id = ?', id)['s'] }
  first = A::Database.one('SELECT cycle_type, start_time FROM cycles WHERE cycle_id = ?', manager.current_cycle_id)
  result['startup'] = [manager.current_state.to_s, first['cycle_type'], (first['start_time'].to_i - Time.now.to_i).abs <= 2]
  manager.instance_variable_set(:@running, false)
  manager.instance_variable_get(:@thread).join(2)

  hunt = A::Database.start_cycle(WHO, :hunt, 'bigshot', 'splinter_crags', {})
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', NOW - 600, hunt)
  { :@current_state => :hunt, :@current_cycle_id => hunt, :@cycle_started_at => NOW - 600, :@last_bigshot_status => :resting,
    :@rest_steps => Hash.new(0.0) }.each { |name, value| manager.instance_variable_set(name, value) }
  $running = ['bigshot']
  $rest_reason = 'wounded.'
  manager.send(:transition_to, :rest) # bigshot heads out to rest...
  rest = manager.current_cycle_id
  manager.send(:transition_to, :dead) # ...and dies a few seconds later
  dead = manager.current_cycle_id
  A::Database.flush
  ended = A::Database.one('SELECT end_time, rest_reason FROM cycles WHERE cycle_id = ?', hunt)
  died = A::Database.one('SELECT cycle_type, start_time FROM cycles WHERE cycle_id = ?', dead)
  # Revived: the rest that follows says it recovers from the death
  $running = []
  $rest_reason = ''
  # (each one backdated, so it's long enough to keep)
  backdate = lambda do |id, ago|
    A::Database.flush
    run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', Time.now.to_i - ago, id)
    manager.instance_variable_set(:@cycle_started_at, Time.now.to_i - ago)
  end
  backdate.call(dead, 900)
  manager.send(:transition_to, :rest)
  recovery = manager.current_cycle_id
  backdate.call(recovery, 600)
  # A hunt still going at midnight is cut there, and says so
  manager.send(:transition_to, :hunt)
  cut = manager.current_cycle_id
  backdate.call(cut, 300)
  manager.instance_variable_set(:@day, (Date.today - 1).to_s)
  manager.send(:roll_over_midnight)
  A::Database.flush
  reason_of = ->(id) { A::Database.one('SELECT rest_reason FROM cycles WHERE cycle_id = ?', id)&.[]('rest_reason') }
  result['death'] = {
    'hunt_reason' => ended['rest_reason'], 'short_rest_dropped' => A::Database.all('SELECT 1 FROM cycles WHERE cycle_id = ?', rest).empty?,
    'no_gap' => died['start_time'] == ended['end_time'], 'dead' => died['cycle_type'],
    'after_death' => reason_of.call(recovery), 'midnight' => reason_of.call(cut), 'after_midnight' => reason_of.call(manager.current_cycle_id)
  }

when 'flap'
  # Bigshot starts and goes straight back to resting (still poisoned): the
  # hunt is too short to keep, and the rest before it goes on
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  manager = A::CycleManager
  $running = []
  manager.start(WHO, cfg)
  manager.instance_variable_set(:@running, false)
  manager.instance_variable_get(:@thread).join(2)
  backdate = lambda do |ago|
    A::Database.flush
    run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', Time.now.to_i - ago, manager.current_cycle_id)
    manager.instance_variable_set(:@cycle_started_at, Time.now.to_i - ago)
  end
  $rest_reason = 'wall of thorns poison.'
  manager.send(:transition_to, :rest)
  rest = manager.current_cycle_id
  backdate.call(300)
  manager.instance_variable_get(:@rest_steps)['eloot'] += 100.0
  manager.send(:transition_to, :hunt) # a second or two of bigshot...
  flap = manager.current_cycle_id
  manager.send(:transition_to, :rest) # ...and back to resting
  manager.instance_variable_get(:@rest_steps)['travel'] += 50.0
  A::Database.flush
  open_rest = A::Database.one('SELECT end_time FROM cycles WHERE cycle_id = ?', rest)
  result['rest'] = { 'resumed' => manager.current_cycle_id == rest, 'open' => open_rest['end_time'].nil?,
                     'flap_dropped' => A::Database.all('SELECT 1 FROM cycles WHERE cycle_id = ?', flap).empty? }
  # The same for a hunt cut by a flap of rest: it goes on, without the reason it stopped for
  $rest_reason = ''
  manager.send(:transition_to, :hunt)
  hunt = manager.current_cycle_id
  backdate.call(600)
  started = manager.hunt_start_time
  $rest_reason = 'encumbered.'
  manager.send(:transition_to, :rest)
  $rest_reason = ''
  manager.send(:transition_to, :hunt)
  A::Database.flush
  open_hunt = A::Database.one('SELECT end_time, rest_reason FROM cycles WHERE cycle_id = ?', hunt)
  result['hunt'] = { 'resumed' => manager.current_cycle_id == hunt, 'open' => open_hunt['end_time'].nil?,
                     'reason' => open_hunt['rest_reason'], 'started' => manager.hunt_start_time == started }
  manager.send(:end_current_cycle)
  A::Database.flush
  result['cycles'] = A::Database.all('SELECT cycle_type, end_time - start_time >= 300 AS long, rest_reason FROM cycles ' \
                                     "WHERE cycle_type != 'idle' ORDER BY start_time").map(&:values)
  result['steps'] = A::Database.all('SELECT step, seconds FROM rest_steps WHERE cycle_id = ? ORDER BY step', rest).map(&:values)

when 'timeout_flap'
  # max_hunt_minutes asks for a rest (RELEASE) once; bigshot rests a few seconds and
  # hunts on, and the resumed hunt mustn't ask again at once
  A::Database.connect!
  cfg = A::Settings.load(WHO).merge(max_hunt_minutes: 30)
  manager = A::CycleManager
  $running = []
  fputs = []
  manager.define_singleton_method(:fput) { |cmd| fputs << cmd }
  manager.start(WHO, cfg)
  manager.instance_variable_set(:@running, false)
  manager.instance_variable_get(:@thread).join(2)
  manager.send(:transition_to, :hunt)
  A::Database.flush
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', Time.now.to_i - 1900, manager.current_cycle_id)
  manager.instance_variable_set(:@cycle_started_at, Time.now.to_i - 1900)
  manager.instance_variable_set(:@hunt_start_time, Time.now.to_i - 1900)
  manager.send(:check_hunt_timeout) # 31+ minutes: asks for a rest once
  first = fputs.dup
  manager.send(:check_hunt_timeout)
  once = fputs.size
  $rest_reason = 'hunt timeout'
  manager.send(:transition_to, :rest) # bigshot rests a few seconds (nothing to do)...
  $rest_reason = ''
  manager.send(:transition_to, :hunt) # ...and the hunt resumes
  manager.send(:check_hunt_timeout)
  result = { 'first' => first, 'repeat_without_flap' => once, 'after_flap' => fputs, 'hunt_start_age' => Time.now.to_i - manager.hunt_start_time.to_i }
when 'midnight_dead'
  # Dead across midnight: one death, not two
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  manager = A::CycleManager
  $running = []
  manager.start(WHO, cfg)
  manager.instance_variable_set(:@running, false)
  manager.instance_variable_get(:@thread).join(2)
  manager.send(:transition_to, :dead)
  A::Database.flush
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', Time.now.to_i - 600, manager.current_cycle_id)
  manager.instance_variable_set(:@cycle_started_at, Time.now.to_i - 600)
  manager.instance_variable_set(:@day, (Date.today - 1).to_s)
  manager.send(:roll_over_midnight)
  A::Database.flush
  result['dead_cycles'] = A::Database.one("SELECT COUNT(*) AS n FROM cycles WHERE cycle_type = 'dead'")['n']
  result['report_deaths'] = A::Report.figures(A::Database.db, WHO, 0)['deaths']
when 'midnight_rest'
  # A rest for the item limit across midnight: its alert isn't sent again
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  manager = A::CycleManager
  $running = []
  manager.start(WHO, cfg)
  manager.instance_variable_set(:@running, false)
  manager.instance_variable_get(:@thread).join(2)
  $rest_reason = 'Too many items.'
  manager.send(:transition_to, :rest)
  A::Database.flush
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', Time.now.to_i - 600, manager.current_cycle_id)
  manager.instance_variable_set(:@cycle_started_at, Time.now.to_i - 600)
  manager.instance_variable_set(:@day, (Date.today - 1).to_s)
  manager.send(:roll_over_midnight)
  A::Database.flush
  result['item_alerts'] = OUT.grep(/ITEM LIMIT/).size
  result['item_rests'] = A::Database.one("SELECT COUNT(*) AS n FROM cycles WHERE cycle_type='rest' AND rest_reason LIKE '%item%'")['n']
when 'weapon_check'
  # weapon_loadout with only a right hand set: a box in the left stays there,
  # and a gem in the right that won't stow (a full container) isn't dropped
  A::Database.connect!
  A::Settings.load(WHO)
  hand = Struct.new(:id, :noun, :name)
  gameobj = Module.new do
    def self.right_hand = $hands[:right]
    def self.left_hand = $hands[:left]
  end
  Object.const_set(:GameObj, gameobj) unless defined?(GameObj)
  $hands = { right: hand.new('11', 'gem', 'blue gem'), left: hand.new('12', 'box', 'iron box') }
  sent = []
  manager = A::CycleManager
  manager.define_singleton_method(:fput) { |cmd| sent << cmd }
  manager.define_singleton_method(:dothistimeout) { |cmd, *| sent << cmd; 'There is no room for that.' }
  manager.define_singleton_method(:checkright) { $hands[:right]&.noun }
  manager.define_singleton_method(:checkleft) { $hands[:left]&.noun }
  armed = manager.send(:rearm, { right: 'scepter', get_right: 'get my scepter' })
  result = { 'sent' => sent, 'armed' => armed, 'log' => OUT.grep(/stays in your hand/).size }

when 'idle_recovery'
  # idle_recover_minutes: the walk (go2, which Script.run waits for) and then
  # the rest script, while the cycle watcher goes on ticking
  A::Database.connect!
  cfg = A::Settings.load(WHO).merge(rest_script: 'myrest', profile_room_map: { 'crags' => 1234 })
  calls = Queue.new
  Script.define_singleton_method(:run) { |*args| sleep 0.6; calls << ['run', *args] }
  Script.define_singleton_method(:start) { |*args| calls << ['start', *args] }
  manager = A::CycleManager
  manager.instance_variable_set(:@cfg, cfg)
  manager.instance_variable_set(:@who, WHO)
  manager.define_singleton_method(:profile) { 'crags' }
  began = Time.now
  manager.send(:recover_from_idle, 900)
  returned_after = Time.now - began
  sleep 1
  seen = []
  seen << calls.pop until calls.empty?
  result = { 'returned_at_once' => returned_after < 0.3, 'calls' => seen, 'reason' => $rest_reason }

when 'bigshot_status'
  # Bigshot's own status marks a rest, but only while the script is running
  A::Database.connect!
  manager = A::CycleManager
  manager.instance_variable_set(:@cfg, A::Settings.load(WHO).merge(rest_script: nil))
  signals = lambda do |running, status|
    $running = running
    $bigshot_status = status
    manager.send(:read_signals).slice(:rest, :hunt).values
  end
  result = {
    'hunting'          => signals.call(['bigshot'], :hunting),
    'ready'            => signals.call(['bigshot'], :ready),
    'resting'          => signals.call(['bigshot'], :resting),
    'rest_stop'        => signals.call(['bigshot'], :rest_stop),
    'stale_after_exit' => signals.call([], :resting),
    'nil_status'       => signals.call(['bigshot'], nil)
  }
  manager.instance_variable_get(:@cfg)[:bigshot_status] = false
  result['disabled'] = signals.call(['bigshot'], :resting)
  manager.instance_variable_set(:@cfg, manager.instance_variable_get(:@cfg).merge(bigshot_status: true, rest_script: 'my_rest'))
  result['rest_script_still_works'] = signals.call(['my_rest'], nil)
  manager.instance_variable_get(:@cfg)[:rest_script] = nil
  $running = ['bigshot']
  $bigshot_status = :resting
  result['status_line'] = manager.status.last

when 'interrupted_hunt'
  # Another script (ebounty) stops bigshot to turn in a bounty: the trip is a rest, not idle
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  manager = A::CycleManager
  set = ->(name, value) { manager.instance_variable_set(name, value) }
  start_state = lambda do |state, cycle_type|
    set.call(:@who, WHO)
    set.call(:@cfg, cfg)
    set.call(:@current_state, state)
    set.call(:@rest_steps, Hash.new(0.0))
    set.call(:@last_step_at, nil)
    set.call(:@last_bigshot_status, nil)
    set.call(:@current_cycle_id, A::Database.start_cycle(WHO, cycle_type, 'bigshot', 'splinter_crags', {}))
    run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', NOW - 600, manager.current_cycle_id)
  end
  signals = lambda do |running|
    $running = running
    manager.send(:read_signals).slice(:rest, :hunt).values
  end

  start_state.call(:hunt, :hunt)
  result['hunt_then_trip'] = signals.call(['ebounty'])
  result['hunt_nothing_running'] = signals.call([])
  result['hunt_running'] = signals.call(%w[bigshot eloot])
  set.call(:@last_step_at, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 30)
  result['grace_expired'] = signals.call([])

  hunt_id = manager.current_cycle_id
  $running = ['ebounty']
  $rest_reason = nil
  manager.send(:transition_to, :rest)
  A::Database.flush
  rest = A::Database.one('SELECT cycle_type, rest_reason FROM cycles WHERE cycle_id = ?', manager.current_cycle_id)
  result['reasons'] = [A::Database.one('SELECT rest_reason FROM cycles WHERE cycle_id = ?', hunt_id)['rest_reason'],
                       rest['cycle_type'], rest['rest_reason']]

  # Not after bigshot said it was resting itself
  start_state.call(:hunt, :hunt)
  set.call(:@last_bigshot_status, :resting)
  hunt_id = manager.current_cycle_id
  $rest_reason = 'encumbered.'
  manager.send(:transition_to, :rest)
  A::Database.flush
  result['own_rest_reason'] = A::Database.one('SELECT rest_reason FROM cycles WHERE cycle_id = ?', hunt_id)['rest_reason']

  # An idle character running a script by hand does not start a rest
  start_state.call(:idle, :idle)
  result['idle_manual_script'] = signals.call(['go2'])

  # The idle time after a rest does not take bigshot's leftover rest reason
  idle_id = manager.current_cycle_id
  $rest_reason = 'encumbered.'
  manager.send(:end_current_cycle)
  A::Database.flush
  result['idle_reason'] = A::Database.one('SELECT cycle_type, rest_reason FROM cycles WHERE cycle_id = ?', idle_id).values

  # The hunting script stopped by hand: a stop, not a crash
  start_state.call(:hunt, :hunt)
  set.call(:@last_bigshot_status, :hunting) # bigshot was hunting, so a rest would have shown
  stopped_id = manager.current_cycle_id
  $running = []
  $rest_reason = nil
  manager.send(:transition_to, :idle)
  A::Database.flush
  result['stopped_reason'] = A::Database.one('SELECT rest_reason FROM cycles WHERE cycle_id = ?', stopped_id)['rest_reason']

  # A death read from the game before the death script starts: the cycle is
  # named for the script once it runs
  start_state.call(:hunt, :hunt)
  set.call(:@cfg, cfg.merge(death_script: %w[dead-splinter]))
  $running = []
  manager.send(:transition_to, :dead)
  manager.send(:name_trigger)
  A::Database.flush
  before = A::Database.one('SELECT trigger_script FROM cycles WHERE cycle_id = ?', manager.current_cycle_id)['trigger_script']
  $running = ['dead-splinter']
  manager.send(:name_trigger)
  A::Database.flush
  result['death_trigger'] = [before, A::Database.one('SELECT trigger_script FROM cycles WHERE cycle_id = ?', manager.current_cycle_id)['trigger_script']]
  # The rest after the death, with bigshot's reason from before it still set
  $rest_reason = 'wounded.'
  manager.send(:transition_to, :rest)
  A::Database.flush
  result['after_death'] = A::Database.one('SELECT rest_reason FROM cycles WHERE cycle_id = ?', manager.current_cycle_id)['rest_reason']

when 'town_bounty'
  # A bounty finished in town, with no hunt running, still gets its type and area
  A::Database.connect!
  A::Settings.load(WHO)
  manager = A::BountyManager
  manager.instance_variable_set(:@who, WHO)
  $running = []
  task = lambda do |type, creature = '', area = '', number = nil, item = nil|
    $task = TaskStub.new(type, creature, area, number, item)
  end
  row = lambda do |silver|
    A::Database.one('SELECT bounty_type, creature, area, count_required, status, silver_reward, received_time, completed_time ' \
                    "FROM bounties WHERE silver_reward = #{silver}")
  end
  age_seen = ->(seconds) { manager.instance_variable_get(:@seen)[:at] -= seconds }

  # Seen while the work was still to do, then done and left waiting for the turn-in
  # for a long time (the log's 05:32 gem task: finished in seconds, rewarded 17 minutes later)
  task.call(:gem, '', 'Solhaven', 9, 'piece of leopard skin jasper')
  manager.send(:check_task)
  A::Database.flush
  recorded_while_not_hunting = A::Database.all('SELECT 1 FROM bounties').size
  task.call(:taskmaster)
  manager.send(:check_task)
  age_seen.call(1000)
  manager.send(:handle_reward, 1250, 1000, 4812)
  A::Database.flush
  gem = row.call(4812)

  # Seen, then removed (no task): the reward cannot be for it
  task.call(:herb, '', 'Vornavis', 4, 'blue moss')
  manager.send(:check_task)
  task.call(:none)
  manager.send(:check_task)
  manager.send(:handle_reward, 100, 100, 100)

  # Seen, then replaced by a new assignment that is not trackable yet
  task.call(:cull, 'kobold', 'Icemule', 20)
  manager.send(:check_task)
  task.call(:gem_assignment)
  manager.send(:check_task)
  manager.send(:handle_reward, 55, 55, 55)

  # Never seen
  $task = nil
  manager.send(:handle_reward, 7, 8, 9)
  A::Database.flush

  result = {
    'recorded_while_not_hunting' => recorded_while_not_hunting,
    'gem'                        => gem.values_at('bounty_type', 'creature', 'area', 'count_required', 'status', 'silver_reward'),
    'received_before_completed'  => gem['received_time'] <= gem['completed_time'] - 900,
    'targets'                    => [A::Util.bounty_target('gem', gem['creature'], gem['area']), A::Util.bounty_target('gem', '', 'Solhaven'),
                                     A::Util.bounty_target('herb', 'blue moss', 'Vornavis'), A::Util.bounty_target('cull', 'kobold', 'Icemule'),
                                     A::Util.bounty_target('gem', 'opal', ''), A::Util.bounty_target('escort', '', "Ta'Vaalor")],
    'untracked'                  => A::Database.all("SELECT silver_reward FROM bounties WHERE bounty_type = 'untracked' ORDER BY silver_reward").map { |r| r['silver_reward'] }
  }

when 'bounty_progress'
  # The task's "N more" count becomes the row's done count, across a restart
  A::Database.connect!
  A::Settings.load(WHO)
  manager = A::BountyManager
  manager.instance_variable_set(:@who, WHO)
  manager.instance_variable_set(:@hunt_script, 'bigshot')
  $running = ['bigshot']
  task = ->(type, *rest) { $task = TaskStub.new(type, *rest) }
  last = lambda do
    A::Database.flush
    A::Database.one('SELECT count_required, count_completed, status FROM bounties ORDER BY rowid DESC LIMIT 1').values
  end
  steps = []
  task.call(:cull, 'kobold', 'Icemule', 11)
  manager.send(:check_task)
  steps << last.call
  task.call(:cull, 'kobold', 'Icemule', 7)
  manager.send(:check_task)
  steps << last.call
  manager.send(:clear_tracking) # the collector restarts and adopts the open row
  manager.send(:reconcile_active_bounties)
  task.call(:cull, 'kobold', 'Icemule', 2)
  manager.send(:check_task)
  steps << last.call
  # Done: on the way back to the guard and the taskmaster, nothing is left
  task.call(:guard, '', '', nil)
  manager.send(:check_task)
  steps << last.call
  task.call(:taskmaster, '', '', nil)
  manager.send(:check_task)
  steps << last.call
  manager.send(:handle_reward, 907, 1000, 9070)
  steps << last.call

  # Five killed before the hunt script started still count as done
  manager.send(:clear_tracking)
  $running = []
  task.call(:cull, 'troll', 'Wehnimer', 20)
  manager.send(:check_task)
  task.call(:cull, 'troll', 'Wehnimer', 15)
  manager.send(:check_task)
  $running = ['bigshot']
  manager.send(:check_task)
  before_hunt = [last.call]
  task.call(:cull, 'troll', 'Wehnimer', 14)
  manager.send(:check_task)
  before_hunt << last.call
  task.call(:none, '', '', nil)
  manager.send(:check_task)
  manager.send(:clear_tracking)

  # A gem task worked in town and turned in without a hunt: the count asked
  # for is the first one seen, not the last
  $running = []
  task.call(:gem, '', 'Solhaven', 9, 'blue sapphire')
  manager.send(:check_task)
  task.call(:gem, '', 'Solhaven', 3, 'blue sapphire')
  manager.send(:check_task)
  task.call(:taskmaster, '', '', nil)
  manager.send(:check_task)
  manager.send(:handle_reward, 1050, 1000, 5130)
  town_gem = last.call

  # A dangerous creature provoked and killed between two polls: the task goes
  # from dangerous to done without the poll seeing it spawn
  manager.send(:clear_tracking)
  $running = ['bigshot']
  offer_id = A::Database.new_id
  A::Database.record_offer(WHO, nil, { assignment: 'creature_assignment', description: 'a dangerous creature' }, id: offer_id, at: NOW)
  manager.instance_variable_set(:@offer, { id: offer_id, detail: nil, words: 'a dangerous creature' })
  task.call(:dangerous, 'shambling lurk', 'the Sanctum', nil)
  manager.send(:check_task)
  task.call(:guard, '', '', nil)
  manager.send(:check_task)
  manager.send(:handle_reward, 1100, 1100, 9430)
  A::Database.flush
  spawned = [A::Database.one('SELECT bounty_type, status FROM bounties ORDER BY rowid DESC LIMIT 1').values,
             A::Database.one("SELECT bounty_type FROM silver_events WHERE source_category = 'bounty' ORDER BY rowid DESC LIMIT 1")['bounty_type']]
  spawned_offer = A::Database.one('SELECT bounty_type FROM bounty_offers WHERE offer_id = ?', offer_id)['bounty_type']

  # An escort's destination, read from the taskmaster's words, survives a poll
  # that names none: the live poll gives blanks, not nils
  escort_id = A::Database.new_id
  A::Database.record_offer(WHO, nil, { assignment: 'escort', bounty_type: 'escort', area: 'Zul Logoth', description: 'an escort' },
                           id: escort_id, at: NOW)
  A::Database.refine_offer(escort_id, 'escort', '', '', nil)
  escort = A::Database.one('SELECT bounty_type, area, creature FROM bounty_offers WHERE offer_id = ?', escort_id).values
  result = { 'cull' => steps, 'before_hunt' => before_hunt, 'town_gem' => town_gem, 'spawned' => spawned,
             'spawned_offer' => spawned_offer, 'escort' => escort }

when 'kill_time'
  # A kill's day is the day of the search, even if its write runs later
  A::Database.connect!
  A::Database.record_kill(WHO, 'kobold', 'crags', 25, at: NOW - 86_400)
  A::Database.record_kill(WHO, 'kobold', 'crags', 30, at: NOW)
  result = { 'days' => A::Database.all('SELECT date, kill_count, total_silver, last_kill_at FROM kill_stats ORDER BY date').map(&:values),
             'yesterday' => (Date.today - 1).to_s, 'today' => Date.today.to_s, 'now' => NOW }

when 'offers'
  # Every task the taskmaster offers, kept or sent back, from the 2026-11-05 logs
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  manager = A::BountyManager
  manager.instance_variable_set(:@who, WHO)
  manager.instance_variable_set(:@hunt_script, cfg[:hunt_script])
  manager.instance_variable_set(:@events, Queue.new)
  manager.send(:clear_tracking)
  manager.send(:install_hook)
  $running = ['bigshot']
  $task = nil
  feed = lambda do |*lines|
    lines.each { |line| DownstreamHook.run(line) }
    manager.send(:drain_events)
  end
  told = ->(words) { "<clearStream id='bounty'/><pushStream id='bounty'/>The taskmaster told you:  \"#{words}\"" }
  malcrith = '<pushBold/><a exist="23813302" noun="Malcrith">Malcrith</a><popBold/>'
  creature = "Hmm, I've got a task here from the town of Vornavis.  It appears they have a creature problem they'd like you to solve.  " \
             'Go report to one of the Vornavis gate guards to find out more.  Be sure to ASK about BOUNTIES.'
  bandit = "Hmm, I've got a task here from the town of Vornavis.  It appears they have a bandit problem they'd like you to solve.  " \
           'Go report to one of the Vornavis gate guards to find out more.  Be sure to ASK about BOUNTIES.'
  escort = "I've got a special mission for you.  A certain client has hired us to provide a protective escort on his upcoming journey.  " \
           'Go to the south end of North Market and WAIT for him to meet you there.  You must guarantee his safety to Zul Logoth ' \
           'as soon as you can, being ready for any dangers that the two of you may face.  Good luck!'
  removed = ->(name) { "#{malcrith} says, \"Very well <a exist=\"-1\" noun=\"#{name}\">#{name}</a>, I have removed you from your current assignment.\"" }

  # Kept: the guard names the creature, the hunt starts, it's turned in.
  # BOUNTY typed before the guard repeats the taskmaster's words (twice here),
  # and the bounty window can repeat them too: still one offer.
  feed.call(told.call(creature))
  listing = ['<a exist="-1" noun="Splinter">Splinter</a>, your Adventurer\'s Guild information is as follows:',
             'You currently have 1,633,594 unspent bounty points.', 'You have 8133 expedited task reassignment vouchers remaining.',
             "The taskmaster told you:  \"#{creature}\"", '<prompt time="1">&gt;</prompt>']
  feed.call(*listing, *listing, told.call(creature))
  A::Database.flush
  repeats = A::Database.one('SELECT COUNT(*) AS n FROM bounty_offers')['n']
  $task = TaskStub.new(:cull, 'lithe veiled sentinel', 'shadow of the Sanctum', 20)
  manager.send(:check_task)
  feed.call('[You have earned 889 bounty points, 1000 experience points, and 8890 silver.]')
  # Sent back before the guard was asked; another player's removal is not ours
  $task = nil
  feed.call(told.call(bandit), removed.call('April'), removed.call('Splinter'))
  # BOUNTY's own voucher listing is not an expedite; the bracketed line is
  feed.call('You have 8133 expedited task reassignment vouchers remaining.')
  feed.call(told.call(creature))
  feed.call(removed.call('Splinter'), "#{malcrith} says, \"Very well, Splinter.  I'll expedite your task reassignment.\"",
            '[You have 8132 expedited task reassignment vouchers remaining.]', told.call(escort), removed.call('Splinter'))
  # Wording the parser doesn't know, replaced by a gem task with no turn-in between
  feed.call(told.call('Something new the taskmaster says.'))
  feed.call(told.call("Hmm, I've got a task here from the town of Solhaven.  The local gem dealer, Kahlyr, has an order to fill " \
                      'and wants our help.  Head over there and see what you can do.  Be sure to ASK about BOUNTIES.'))
  gem = manager.instance_variable_get(:@offer)[:id]
  A::Database.flush # a restart follows the last run's final writes
  # Restarted while still holding it: kept. Restarted with no task: expired.
  $task = TaskStub.new(:gem, '', 'Solhaven', 9, 'blue sapphire')
  manager.send(:reconcile_offers)
  kept = manager.instance_variable_get(:@offer)&.[](:id) == gem
  $task = TaskStub.new(:none, '', '', nil)
  manager.send(:reconcile_offers)
  A::Database.flush

  rows = A::Database.all('SELECT * FROM bounty_offers ORDER BY offered_at, rowid')
  bounty = A::Database.one('SELECT bounty_id, status FROM bounties')
  text = A::Database.reader { |conn| A::Report::Text.bounty_summary(conn, WHO, 'daily') }.join("\n")
  result = {
    'rows' => rows.map do |row|
      [row['assignment'], row['town'], row['area'], row['bounty_type'], row['creature'], row['count'],
       A::Util.truthy(row['expedited']), row['vouchers_left'], row['outcome']]
    end,
    'labels' => rows.map { |row| A::Util.offer_label(row) },
    'linked' => rows.first['bounty_id'] == bounty['bounty_id'] && bounty['status'] == 'completed',
    'described' => rows.first['description'].start_with?("Hmm, I've got") && !rows.first['description'].end_with?('"'),
    'ended' => rows.all? { |row| row['ended_at'] }, 'kept_on_restart' => kept, 'after_bounty_listings' => repeats,
    'report' => [text.include?('Task offers'), text[/Offered\s*\|\s*(\d+)/, 1], text[/Removed\s*\|\s*(\d+)/, 1],
                 text[/Expedited\s*\|\s*(\d+)/, 1], text.include?('escort to Zul Logoth')]
  }
  DownstreamHook.remove('GS4Analytics::BountyManager')

when 'failed_offer'
  # A failed task closes nothing, so the next task from the same town arrives
  # with the same words while the old offer is still open
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  manager = A::BountyManager
  manager.instance_variable_set(:@who, WHO)
  manager.instance_variable_set(:@hunt_script, cfg[:hunt_script])
  manager.instance_variable_set(:@events, Queue.new)
  manager.send(:clear_tracking)
  manager.send(:install_hook)
  $running = ['bigshot']
  feed = lambda do |*lines|
    lines.each { |line| DownstreamHook.run(line) }
    manager.send(:drain_events)
  end
  words = "Hmm, I've got a task here from the town of Vornavis.  It appears they have a creature problem they'd like you to solve.  " \
          'Go report to one of the Vornavis gate guards to find out more.  Be sure to ASK about BOUNTIES.'
  told = "<clearStream id='bounty'/><pushStream id='bounty'/>The taskmaster told you:  \"#{words}\""
  feed.call(told)
  $task = TaskStub.new(:cull, 'lithe veiled sentinel', 'shadow of the Sanctum', 20)
  manager.send(:check_task)
  $task = TaskStub.new(:failed, '', '', nil)
  manager.send(:check_task)
  feed.call(told)
  $task = TaskStub.new(:cull, 'grotesque nightmare', 'shadow of the Sanctum', 15)
  manager.send(:check_task)
  feed.call('[You have earned 889 bounty points, 1000 experience points, and 8890 silver.]')
  A::Database.flush
  rows = A::Database.all('SELECT creature, count, outcome FROM bounty_offers ORDER BY offered_at, rowid')
  result = { 'rows' => rows.map(&:values) }
  DownstreamHook.remove('GS4Analytics::BountyManager')

when 'spending'
  # Boxes found on corpses, and silver spent at the locksmith, the locksmith
  # pool and the priestess, from the 2026-11-05 logs
  A::Database.connect!
  A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  feed = ->(*lines) { lines.each { |line| DownstreamHook.run(line) } }
  feed.call('You search the scaled shaper.', 'You discard the shaper\'s useless equipment.',
            'He carried a corroded brass strongbox on him!', "He didn't carry any silver.", 'He had nothing else of value.',
            '<prompt time="1">&gt;</prompt>',
            'You search the flesh monstrosity.', 'It had 57 silvers on it.', 'It had nothing else of value.',
            '<prompt time="2">&gt;</prompt>',
            'You ring the bell, and ask Jyhm if he can open your silver strongbox.',
            'He looks over the silver strongbox, frowns, and tells you, "Havin\' some trouble, eh?  Of course I could open this, ' \
            'but it\'ll cost ya.  Gimme 4,033 silvers, and I\'ll have it open before you know it."',
            # Another player's quote, 134 ms before this character pays (seen in the logs): not ours
            'He looks over the walnut box, frowns, and tells Penny, "Havin\' some trouble, eh?  Of course I could open this, ' \
            'but it\'ll cost ya.  Gimme 5,729 silvers, and I\'ll have it open before you know it."',
            'The locksmith Jyhm accepts your silvers.',
            'The locksmith Jyhm accepts your silvers.', # no quote before it: not counted twice
            'Jahck takes your chest and says, "Your tip of 500 silvers has been recorded, and the 250 silver fee has been collected.  ' \
            'We\'ll get someone on that right away."',
            'You hand the priestess 1,200 silvers.  "Thank you," she says.  She removes a glass decanter, and fills a simple ' \
            'indigo flask with a clear fluid, and then hands it to you.',
            'You hear the voice of the clerk from behind one of the thin walls telling you he has recorded a storage fee of ' \
            '1210 silvers for you and thanks you for paying it promptly.',
            # Herbs bought with a note (eherbs), then another player's words alone: not ours
            'Kelph exclaims, "Sold for 360 silvers!"', 'Kelph takes your promissory note and hands you a new one.',
            'She hands you some pothinir grass and says, "Here\'s your purchase.  Thanks for your patronage."',
            'Syiah Kintaru exclaims, "Sold for 90 silvers!"',
            'He hands you some ambrominas leaf and says, "Here\'s your purchase.  Thanks for your patronage."',
            'Penny exclaims, "Sold for 5,000 silvers!"', 'Penny grins.')
  sleep 0.3
  A::Database.flush
  result = {
    'kills' => A::Database.all('SELECT creature, kill_count, total_silver, boxes FROM kill_stats ORDER BY creature').map(&:values),
    'spent' => A::Database.all("SELECT vendor_type, vendor_name, amount FROM silver_events WHERE source_category = 'expense' " \
                               'ORDER BY rowid').map(&:values)
  }
  A::SilverManager.stop

when 'overheard'
  # Other players' words, as the stream marks them (the 2026-11-12 logs):
  # room speech in its own stream and then with its preset, a whisper, and a
  # thought over ESP. None of it is this character's; the NPCs' lines are.
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  A::BountyManager.start(WHO, cfg)
  feed = ->(*lines) { lines.each { |line| DownstreamHook.run(line) } }
  said = "<preset id='speech'>Penny says</preset>, \"%s\""
  spoken = lambda do |text|
    ["<pushStream id=\"speech\"/>#{format(said, text)}", '<popStream/>', format(said, text)]
  end
  feed.call('You currently have the following amounts on deposit:', '      Bank A: 100', '      Total: 100')
  sleep 0.3
  feed.call(*spoken.call('You gather the remaining 9,999,999 coins from inside your box.'),
            *spoken.call('You search the kobold.'), '<prompt time="1">&gt;</prompt>',
            *spoken.call('You deposit 1 silver into your account.  The teller says, "This brings your total to 1,000,000,000 silvers.'),
            *spoken.call('You have earned 1 bounty point, 1 experience point, and 88,888,888 silver.'),
            "<preset id=\"whisper\">Penny whispers</preset>, \"The Bob takes your gem, looks at it and hands you 4,444,444 silvers for it.\"",
            '<pushStream id="thoughts"/><preset id="thought">[General]-GSIV:Penny: </preset>"Jahck takes your box and says, ' \
            '\"Your tip of 1 silver has been recorded, and the 3,333,333 silvers fee has been collected"',
            '<popStream/>',
            # a stream that never pops (a lost line): the next prompt ends it
            '<pushStream id="thoughts"/><preset id="thought">[General]-GSIV:Penny: </preset>"You gather the remaining 5 coins from inside your box."',
            '<prompt time="2">&gt;</prompt>',
            # thoughts as plain text
            '[General]-GSIV:Penny: "You gather the remaining 7 coins from inside your box."',
            # the Order of Voln's channel, in the shape Lich parses: one
            # member's words reach every member in the realm
            '<pushStream id="voln"/>[Voln - <a exist="-9" noun="Penny">Penny</a>] "You deposit 1 silver into your account.  ' \
            'The teller says, \"This brings your total to 1,999,999,999 silvers."',
            '<popStream/>',
            '<pushStream id="voln"/>[Voln - <a exist="-9" noun="Penny">Penny</a>] "You gather the remaining 11 coins from inside your box."',
            '<popStream/>',
            # thoughts as one element, the form Lich's markup also reads, closed
            # by its own end tag
            '<stream id="thoughts">Penny: "You gather the remaining 9 coins from inside your box."</stream>',
            # a line with a byte that isn't UTF-8: read without it, and the hooks go on
            "You gather the remaining 33 coins from inside your box.\xFF".dup.force_encoding('UTF-8'),
            # this character's own: the NPCs' lines, in the main window
            'You gather the remaining 75 coins from inside your box.',
            'Jahck takes your chest and says, "Your tip of 500 silvers has been recorded, and the 250 silver fee has been collected."')
  sleep 0.3
  feed.call('<pushStream id="thoughts"/><preset id="thought">[General]-GSIV:Penny: </preset>"The taskmaster told you:  ' \
            '\"It appears they have a bandit problem.\""', '<popStream/>')
  sleep 1.2
  A::Database.flush
  result = {
    'silver' => A::Database.all('SELECT source_category, vendor_type, amount FROM silver_events ORDER BY rowid').map(&:values),
    'kills' => A::Database.all('SELECT creature FROM kill_stats').map(&:values),
    'bank' => A::Database.all("SELECT snapshot_type, balance FROM bank_snapshots WHERE bank_name = '__total__' ORDER BY rowid").map(&:values),
    'bounties' => A::Database.all('SELECT status FROM bounties').map(&:values),
    'offers' => A::Database.all('SELECT assignment FROM bounty_offers').map(&:values)
  }
  A::BountyManager.stop
  A::SilverManager.stop

when 'money_reports'
  # The silver, kills and cycle reports, the death alert and backups
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  # Everything in the last ~70 minutes and read through the weekly window,
  # so the numbers hold at any time of day, midnight included
  day = NOW - 4200
  A::Database.record_kill(WHO, 'kobold', 'crags', 40, at: day + 10, boxes: 1)
  A::Database.record_kill(WHO, 'kobold', 'crags', 60, at: day + 20)
  A::Database.record_kill(WHO, 'troll', 'crags', 500, at: day + 30, boxes: 1)
  { 'box' => [300, nil], 'sale' => [1000, 'pawnbroker'], 'bounty' => [9000, nil] }.each do |cat, (amount, kind)|
    A::Database.record_silver(WHO, nil, cat, amount, vendor_type: kind, at: day + 40)
  end
  A::Database.record_silver(WHO, nil, 'expense', 4033, vendor_type: 'locksmith', vendor_name: 'Jyhm', at: day + 50)
  A::Database.record_silver(WHO, nil, 'expense', 1200, vendor_type: 'priestess', at: day + 60)
  [[day + 100, 600], [day + 3700, 300]].each do |start, secs|
    dead = A::Database.start_cycle(WHO, :dead, 'dead', 'crags', {})
    run_sql('UPDATE cycles SET start_time = ?, end_time = ?, duration_seconds = ? WHERE cycle_id = ?', start, start + secs, secs, dead)
  end
  hunt = A::Database.start_cycle(WHO, :hunt, 'bigshot', 'crags', {})
  run_sql('UPDATE cycles SET start_time = ?, end_time = ?, duration_seconds = 3000 WHERE cycle_id = ?', day + 700, day + 3700, hunt)
  texts = A::Database.reader do |conn|
    %w[silver kill cycle].to_h do |name|
      [name, A::Report::Text.public_send({ 'silver' => :silver_summary, 'kill' => :kill_summary, 'cycle' => :cycle_summary }[name],
                                         conn, WHO, 'weekly').join("\n")]
    end
  end
  cell = ->(text, label) { text[/\| #{Regexp.escape(label)}\s*\|\s*([^|]+?)\s*\|/, 1] }
  # Death alert, on and off
  manager = A::CycleManager
  manager.instance_variable_set(:@who, WHO)
  manager.instance_variable_set(:@cfg, cfg)
  OUT.clear
  manager.send(:alert_death)
  alerted = OUT.any? { |line| line.include?('DEATH: Splinter died') }
  cfg[:alerts][:death] = false
  OUT.clear
  manager.send(:alert_death)
  quiet = OUT.none? { |line| line.include?('DEATH') }
  # Backups: a readable copy, and only the newest few kept
  dir = File.join(DATA_DIR, 'analytics-backups')
  FileUtils.mkdir_p(dir)
  9.times { |i| File.write(File.join(dir, "analytics-20200101-00000#{i}.db"), '') }
  message = A::Database.backup
  copies = Dir[File.join(dir, 'analytics-*.db')].sort
  copy = Sequel.sqlite(copies.last)
  copied_kills = copy[:kill_stats].sum(:kill_count)
  copy.disconnect
  result = {
    'silver' => %w[Corpses Boxes Sales Bounties Total locksmith priestess].map { |label| cell.call(texts['silver'], label) } +
                [cell.call(texts['silver'], 'Found less spent')],
    'kills'  => [cell.call(texts['kill'], 'kobold'), texts['kill'].lines.grep(/\| Total/).first.to_s.split('|').map(&:strip).reject(&:empty?)],
    'deaths' => %w[Deaths Hunting\ time\ per\ death Time\ between\ deaths].map { |label| cell.call(texts['cycle'], label) },
    'alert'  => [alerted, quiet],
    'backup' => [message.start_with?('Backed up to'), copies.size, copied_kills, File.basename(copies.first).start_with?('analytics-2020')]
  }

when 'session_report'
  # "This login" (Lich's $login_time, days long) next to today, week, month,
  # YTD and lifetime: silver, exp, rates and deaths
  A::Database.connect!
  login = NOW - (2 * 86_400) - 3600 # logged in two days and an hour ago
  A::Database.record_login(WHO, login, login + 5)
  A::Database.record_login(WHO, login, NOW - 30) # a restart in the same login keeps it
  cycle = lambda do |type, start, secs, exp_a, exp_b|
    id = A::Database.start_cycle(WHO, type, type.to_s, 'crags', { exp_total: exp_a })
    run_sql('UPDATE cycles SET start_time = ?, end_time = ?, duration_seconds = ?, exp_total_end = ? WHERE cycle_id = ?',
            start, secs && start + secs, secs, exp_b, id)
  end
  bank = lambda do |at, delta|
    run_sql("INSERT INTO bank_snapshots (snapshot_id, game, character, timestamp, bank_name, balance, delta_silver, snapshot_type) " \
            "VALUES (?, 'GS3', 'Splinter', ?, '__total__', 0, ?, 'deposit')", A::Database.new_id, at, delta)
  end
  # Before this login: a year-old death and silver that only lifetime counts
  cycle.call(:dead, NOW - (400 * 86_400), 600, 900, 900)
  bank.call(NOW - (400 * 86_400), 50_000)
  # In this login: two hours hunting (one of them two days ago), a death, and
  # an hour of hunt still running now
  cycle.call(:hunt, login + 600, 3600, 1000, 3000)
  bank.call(login + 4000, 100_000)
  cycle.call(:dead, login + 4300, 300, 3000, 3000)
  cycle.call(:hunt, NOW - 3600, nil, 3000, nil)
  bank.call(NOW - 60, 20_000)
  # At the moment the rows were laid out, so a slow run doesn't stretch the hunt still going
  text = A::Database.reader { |conn| A::Report::Text.session_summary(conn, WHO, now: NOW) }.join("\n")
  cells = ->(label) { text.lines.find { |l| l.start_with?("| #{label} ") }.to_s.split('|').map(&:strip).drop(2) }
  login_info = A::Database.one('SELECT first_seen, last_seen FROM logins')
  result = {
    'header' => text.lines.map(&:strip).find { |l| l.start_with?('This login: since') }.to_s.sub(/\(.*\)/, '(...)'),
    'columns' => text.lines.find { |l| l.include?('This login') && l.start_with?('|') }.to_s.split('|').map(&:strip).drop(2),
    'silver' => cells.call('Silver'), 'deaths' => cells.call('Deaths'), 'exp' => cells.call('Exp'),
    'silver_hr' => cells.call('Silver / hour').first, 'hunting' => cells.call('Hunting').first,
    'kept_first_seen' => [login_info['first_seen'] == login + 5, login_info['last_seen'] == NOW - 30],
    'expected_since' => Time.at(login).strftime('%Y-%m-%d %H:%M'),
    'login' => A::Database.reader { |conn| A::Report.login_for(conn, WHO) }&.values_at('started_at', 'live')
  }
  result['login_ok'] = result.delete('login') == [login, true]

when 'schema_guard'
  # A file from another build is refused, not migrated: testers start fresh
  file = A::Database.file
  old = lambda do |version|
    FileUtils.rm_f(Dir["#{file}*"])
    db = Sequel.sqlite(file)
    db.create_table(:cycles) { String :cycle_id, primary_key: true }
    if version
      db.create_table(:metadata) { String :key, primary_key: true; String :value; Integer :updated_at }
      db[:metadata].insert(key: 'schema_version', value: version, updated_at: NOW)
    end
    db.disconnect
  end
  refused = lambda do |&action|
    [false, action.call]
  rescue A::Database::Outdated => e
    [true, e.message]
  end
  tables = -> { Sequel.sqlite(file).then { |db| db.tables.sort.tap { db.disconnect } } }
  result = {}
  old.call('6')
  result['writer'] = refused.call { A::Database.connect! }
  result['untouched'] = tables.call
  result['reader'] = refused.call { A::Database.reader }.first
  old.call(nil)
  result['no_version'] = refused.call { A::Database.connect! }
  old.call('6')
  OUT.clear
  A::CLI.send(:execute, %w[report cycle])
  result['cli'] = OUT.any? { |line| line.include?('was made by another build') }
  port = 39_000 + (Process.pid % 1000)
  A::Dashboard.start(port)
  sleep 0.2
  socket = TCPSocket.new('127.0.0.1', port)
  socket.write("GET /api/meta HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
  reply = socket.read
  socket.close
  A::Dashboard.stop
  result['api'] = [reply.split[1], reply.include?('was made by another build')]
  FileUtils.rm_f(Dir["#{file}*"])
  File.write(file, '')
  A::Database.connect!
  result['empty_file'] = A::Database.one("SELECT value FROM metadata WHERE key = 'schema_version'")['value']
  A::Database.close

when 'zone'
  # The zone this Lich runs in, recorded with the moment it was read
  zone = lambda do |tz|
    ENV['TZ'] = tz
    A::Database.connect!
    rows = A::Database.all("SELECT key, value, updated_at FROM metadata WHERE key IN ('utc_offset', 'zone') ORDER BY key")
    A::Database.close
    rows.to_h { |r| [r['key'], [r['value'], r['updated_at'].is_a?(Integer)]] }
  end
  result = { 'tokyo' => zone.call('Asia/Tokyo'), 'utc' => zone.call('UTC') }
  ENV.delete('TZ')

when 'writer_safety'
  # Cheaper syncing on every writer connection, the received-time index, and
  # a write that never runs on the caller's thread once the writer exists
  A::Database.connect!
  sync = ->(conn) { conn.fetch('PRAGMA synchronous').single_value }
  result = {
    # the pragma reads 1 either way with Lich's gem (NORMAL is its WAL default): the
    # setting itself is what makes another build the same
    'synchronous'    => [sync.call(A::Database.db), Thread.new { sync.call(A::Database.db) }.value, A::Database.db.opts[:synchronous]],
    'received_index' => A::Database.db.indexes(:bounties).values.any? { |i| i[:columns] == %i[game character received_time] }
  }
  # The writer survives an error of its own and keeps writing, in order
  original = A::Database.method(:drain_writes)
  A::Database.singleton_class.send(:define_method, :drain_writes) do
    A::Database.singleton_class.send(:define_method, :drain_writes, original)
    raise 'boom'
  end
  A::Database.async { A::Database.set_metadata('first', '1') }
  A::Database.async { A::Database.set_metadata('second', '2') }
  sleep 1.5 # the writer pauses a second after an error
  A::Database.flush
  result['survives'] = [A::Database.instance_variable_get(:@writer).alive?,
                        A::Database.metadata('first'), A::Database.metadata('second')]
  # Writer gone (as on ;kill): a write from another thread is queued, not run
  # there, and #close writes it
  writer = A::Database.instance_variable_get(:@writer)
  writer.kill
  writer.join
  ran_on = nil
  hook = Thread.new do
    A::Database.async do
      ran_on = Thread.current
      A::Database.set_metadata('late', 'yes')
    end
    Thread.current
  end.value
  queued = [ran_on.nil?, A::Database.send(:backlog?)]
  A::Database.close
  file = Sequel.sqlite(A::Database.file)
  late = file[:metadata].where(key: 'late').get(:value)
  file.disconnect
  result['writer_gone'] = queued + [ran_on && ran_on != hook, late]

when 'progress'
  A::Database.connect!
  P = A::ProgressManager
  # EXPERIENCE output as the game sends it, tags and all
  experience = lambda do |fame:, sting:, lte:, deeds:|
    ['<output class="mono"/>', '', "          Level: 100                         Fame: #{fame}",
     '     Experience: 900,500             Field Exp: 400/800', '  Ascension Exp: 100,000          Recent Deaths: 1',
     "      Total Exp: 1,000,500         Death's Sting: #{sting}", "  Long-Term Exp: #{lte}                  Deeds: #{deeds}",
     '     Exp to next TP: 1,500'].each { |line| DownstreamHook.run(line) }
  end
  $read_at = Time.now - 86_400 # infomon's reading from a day ago: not one this session saw
  P.start(WHO)
  sleep 0.3 # the first read, from the thread
  hook = DownstreamHook.names.include?('GS4Analytics::ProgressManager')
  t = Time.now.to_i
  $exp = 900_500
  soon = P.check(now: t + 30)          # experience alone: waits for the heartbeat
  later = P.check(now: t + 400)
  $sting = 'Light'
  sting_unread = P.check(now: t + 405) # Lich's value changed, but no EXPERIENCE seen: not written
  sleep 1.1                            # a reading is stamped with the clock: a second from the first row
  # EXPERIENCE typed right after a death: the total is the same, only the sting moved,
  # so infomon's time for the total doesn't move. The reading is read from the text.
  experience.call(fame: '7,777', sting: 'Sharp', lte: 61, deeds: 13)
  read = P.check(now: t + 410) # a new reading: at once
  # Another player's words, then the real training-point line
  DownstreamHook.run('Bob says, "PTPs/MTPs: 999/888 ATPs: 777"')
  DownstreamHook.run(%(Bob says, "      Total Exp: 1 Death's Sting: Harsh"))
  ignored = P.check(now: t + 415)
  DownstreamHook.run('<output class="mono"/>       PTPs/MTPs: 36/0                        ATPs: 6')
  tps = P.check(now: t + 420)
  sleep 4.1 # more than PAIR_SECONDS (in whole seconds) after the EXPERIENCE: a RESOURCE of its own
  # RESOURCE output, as the game sends it, ended by the prompt
  ['<output class="mono"/>', 'Health: 280/<pushBold/>300<popBold/>     Mana: 40/80     Stamina: 120/120     Spirit: 10/10',
   'Devotion: 12,345/50,000 (Weekly)           67,890/200,000 (Total)', 'Suffused Devotion: 4,321', 'Voln Favor: 98,765',
   'Bob says, "Voln Favor: 1"', '<prompt time="1">&gt;</prompt>'].each { |line| DownstreamHook.run(line) }
  resource = P.check(now: t + 450)
  same = P.check(now: t + 500)         # nothing changed
  beat = P.check(now: t + 4100)        # the hourly heartbeat
  sleep 4.1 # apart from the RESOURCE before it
  experience.call(fame: '7,800', sting: 'Light', lte: 61, deeds: 13) # a potion eases it
  sleep 1.1
  DownstreamHook.run('You feel the sting of a recent death slowly fade away, yet a lingering weakness remains.')
  P.check(now: t + 4150)
  eased = A::Database.flush && A::Database.one("SELECT COUNT(*) AS n FROM progress WHERE deaths_sting = 'None'")['n']
  sleep 1.1
  DownstreamHook.run('You feel the sting of a recent death slowly fade away.')
  P.check(now: t + 4200)
  # Fame on a cycle only from a reading fresh at that moment (the last one the hook saw)
  stale = A::Vitals.read(since: Time.now.to_i + 60)
  fresh = A::Vitals.read(since: Time.now.to_i - 60)
  id = A::Database.start_cycle(WHO, :hunt, 'bigshot', 'crags', fresh, at: NOW - 600)
  A::Database.end_cycle(id, fresh, nil, at: NOW - 60)
  # EXPERIENCE and RESOURCE typed together, their output ending either side of a second: one row
  sleep 4.1
  experience.call(fame: '8,100', sting: 'Light', lte: 62, deeds: 14)
  sleep 1.1
  ['<output class="mono"/>', 'Health: 300/300     Mana: 80/80     Stamina: 120/120     Spirit: 10/10',
   'Devotion: 13,000/50,000 (Weekly)           68,000/200,000 (Total)', '<prompt time="2">&gt;</prompt>'].each { |line| DownstreamHook.run(line) }
  P.check(now: t + 4300)
  P.stop(now: t + 5000) # and a last row
  # EXPERIENCE and RESOURCE typed together: two readings in one second, one row with both
  A::Database.flush
  base = { level: 100, exp: 900_500 }
  A::Database.record_progress(WHO, t + 9000, base.merge(fame: 8000, deeds: 14, deaths_sting: 'None'))
  A::Database.record_progress(WHO, t + 9000, base.merge(resource_name: 'Devotion', resource_weekly: 13_000, voln_favor: 99_000))
  together = A::Database.all('SELECT fame, deeds, deaths_sting, resource_name, resource_weekly, voln_favor FROM progress WHERE timestamp = ?', t + 9000)
  A::Database.send(:db)[:progress].where(timestamp: t + 9000).delete
  A::Database.flush
  rows = A::Database.all('SELECT * FROM progress ORDER BY timestamp')
  cycle = A::Database.one('SELECT exp_regular_start, exp_regular_end, exp_asc_start, exp_asc_end, exp_total_start FROM cycles')
  at = ->(dt) { rows.find { |r| r['timestamp'] == t + dt } }
  sting = ->(level) { rows.find { |r| r['deaths_sting'] == level } }
  result = {
    'hook' => hook, 'hook_removed' => !DownstreamHook.names.include?('GS4Analytics::ProgressManager'),
    'checks' => [soon, later, sting_unread, read, ignored, tps, same, beat], 'rows' => rows.size, 'resource_check' => resource,
    'resource' => rows.find { |r| r['resource_name'] }&.slice('resource_name', 'resource_weekly', 'resource_total', 'suffused', 'voln_favor',
                                                              'covert_arts_charges', 'fame', 'deaths_sting'),
    'first' => rows.first&.slice('level', 'exp', 'ascension_exp', 'until_next', 'fame', 'deeds', 'long_term_exp', 'deaths_sting', 'ptp', 'lumnis'),
    'reading' => sting.call('Sharp')&.slice('deaths_sting', 'fame', 'deeds', 'long_term_exp'),
    'reading_at_its_time' => sting.call('Sharp') && sting.call('Sharp')['timestamp'] < t + 30,
    'eased' => sting.call('Light')&.slice('deaths_sting', 'fame'),
    'heartbeat' => at.call(4100)&.slice('exp', 'deaths_sting', 'fame'),
    'tps' => rows.select { |r| r['ptp'] }.map { |r| r.slice('ptp', 'mtp', 'atp') },
    'gone' => [eased, rows.count { |r| r['deaths_sting'] == 'None' }], 'cycle_fame' => [stale[:fame], fresh[:fame]],
    'gone_row' => sting.call('None')&.slice('fame', 'deeds', 'long_term_exp'),
    'cycle' => cycle, 'schema' => A::Database.metadata('schema_version'), 'together' => together,
    'paired' => rows.select { |r| r['fame'] == 8100 }.map { |r| r.slice('fame', 'resource_weekly') }
  }

when 'shops'
  A::Database.connect!
  cfg = A::Settings.load(WHO)
  # find_nearest_by_tag('town'): the town room each shop is nearest (Lich walks the map)
  shop_room = Struct.new(:id, :tags, :location, :title, :town_room) do
    def find_nearest_by_tag(tag) = tag == 'town' ? town_room : nil
  end
  ROOMS = {
    10 => shop_room.new(10, ['town square'], "Wehnimer's Landing", '[Town Square]', 1),
    20 => shop_room.new(20, ['gemshop', 'urchin guide gemshop'], "Wehnimer's Landing", '[Gems]', 1),
    30 => shop_room.new(30, ['locksmith', 'locksmith pool'], 'the lowlands of Marshtown', '[Pool]', 2),
    40 => shop_room.new(40, ['consignment'], 'Solhaven', '[Consignment]', 2),
    50 => shop_room.new(50, ['locksmith pool'], 'Solhaven', '[Garret]', 2), # the priestess, in a room tagged for the pool
    1  => shop_room.new(1, ['town'], "the town of Wehnimer's Landing", '[Town Square Central]', 1),
    2  => shop_room.new(2, ['town'], 'the free port of Solhaven', '[Solhaven, North Market]', 2)
  }.freeze
  Object.const_set(:Room, Class.new do
    def self.current = ROOMS[$room_id]
    def self.[](id) = ROOMS[id]
  end) unless defined?(Room)
  W = A::ShopWatcher
  A::SilverManager.start(WHO)
  W.start(WHO)
  t = NOW - 1000
  $room_id = 10
  W.tick(t)
  $room_id = 20
  W.tick(t + 10)                       # into the gem shop
  DownstreamHook.run('The jeweler takes your black opal, glances at it, and hands you 5,000 silvers.')
  W.note(silver: 1200)
  open_visit = W.current&.slice(:vendor, :silver, :town)
  $room_id = 10
  W.tick(t + 70)                       # out: a 60 second visit
  $room_id = 20
  W.tick(t + 80)
  $room_id = 10
  W.tick(t + 82)                       # straight through: not a visit
  $room_id = 30
  W.tick(t + 100)                      # the locksmith pool, tagged locksmith too
  W.note(spent: 300)
  A::SilverManager.record_vendor_visit('api', t + 110, t + 120, 777) # ignored: tracked already
  $room_id = 40
  W.tick(t + 130) # the consignment shop, whose clerk calls itself a pawnbroker
  DownstreamHook.run('The pawnbroker takes your silver ring, glances at it, and hands you 400 silvers.')
  W.tick(t + 131)
  $room_id = 50
  W.tick(t + 132) # only the priestess paid here: named for her, not the tag
  DownstreamHook.run('You hand the priestess 1,200 silvers.  "Thank you," she says.  She removes a glass decanter, and fills a simple ' \
                     'indigo flask with a clear fluid, and then hands it to you.')
  $room_id = 10
  W.tick(t + 140)
  W.stop(now: t + 141)
  A::Settings.instance_variable_set(:@current, cfg.merge(track_shops: false))
  A::SilverManager.record_vendor_visit('api', t + 200, t + 250, 777)
  $room_id = 20
  W.start(WHO)
  W.tick(t + 300) # with track_shops off, nothing is opened
  off = W.current
  # A sale read before the poll has seen the character step into the shop
  A::Settings.instance_variable_set(:@current, cfg)
  W.start(WHO)
  $room_id = 10
  W.tick
  $room_id = 20
  DownstreamHook.run('The jeweler takes your sapphire, glances at it, and hands you 2,269 silvers.')
  raced = W.current&.slice(:vendor, :silver)&.transform_keys(&:to_s)
  W.stop
  A::SilverManager.stop
  A::Database.flush
  visits = A::Database.all('SELECT vendor, duration_seconds, silver, spent, room_id, town FROM vendor_visits ORDER BY start_time')
  sales = A::Database.all("SELECT vendor_type, vendor_name, amount FROM silver_events WHERE source_category = 'sale' ORDER BY timestamp, amount")
  result = { 'open' => open_visit && open_visit.transform_keys(&:to_s), 'visits' => visits.map(&:values), 'off' => off,
             'sales' => sales.map(&:values), 'raced' => raced }

when 'pool'
  # The locksmith pool's list of our boxes, as eloot asks for it, and a box turned away
  A::Database.connect!
  A::Settings.load(WHO)
  A::SilverManager.start(WHO)
  feed = ->(*lines) { lines.each { |line| DownstreamHook.run("#{line}\r\n") } }
  feed.call('The worker says, "We don\'t have any boxes ready for you."',
            'The worker says, "Splinter, here\'s the list of boxes we have for you."',
            '',
            '<output class="mono"/>',
            ' 1.  A scratched white oak box about a minute ago for 750 silvers.',
            '     It is waiting to be worked on.',
            '',
            ' 2.  A battered tanik strongbox about 20 minutes ago for 750 silvers.',
            '[tsquelch3: End Squelching!]',
            '     It is waiting to be worked on.',
            '10.  An iron-bound maple chest a few days ago for 750 silvers.',
            '     It has been opened.',
            '<prompt time="1794300000">&gt;</prompt>',
            # Another player's list, and another player's box turned away: not ours
            'The worker says, "April, here\'s the list of boxes we have for you."',
            ' 1.  A plain maple trunk about an hour ago for 750 silvers.',
            '     It is waiting to be worked on.',
            'The worker says, "Sorry, we\'re already holding as many boxes for you as we can."')
  sleep 1.1 # a second apart, as the game is
  feed.call('You want a locksmith to open a riveted white oak trunk for a tip of 750 silvers.  There is also a fee of 1,803 silvers ' \
            'due up front, totaling 2,553 silvers.  You will need that amount on you or in a local bank.',
            'Please GIVE WORKER 750 CONFIRM to the worker to proceed.',
            'The worker says, "Sorry, we\'re already holding as many boxes for you as we can."')
  sleep 0.3
  A::Database.flush
  result = { 'pool' => A::Database.all('SELECT npc, boxes, waiting, full FROM pool_depth ORDER BY timestamp, full').map(&:values) }

when 'combat'
  # A recorder file as Lich's Combat::Recorder lays it out (the columns the
  # summary reads), with one hunt today and one that ended three weeks ago
  A::Database.connect!
  path = File.join(Dir.mktmpdir('analytics-combat'), 'analytics-combat.db')
  rec = SQLite3::Database.new(path)
  rec.execute_batch(<<~SQL)
    CREATE TABLE sessions (id INTEGER PRIMARY KEY, character TEXT, source TEXT, started_at REAL NOT NULL, ended_at REAL);
    CREATE TABLE creatures (id INTEGER PRIMARY KEY, session_id INTEGER, exist_id INTEGER, noun TEXT, name TEXT, first_seen REAL,
                            last_seen REAL, killed_at REAL, killed_by_attack_id INTEGER, kill_credit TEXT);
    CREATE TABLE attacks (id INTEGER PRIMARY KEY, session_id INTEGER, creature_id INTEGER, ours INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE flares (id INTEGER PRIMARY KEY, attack_id INTEGER, ours INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE resolutions (id INTEGER PRIMARY KEY, attack_id INTEGER);
    CREATE TABLE hits (id INTEGER PRIMARY KEY, attack_id INTEGER, flare_id INTEGER, session_id INTEGER, creature_id INTEGER, damage INTEGER);
    CREATE TABLE statuses (id INTEGER PRIMARY KEY, session_id INTEGER, creature_id INTEGER);
  SQL
  t = NOW - 600
  hunt = A::Database.start_cycle(WHO, :hunt, 'bigshot', 'sewer_tunnels', {})
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', t - 60, hunt)
  rec.execute('INSERT INTO sessions VALUES (1, ?, ?, ?, NULL), (2, ?, ?, ?, ?)',
              [WHO.name, 'live', t, WHO.name, 'live', NOW - (21 * 86_400), NOW - (21 * 86_400) + 600])
  # [id, exist id, name, killed by attack, credit]
  [[1, 101, 'battle-scarred foot ninja', 1, 'crit'], # our swing killed it
   [2, 102, 'foot ninja', 4, 'window'],              # we hit it, another player finished it
   [3, 103, 'mutated rat', 5, 'window'],             # someone else's fight
   [4, 104, 'foot soldier', nil, nil],               # only our shield's spikes, and it got away
   [5, 105, 'foot soldier', 6, 'last_own_hit']].each do |id, exist, name, by, credit|
    rec.execute('INSERT INTO creatures VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?, ?)',
                [id, exist, name.split.last, name, t + id, t + id + 30, (t + id + 30 if by), by, credit])
  end
  rec.execute('INSERT INTO creatures VALUES (6, 2, 201, ?, ?, ?, ?, ?, 7, ?)', ['ninja', 'foot ninja', NOW - (21 * 86_400) + 10, NOW - (21 * 86_400) + 20, NOW - (21 * 86_400) + 20, 'crit'])
  # attacks: [id, creature, ours]; 6 is a creature's swing at us that our reactive flare (flare 1) answered
  [[1, 1, 1], [2, 1, 1], [3, 2, 1], [4, 2, 0], [5, 3, 0], [6, nil, 0], [7, 6, 1], [8, nil, 0]].each do |id, creature, ours|
    rec.execute('INSERT INTO attacks VALUES (?, ?, ?, ?)', [id, id == 7 ? 2 : 1, creature, ours])
  end
  rec.execute('INSERT INTO flares VALUES (1, 6, 1), (2, 8, 1), (3, 7, 0)')
  rec.execute('INSERT INTO resolutions VALUES (1, 7)')
  # hits: [attack, flare, creature, damage]
  [[1, nil, 1, 50], [2, nil, 1, 30], [3, nil, 2, 20], [4, nil, 2, 90], [5, nil, 3, 70], [6, 1, 5, 25], [8, 2, 4, 12]].each do |attack, flare, creature, damage|
    rec.execute('INSERT INTO hits (attack_id, flare_id, session_id, creature_id, damage) VALUES (?, ?, 1, ?, ?)', [attack, flare, creature, damage])
  end
  rec.execute('INSERT INTO hits (attack_id, session_id, creature_id, damage) VALUES (7, 2, 6, 40)')
  rec.execute('INSERT INTO statuses (session_id, creature_id) VALUES (2, 6)')
  rec.close
  # Summed earlier under a cycle too short to keep, which the hunt then replaced
  # from the same moment: the next pass must not count its creatures twice
  run_sql("INSERT INTO combat_stats (game, character, cycle_id, start_time, creature, fought, damage) VALUES (?, ?, 'dropped', ?, 'foot ninja', 1, 20)",
          *WHO, t - 60)
  manager = A::CombatManager
  manager.instance_variable_set(:@path, path)
  manager.instance_variable_set(:@mark, 0.0)
  manager.rollup(path, WHO)
  A::Database.flush
  summed = lambda do
    A::Database.all('SELECT cycle_id = ? AS in_hunt, creature, fought, kills, assists, damage, hits, kill_damage FROM combat_stats ' \
                    'ORDER BY creature', hunt).map(&:values)
  end
  first = summed.call
  # A later hit on the ninja: its hunt is summed again on the next pass
  check = SQLite3::Database.new(path)
  check.execute('INSERT INTO hits (attack_id, session_id, creature_id, damage) VALUES (3, 1, 2, 5)')
  check.execute('UPDATE creatures SET last_seen = ? WHERE id = 2', [t + 200])
  check.close
  manager.rollup(path, WHO)
  A::Database.flush
  again = A::Database.one("SELECT damage, hits FROM combat_stats WHERE creature = 'foot ninja'").values
  manager.prune
  left = SQLite3::Database.new(path)
  kept = %w[sessions creatures attacks flares resolutions hits statuses].to_h { |table| [table, left.get_first_value("SELECT COUNT(*) FROM #{table}")] }
  left.close
  result = { 'rows' => first, 'mark' => A::Database.one('SELECT value FROM metadata WHERE key = ?', "combat_mark_#{WHO}")['value'].to_f.positive?,
             'again' => again, 'kept' => kept }

when 'reload'
  # Loading the body again must not warn about redefined constants
  warnings = StringIO.new
  old = $stderr
  $stderr = warnings
  $VERBOSE = true
  eval(source[0...cut], TOPLEVEL_BINDING, lic_path)
  $VERBOSE = nil
  $stderr = old
  result = { 'constant_warnings' => warnings.string.lines.grep(/constant/) }

else
  abort "unknown scenario #{scenario}"
end

puts JSON.generate(result)
