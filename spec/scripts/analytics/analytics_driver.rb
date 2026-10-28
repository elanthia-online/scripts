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
    def self.quiet_command_xml(*) = $bank_lines
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
  DownstreamHook.run('The halfling cannibal rots away.')
  # Lines as the XML frontend sends them; this kill ends at the prompt, not at a decay line
  DownstreamHook.run('You search the <pushBold/><a exist="1" noun="sentinel">veiled sentinel</a><popBold/>.')
  DownstreamHook.run('<pushBold/><a exist="1" noun="sentinel">She</a><popBold/> had 345 silvers on <pushBold/>her<popBold/>.')
  DownstreamHook.run('<prompt time="1793074672">&gt;</prompt>')
  DownstreamHook.run('You search the <pushBold/><a exist="2" noun="lurk">shambling lurk</a><popBold/>.')
  DownstreamHook.run("It didn't carry any silver.")
  DownstreamHook.run('Decay rapidly races over a shambling lurk\'s form as it collapses into foul-smelling compost.')
  DownstreamHook.run('They locate a pile of 500 coins, reclaiming them')
  DownstreamHook.run('You gather the remaining 250 coins from inside your box')
  A::SilverManager.record_vendor_silver(12_345, 'gemshop', 'Bob')
  A::SilverManager.record_vendor_visit('gemshop', NOW - 100, NOW - 50, 12_345)
  A::Database.record_item_sale(WHO, A::Database.session_for(WHO), 'a black opal', 'opal', 5000, 'gemshop', 'Bob', 2)
  sleep 0.5
  kills = A::Database.all('SELECT creature, total_silver, game, character FROM kill_stats ORDER BY creature')
  result = {
    'hook_registered' => hook, 'cfg_hunt' => cfg[:hunt_script],
    'kills' => kills.map(&:values),
    'box' => A::Database.all("SELECT amount FROM silver_events WHERE source_category = 'box' ORDER BY amount").map { |r| r['amount'] },
    'sale' => A::Database.one("SELECT amount, vendor_type FROM silver_events WHERE source_category = 'sale'").values,
    'visit_seconds' => A::Database.one('SELECT duration_seconds FROM vendor_visits')['duration_seconds'],
    'unit_price' => A::Database.one('SELECT unit_price FROM item_sales')['unit_price']
  }
  A::SilverManager.stop
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
  passed = ['look', ';other thing', ';analytics'].map { |line| UpstreamHook.run(line) }
  result = {
    'report' => report.include?('Summary'), 'status' => status.include?('Database:'),
    'stats' => stats.include?('cycles:'), 'help' => help.include?('Usage'),
    'caught' => caught, 'passed' => passed,
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
