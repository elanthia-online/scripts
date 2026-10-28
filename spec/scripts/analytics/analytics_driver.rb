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
  def self.name = 'Torvek'
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
  def self.fxp_current = 400
  def self.fxp_max = 800
  def self.fame = 5000
end

BANK_LINES = ['The Bank amounts on deposit:', 'Icemule Trace: 1,500,000',
              "Wehnimer's Landing: 2,100,000,000", 'Total: 2,101,500,000'].freeze
$bank_lines = BANK_LINES
$lich_char_regex = Regexp.union(',', ';')

module Lich
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

  def initialize(type, creature, area, number)
    @type = type
    @creature = creature
    @town = area
    @requirements = { area: area, number: number }
  end

  def none? = false
end

module Bounty
  def self.task = $task
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
def seed_cycles(who, session, start, rest: true)
  hunt = A::Database.start_cycle(who, session, :hunt, 'bigshot', 'torvek_crags',
                                 exp_total: 1_000_000, exp_field: 100, exp_max: 800, fame: 10, encumbrance: 20.0)
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', start, hunt)
  A::Database.end_cycle(hunt, { exp_total: 1_100_000, exp_field: 700, exp_max: 800, fame: 20, encumbrance: 40.0 },
                        'Too many items')
  run_sql('UPDATE cycles SET end_time = ?, duration_seconds = 2700 WHERE cycle_id = ?', start + 2700, hunt)
  return unless rest

  rest_id = A::Database.start_cycle(who, session, :rest, 'my_rest', 'torvek_crags',
                                    exp_total: 1_100_000, exp_field: 700, exp_max: 800, fame: 20, encumbrance: 40.0)
  run_sql('UPDATE cycles SET start_time = ?, end_time = ?, duration_seconds = 400, ' \
          'exp_total_end = 1100000, rest_reason = ? WHERE cycle_id = ?', start + 2700, start + 3100, 'Too many items', rest_id)
  A::Database.record_rest_steps(who, rest_id, start + 2700, { 'travel' => 120.0, 'selling' => 80.5 })
end

# Three characters over the last few days: two games, one shared name
def seed_history
  [WHO, A::Who.new('GS3', 'Ashur'), A::Who.new('GSF', 'Torvek')].each do |who|
    session = A::Database.session_for(who)
    midnight = A::Util.midnight(Date.today)
    seed_cycles(who, session, NOW - 5000) # finished within the last 24 hours, so it shows on the dashboard
    3.downto(1) do |ago|
      seed_cycles(who, session, midnight - (ago * 86_400) + (8 * 3600))
      run_sql('INSERT INTO kill_stats (game, character, date, profile, creature, kill_count, total_silver, last_kill_at) ' \
              'VALUES (?,?,?,?,?,?,?,?) ON CONFLICT DO NOTHING',
              *who, (Date.today - ago).to_s, 'torvek_crags', 'kobold', 100, 5000, NOW - 100)
    end
  end
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
    'who'           => [WHO.to_s, WHO.to_a, A::Who.parse('GS3:Torvek') == WHO, { WHO => 1 }[A::Who.parse('GS3:Torvek')],
                        A::Who.new('GSF', 'Torvek') == WHO]
  }

when 'settings'
  file = A::Settings.path(WHO)
  defaults = A::Settings.load(WHO)
  written = File.exist?(file)
  File.write(file, "rest_script: my_rest\nalerts:\n  no_kill_minutes: 3\nprofile_room_map:\n  crags: 1234\n")
  custom = A::Settings.load(WHO)
  File.write(file, "rest_script: [unclosed\n")
  broken = A::Settings.load(WHO)
  result = {
    'path' => file.delete_prefix("#{DATA_DIR}/"), 'written' => written,
    'default_hunt' => defaults[:hunt_script], 'default_rest' => defaults[:rest_script],
    'rest_steps_first' => defaults[:rest_steps].keys.first,
    'custom_rest' => custom[:rest_script], 'custom_no_kill' => custom[:alerts][:no_kill_minutes],
    'kept_default_drop' => custom[:alerts][:silver_drop_pct], 'room_map' => custom[:profile_room_map],
    'broken_falls_back' => broken[:hunt_script], 'broken_reported' => OUT.any? { |line| line.include?('ERROR (settings)') }
  }

when 'database'
  A::Database.connect!
  session = A::Database.session_for(WHO)
  hunt = A::Database.start_cycle(WHO, session, :hunt, 'bigshot', 'torvek_crags', exp_total: 100, exp_field: 10)
  run_sql('UPDATE cycles SET start_time = ? WHERE cycle_id = ?', NOW - 600, hunt)
  ended = A::Database.end_cycle(hunt, { exp_total: 5100, exp_field: 700, exp_max: 800, fame: 11, encumbrance: 35.0 }, 'Too many items')
  saved = A::Database.one('SELECT * FROM cycles WHERE cycle_id = ?', hunt)
  rest = A::Database.start_cycle(WHO, session, :rest, 'my_rest', 'torvek_crags', exp_total: 5100)
  run_sql('UPDATE cycles SET start_time = ?, rest_reason = ? WHERE cycle_id = ?', NOW - 300, 'Too many items', rest)
  A::Database.end_cycle(rest, {}, 'something else')
  A::Database.record_rest_steps(WHO, rest, NOW - 300, { 'travel' => 120.0, 'selling' => 80.5, 'waiting' => 0 })
  short = A::Database.start_cycle(WHO, session, :hunt, 'bigshot', nil, {})
  A::Database.record_kill(WHO, 'kobold', 'torvek_crags', 100)
  A::Database.record_kill(WHO, 'kobold', 'torvek_crags', 50)
  result = {
    'game_column' => saved['game'], 'character_column' => saved['character'],
    'session_cached' => session == A::Database.session_for(WHO),
    'session_per_game' => A::Database.session_for(A::Who.new('GSF', 'Torvek')) != session,
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

when 'bounties'
  A::Database.connect!
  session = A::Database.session_for(WHO)
  first = A::Database.start_bounty(WHO, session, nil, 'cull', 'kobold', 'Icemule Trace', 20)
  second = A::Database.start_bounty(WHO, session, nil, 'dangerous', 'troll', 'Wehnimer', nil)
  third = A::Database.start_bounty(WHO, session, nil, 'gem', nil, "Ta'Vaalor", 5)
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
  rows = A::Database.all('SELECT bank_name, balance FROM bank_snapshots ORDER BY bank_name')
  warned = OUT.any? { |line| line.include?('2.0B') }
  $bank_lines = ['The Bank amounts on deposit:', 'Icemule Trace: 2,500,000', 'Total: 2,500,000']
  A::SilverManager.take_snapshot
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
  DownstreamHook.run('They locate a pile of 500 coins, reclaiming them')
  DownstreamHook.run('You gather the remaining 250 coins from inside your box')
  A::SilverManager.record_vendor_visit('gemshop', NOW - 100, NOW - 50, 12_345)
  A::Database.record_item_sale(WHO, A::Database.session_for(WHO), 'a black opal', 'opal', 5000, 'gemshop', 'Bob', 2)
  A::SilverManager.stop # records the kill still being read
  sleep 0.5
  kills = A::Database.all('SELECT creature, total_silver, game, character FROM kill_stats ORDER BY creature')
  result = {
    'hook_registered' => hook, 'cfg_hunt' => cfg[:hunt_script],
    'kills' => kills.map(&:values),
    'box' => A::Database.all("SELECT amount FROM silver_events WHERE source_category = 'box' ORDER BY amount").map { |r| r['amount'] },
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
      'names_in_character' => texts['character'].join.scan(/Torvek|Ashur/).uniq.sort,
      'min_range_lines'    => ranges.values.min,
      'bad_range'          => A::Report::Text.exp_summary(conn, 'bogus').first
    }
  end

when 'dashboard'
  A::Database.connect!
  seed_history
  overview = A::Dashboard.overview
  torvek = overview['characters'].find { |c| c['id'] == 'GS3:Torvek' }
  detail = A::Dashboard.character('GS3:Torvek', 'weekly')
  port = 38_000 + (Process.pid % 1000)
  A::Dashboard.start(port, '127.0.0.1')
  sleep 0.3
  http = Net::HTTP.new('127.0.0.1', port)
  index = http.get('/')
  api = JSON.parse(http.get('/api/overview').body)
  result = {
    'ids' => overview['characters'].map { |c| c['id'] }.sort,
    'fields' => %w[state timeline pace today bounty mind encumbrance rest_reasons].all? { |key| torvek.key?(key) },
    'trend_labels' => %w[daily weekly monthly].map { |range| A::Dashboard.character('GS3:Torvek', range)['trend']['labels'].size },
    'detail_id' => detail['id'], 'steps' => detail['steps'].keys.sort,
    'unknown' => A::Dashboard.character('GS3:Nobody', 'daily').nil?,
    'http_index' => [index.code, index.body.include?('GS4 Analytics'), index['content-security-policy'].to_s.include?("default-src 'none'")],
    'http_api' => api['characters'].size,
    'http_character' => http.get('/api/character?name=GS3%3ATorvek&range=weekly').code,
    'http_unknown' => http.get('/api/character?name=nobody').code,
    'http_missing' => http.get('/nope').code,
    'http_post' => http.post('/', 'x').code
  }
  A::Dashboard.stop
  result['stopped'] = !A::Dashboard.running?

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
    'stats' => stats.include?('cycles:'), 'help' => help.include?('Usage'),
    'caught' => caught, 'dashboard' => dashboard, 'passed' => passed,
    'queued' => cli.instance_variable_get(:@commands).size
  }

when 'standalone'
  # No collector: the read-only reader works, refuses writes, and a missing file is reported
  A::Database.connect!
  seed_history
  A::Database.close
  result['connected'] = A::Database.connected?
  A::Database.reader do |conn|
    result['overview'] = A::Dashboard.send(:build_overview)['characters'].size
    result['report_lines'] = A::Report::Text.character_summary(conn).size
    result['write_refused'] = begin
      conn.run('DELETE FROM cycles')
      false
    rescue StandardError
      true
    end
  end
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
  withdraw = A::Database.one("SELECT balance, snapshot_type FROM bank_snapshots WHERE bank_name = '__total__'")
  hook_ignored = (A::SilverManager.record_vendor_silver(999, 'gemshop', 'Bob'); count.call('silver_events'))

  # A BANK ACCOUNT block names the bank, so later deposits update it
  feed.call('You currently have the following amounts on deposit:', '', '<output class="mono"/>',
            '      Vornavis Bank of Solhaven: 422,471,304', '                          Total: 422,471,304',
            '<output class=""/>', 'You currently have 0 inter-town bank transfer options available.')
  settle.call
  feed.call('You deposit 4,812 silvers into your account.  The teller carefully records the transaction and says, ' \
            '"Thank you, <a exist="-1" noun="Tysong">Tysong</a>.  This brings your total to 422,476,116 silvers.  Have a nice day!"')
  settle.call
  one_bank = A::Database.all("SELECT bank_name, balance, delta_silver, snapshot_type FROM bank_snapshots WHERE snapshot_type != 'withdraw' ORDER BY timestamp, rowid, bank_name").map(&:values)

  # With two banks a deposit can't be placed, so nothing is recorded
  feed.call('You currently have the following amounts on deposit:', '      Bank A: 100', '      Bank B: 200', '      Total: 300')
  settle.call
  rows_before = count.call('bank_snapshots')
  feed.call('You deposit 50 silvers into your account.  The teller carefully records the transaction and says, ' \
            '"Thank you, Tysong.  This brings your total to 350 silvers.  Have a nice day!"')
  settle.call
  ambiguous_rows = count.call('bank_snapshots') - rows_before

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
  hook_when_off = count.call('silver_events') - before.first

  result = {
    'sales' => sales.map(&:values), 'items' => items.map(&:values),
    'withdraw_total_only' => withdraw.values, 'hook_ignored' => hook_ignored,
    'one_bank' => one_bank, 'ambiguous_rows' => ambiguous_rows, 'command_rows' => command_rows,
    'disabled' => disabled, 'hook_when_off' => hook_when_off
  }
  A::SilverManager.stop

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
    'hunting' => signals.call(['bigshot'], :hunting),
    'ready' => signals.call(['bigshot'], :ready),
    'resting' => signals.call(['bigshot'], :resting),
    'rest_stop' => signals.call(['bigshot'], :rest_stop),
    'stale_after_exit' => signals.call([], :resting),
    'nil_status' => signals.call(['bigshot'], nil)
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
  session = A::Database.session_for(WHO)
  set = ->(name, value) { manager.instance_variable_set(name, value) }
  start_state = lambda do |state, cycle_type|
    set.call(:@who, WHO)
    set.call(:@cfg, cfg)
    set.call(:@session_id, session)
    set.call(:@current_state, state)
    set.call(:@rest_steps, Hash.new(0.0))
    set.call(:@last_step_at, nil)
    set.call(:@last_bigshot_status, nil)
    set.call(:@current_cycle_id, A::Database.start_cycle(WHO, session, cycle_type, 'bigshot', 'torvek_crags', {}))
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
  rest = A::Database.one('SELECT cycle_type, rest_reason FROM cycles WHERE cycle_id = ?', manager.current_cycle_id)
  result['reasons'] = [A::Database.one('SELECT rest_reason FROM cycles WHERE cycle_id = ?', hunt_id)['rest_reason'],
                       rest['cycle_type'], rest['rest_reason']]

  # Not after bigshot said it was resting itself
  start_state.call(:hunt, :hunt)
  set.call(:@last_bigshot_status, :resting)
  hunt_id = manager.current_cycle_id
  $rest_reason = 'encumbered.'
  manager.send(:transition_to, :rest)
  result['own_rest_reason'] = A::Database.one('SELECT rest_reason FROM cycles WHERE cycle_id = ?', hunt_id)['rest_reason']

  # An idle character running a script by hand does not start a rest
  start_state.call(:idle, :idle)
  result['idle_manual_script'] = signals.call(['go2'])

when 'town_bounty'
  # A bounty finished in town, with no hunt running, still gets its type and area
  A::Database.connect!
  A::Settings.load(WHO)
  manager = A::BountyManager
  manager.instance_variable_set(:@who, WHO)
  $running = []
  task = lambda do |type, creature, area, number|
    $task = TaskStub.new(type, creature, area, number)
  end
  row = ->(label) { A::Database.one("SELECT bounty_type, creature, area, count_required, status, silver_reward, received_time, completed_time FROM bounties WHERE bounty_type = '#{label}'") }

  task.call(:gem, '', 'Solhaven', 9)
  manager.send(:check_task)
  recorded_while_not_hunting = A::Database.all('SELECT 1 FROM bounties').size
  $task = nil
  manager.send(:handle_reward, 1250, 1000, 4812)
  gem = row.call('gem')

  # Seen long ago: too old to explain a reward
  task.call(:herb, 'moss', 'Vornavis', 4)
  manager.send(:check_task)
  $task = nil
  manager.instance_variable_get(:@seen)[:at] -= 700
  manager.send(:handle_reward, 100, 100, 100)

  # Never seen
  manager.send(:handle_reward, 7, 8, 9)

  result = {
    'recorded_while_not_hunting' => recorded_while_not_hunting,
    'gem' => gem.values_at('bounty_type', 'creature', 'area', 'count_required', 'status', 'silver_reward'),
    'received_before_completed' => gem['received_time'] <= gem['completed_time'],
    'untracked' => A::Database.all("SELECT silver_reward FROM bounties WHERE bounty_type = 'untracked' ORDER BY silver_reward").map { |r| r['silver_reward'] }
  }

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
