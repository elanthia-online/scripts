# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'open3'

# analytics.lic: hunting analytics (collector, SQLite storage, reports,
# dashboard server and command line).
#
# Every example runs analytics.lic's real code, loaded up to its entry point,
# in a child process (see analytics_driver.rb for why) against a temporary
# DATA_DIR, so nothing here touches a real database. The driver replaces only
# the game and the Lich runtime (XMLData, Script, the hook sets, bank text);
# the SQL, the hooks and the report and dashboard builders are the script's
# own. Each example reads back what was written to SQLite or served over HTTP
# and compares it with fixed expected values.
#
# Not covered: the cycle state machine and the bounty hook run on timers of
# several seconds, so they are left out; the bounty rows they write are
# covered through the database API instead.
module AnalyticsSpec
  LIC_PATH = find_lic_source('analytics.lic', from: File.expand_path('..', __dir__))
  DRIVER = File.join(__dir__, 'analytics_driver.rb')

  def self.run(scenario)
    out, err, status = Open3.capture3(RbConfig.ruby, DRIVER, LIC_PATH, scenario)
    raise "analytics_driver #{scenario} failed (#{status.exitstatus}):\n#{err}#{out}" unless status.success?

    JSON.parse(out.lines.last)
  end

  # Scenarios are independent child processes; run each once and share the result
  def self.result(scenario)
    (@results ||= {})[scenario] ||= run(scenario)
  end
end

RSpec.describe 'analytics.lic' do
  def result(scenario) = AnalyticsSpec.result(scenario)

  describe 'loading' do
    it 'can be loaded again without constant warnings' do
      expect(result('reload')['constant_warnings']).to eq([])
    end
  end

  describe 'Util and Who' do
    subject(:util) { result('util') }

    it 'formats numbers and durations' do
      expect(util.values_at('fmt', 'short', 'hms', 'hm')).to eq(
        [['1,234,567', '-1,234', '12'], ['1.5M', '-2.50B', '950'], '1:02:05', ['1:02', '0:00']]
      )
    end

    it 'computes statistics, returning nil when there is nothing to compute' do
      expect(util.values_at('mode', 'median', 'percent')).to eq([2.5, [2.0, 2.5, nil], [25.0, nil]])
    end

    it 'converts binary game text to UTF-8 so SQLite stores it as text' do
      expect(util['binary_string']).to eq('UTF-8')
    end

    it 'identifies a character by game and name' do
      expect(util['who']).to eq(['GS3:Torvek', %w[GS3 Torvek], true, 1, false])
    end
  end

  describe 'Settings' do
    subject(:settings) { result('settings') }

    it 'writes the defaults under the game and character on first load' do
      expect(settings.values_at('path', 'written', 'default_hunt', 'default_rest', 'rest_steps_first')).to eq(
        ['GS3/Torvek/analytics.yaml', true, 'bigshot', nil, 'go2']
      )
    end

    it 'overrides only the keys the file sets' do
      expect(settings.values_at('custom_rest', 'custom_no_kill', 'kept_default_drop', 'room_map')).to eq(
        ['my_rest', 3, 50, { 'crags' => 1234 }]
      )
    end

    it 'reports an unreadable file once and falls back to the defaults' do
      expect(settings.values_at('broken_falls_back', 'broken_reported')).to eq(['bigshot', true])
    end
  end

  describe 'CycleManager bigshot status' do
    subject(:signals) { result('bigshot_status') }

    it 'counts bigshot as hunting, not resting, while it hunts or is ready' do
      expect(signals.values_at('hunting', 'ready')).to eq([[false, true], [false, true]])
    end

    it 'counts bigshot as resting when its status is resting or rest_stop' do
      expect(signals.values_at('resting', 'rest_stop')).to eq([[true, true], [true, true]])
    end

    it 'ignores a stale status once bigshot is no longer running' do
      expect(signals.values_at('stale_after_exit', 'nil_status')).to eq([[false, false], [false, true]])
    end

    it 'can be turned off for characters that hunt with something else' do
      expect(signals['disabled']).to eq([false, true])
    end

    it 'still detects a rest script' do
      expect(signals['rest_script_still_works']).to eq([true, false])
    end

    it 'shows the status in ;analytics status' do
      expect(signals['status_line']).to eq('Bigshot status: :resting')
    end
  end

  describe 'a hunt interrupted by another script' do
    subject(:trip) { result('interrupted_hunt') }

    it 'counts a rest-step script running after a hunt as resting' do
      expect(trip.values_at('hunt_then_trip', 'hunt_nothing_running')).to eq([[true, false], [true, false]])
    end

    it 'keeps hunting while the hunt script runs, even with eloot running' do
      expect(trip['hunt_running']).to eq([false, true])
    end

    it 'stops counting the trip once no step has run for a while' do
      expect(trip['grace_expired']).to eq([false, false])
    end

    it 'does not start a rest from a script run by hand while idle' do
      expect(trip['idle_manual_script']).to eq([false, false])
    end

    it 'does not give the idle time after a rest the rest reason bigshot left behind' do
      expect(trip['idle_reason']).to eq(['idle', nil])
    end

    it 'names the script that stopped the hunt, on the hunt and on the rest' do
      expect(trip['reasons']).to eq(['stopped by ebounty', 'rest', 'stopped by ebounty'])
    end

    it 'keeps bigshot\'s own reason when it rested by itself' do
      expect(trip['own_rest_reason']).to eq('encumbered.')
    end
  end

  describe 'bounties finished in town' do
    subject(:town) { result('town_bounty') }

    it 'does not record a task before a hunt starts' do
      expect(town['recorded_while_not_hunting']).to eq(0)
    end

    it 'describes the reward from the task last seen' do
      expect(town['gem']).to eq(['gem', 'piece of leopard skin jasper', 'Solhaven', 9, 'completed', 4812])
    end

    it 'shows a gem or herb with its town, and other bounties by creature or area' do
      expect(town['targets']).to eq(
        ['piece of leopard skin jasper (Solhaven)', 'Solhaven', 'blue moss (Vornavis)', 'kobold', 'opal', "Ta'Vaalor"]
      )
    end

    it 'dates the bounty from when the task was first seen, even if the reward came much later' do
      expect(town['received_before_completed']).to be(true)
    end

    it 'falls back to untracked when the task was removed, replaced or never seen' do
      expect(town['untracked']).to eq([9, 55, 100])
    end
  end

  describe 'Database when busy' do
    subject(:busy) { result('busy_database') }

    it 'retries a write that finds the database locked, once, without repeating its earlier statements' do
      expect(busy.values_at('attempts', 'rows')).to eq([3, %w[retry.a retry.b]])
    end

    it 'keeps queued writes in order and skips one that fails for another reason' do
      expect(busy['order']).to eq(%w[a broken b])
    end

    it 'reports a busy database and other failures once each' do
      expect(busy.values_at('busy_reported', 'failure_reported')).to eq([true, true])
    end

    it 'tells a busy database from other errors' do
      expect(busy['busy_tells_apart']).to eq([false, false])
    end
  end

  describe 'Database' do
    subject(:database) { result('database') }

    it 'creates the database in DATA_DIR' do
      expect(database['db_in_data_dir']).to be(true)
    end

    it 'records the game and the character on every row' do
      expect(database.values_at('game_column', 'character_column')).to eq(%w[GS3 Torvek])
    end

    it 'keeps one session per game and character' do
      expect(database.values_at('session_cached', 'session_per_game')).to eq([true, true])
    end

    it 'closes a cycle with its duration and ending figures' do
      expect(database.values_at('duration_ok', 'exp_end', 'rest_reason')).to eq([true, 5100, 'Too many items'])
    end

    it 'keeps the reason a rest started with' do
      expect(database['rest_reason_kept']).to eq('Too many items')
    end

    it 'skips rest steps that took no time' do
      expect(database['rest_steps']).to eq(%w[selling travel])
    end

    it 'discards cycles that were over almost at once' do
      expect(database['short_dropped']).to be(true)
    end

    it 'adds up kills for the same creature, profile and day' do
      expect(database['kills']).to eq([2, 150])
    end

    it 'opens an existing database again' do
      expect(database['reconnect_rows']).to eq(2)
    end
  end

  describe 'bounties' do
    subject(:bounties) { result('bounties') }

    it 'records the rewards of a completed bounty' do
      expect(bounties['completed']).to eq(['completed', 11_066, 1100, 1106, 20])
    end

    it 'marks abandoned and expired bounties and leaves none active' do
      expect(bounties.values_at('abandoned', 'expired', 'active')).to eq(['abandoned', 'expired', 0])
    end
  end

  describe 'bank snapshots' do
    subject(:banks) { result('banks') }

    it 'stores each bank and a total' do
      expect(banks['banks']).to eq(["Icemule Trace", "Wehnimer's Landing", '__total__'])
    end

    it 'warns about a bank at the 2.0B cap in the log only, not Discord' do
      expect(banks.values_at('warned', 'discord_spam')).to eq([true, 0])
    end

    it 'records a bank that is no longer listed as empty' do
      expect(banks['emptied_balance']).to eq(0)
    end

    it 'computes the total change since the previous snapshot' do
      expect(banks['total_delta']).to eq(2_500_000 - 2_101_500_000)
    end
  end

  describe 'SilverManager' do
    subject(:collector) { result('collector') }

    it 'adds and removes its game hook' do
      expect(collector.values_at('hook_registered', 'hook_removed')).to eq([true, true])
    end

    it 'records each kill, ended by the prompt, the next search or stopping, with its silver' do
      expect(collector['kills']).to eq(
        [['halfling cannibal', 1234, 'GS3', 'Torvek'], ['shambling lurk', 0, 'GS3', 'Torvek'],
         ['veiled sentinel', 345, 'GS3', 'Torvek']]
      )
    end

    it 'records box silver' do
      expect(collector['box']).to eq([250, 500])
    end

    it 'records a vendor visit and the price per item' do
      expect(collector.values_at('visit_seconds', 'unit_price')).to eq([50, 2500])
    end
  end

  describe 'sales and bank balances read from the game text' do
    subject(:game_text) { result('game_text') }

    it 'records each vendor sale as silver, with the vendor split into type and name' do
      expect(game_text['sales']).to eq(
        [['pawnbroker', nil, 77], ['vendor', 'Walsor Gryhm', 410], ['jeweler', 'Kahlyr', 1250]]
      )
    end

    it 'records the item sold, its noun and its price' do
      expect(game_text['items']).to eq(
        [['ayanad crystal', 'crystal', 77, 'pawnbroker', nil], ['quartz orb', 'orb', 410, 'vendor', 'Walsor Gryhm'],
         ['gold ingot', 'ingot', 1250, 'jeweler', 'Kahlyr']]
      )
    end

    it 'does not count locksmith fees or the teller as sales' do
      expect(game_text['sales'].size).to eq(3)
    end

    it 'records nothing for a withdrawal that comes before any BANK ACCOUNT' do
      expect(game_text['withdraw_rows']).to eq(0)
    end

    it 'records a BANK ACCOUNT listing, then moves only the total on a deposit' do
      expect(game_text['one_bank']).to eq(
        [['Vornavis Bank of Solhaven', 422_471_304, nil, 'bank_account'], ['__total__', 422_471_304, nil, 'bank_account'],
         ['__total__', 422_476_116, 4812, 'deposit']]
      )
    end

    it 'moves the total by the amount deposited when there are several banks' do
      expect(game_text['two_bank_deposit']).to eq([['__total__', 350, 50]])
    end

    it 'does not record the output of its own BANK ACCOUNT command twice' do
      expect(game_text['command_rows']).to eq(2)
    end

    it 'ignores vendor_silver calls from scripts while sales are read from the game text' do
      expect(game_text['hook_ignored']).to eq(3)
    end

    it 'can be turned off, and then record_vendor_silver works again' do
      expect(game_text.values_at('disabled', 'hook_when_off')).to eq([true, 1])
    end
  end

  describe 'cycle and bounty writes while another session holds the database' do
    subject(:locked) { result('locked_cycle') }

    it 'moves to the rest at once, while the writes wait' do
      expect(locked['during']).to eq('state' => 'rest', 'cycle' => true, 'hunt_open' => true)
    end

    it 'closes the hunt with its real end time and reason once the lock is released' do
      expect([locked['flushed'], locked['hunt']]).to eq([true, [true, 'encumbered.', true]])
    end

    it 'records the rest from the time it started' do
      expect(locked['rest']).to eq(['rest', 'encumbered.', true])
    end

    it 'records a bounty reward that arrived during the lock' do
      expect(locked['bounty']).to eq(['completed', 300])
    end
  end

  describe 'a new session created inside a queued write while the database is held' do
    it 'is written by the retry, with the write that needed it' do
      expect(result('locked_session')).to eq('sessions' => 1, 'linked' => 1)
    end
  end

  describe 'stopping after ;kill has stopped the writer' do
    subject(:killed) { result('killed_writer') }

    it 'writes what the writer left, then what was queued while stopping, in order' do
      expect(killed.values_at('written', 'lost_reported')).to eq([[600, 'killed'], false])
    end

    it 'waits for the lock once and reports what could not be written' do
      expect([killed['stop_seconds'] < 2, killed['lost_line']])
        .to eq([true, '3 analytics write(s) were lost, the database stayed busy'])
    end
  end

  describe 'the first bank listing for a character' do
    subject(:baseline) { result('baseline') }

    it 'is taken when there is no bank total yet' do
      expect(baseline['first']).to eq([true, 3])
    end

    it 'is not taken again once there is one, or with parse_bank off' do
      expect(baseline.values_at('again', 'off')).to eq([[false, 3], [false, 0]])
    end

    it 'lets the next deposit move the total' do
      expect([baseline['types'], baseline['deposit']]).to eq([[['baseline']], [2_101_501_000, 1000]])
    end
  end

  describe 'promissory notes and gem pouches' do
    subject(:notes) { result('notes') }

    it 'records sales paid with a note, and gem pouch sales paid either way' do
      expect(notes['sales']).to eq(
        [['diamond ring', 'ring', 22_555, 'Kahlyr'], ['gems from ruby red pouch', 'pouch', 8120, 'Kahlyr'],
         ['gems from leather gem pouch', 'pouch', 23_136, 'Kahlyr']]
      )
    end

    it 'moves the total for note deposits, and by what the same teller\'s balances show for a note round trip' do
      expect(notes['totals']).to eq([1_515_750, 1_515_660, 1_565_660, 1_563_160])
    end

    it 'agrees with the next BANK ACCOUNT listing' do
      expect(notes['listing']).to eq([1_563_160, 0])
    end

    it 'does not count again what a listing between two lines at the same teller already took in' do
      expect(result('teller_listing')).to eq('after_note' => 1_425_750, 'next_listing' => 0, 'after_snapshot' => 1_336_750)
    end
  end

  describe 'cycle edges' do
    subject(:edges) { result('cycle_edges') }

    it 'records the idle time from the moment the collector starts' do
      expect(edges['startup']).to eq(['idle', 'idle', true])
    end

    it 'marks the hunt that ended in a death, keeping why it stopped' do
      expect(edges['death']['hunt_reason']).to eq('died (wounded.)')
    end

    it 'leaves no gap where a cycle too short to keep was dropped' do
      expect(edges['death'].values_at('short_rest_dropped', 'no_gap', 'dead')).to eq([true, true, 'dead'])
    end
  end

  describe 'mind over capacity' do
    it 'shows as full on the dashboard' do
      expect(result('mind')).to eq('mind' => [100.0, 100.0], 'trend_capped' => true)
    end
  end

  describe 'bank deposits and withdrawals' do
    subject(:moves) { result('bank_moves') }

    it 'does not count silver in another town as earned when the first bank line is a withdrawal' do
      expect(moves['first_listing_earned']).to eq(0)
    end

    it 'moves the total by the amount deposited at a bank it did not know' do
      expect(moves['after_deposit']).to eq([5_098_500, 1000])
    end

    it 'leaves the known banks alone on a deposit, since it names no bank' do
      expect(moves['banks_after_deposit']).to eq('Bank of Icemule' => 97_500, 'Bank of Solhaven' => 5_000_000)
    end

    it 'adds up to the silver actually moved' do
      expect(moves.values_at('earned', 'last_total')).to eq([500, 5_098_000])
    end
  end

  describe 'Report' do
    subject(:reports) { result('reports') }

    it 'adds the game to a name only because two games are present' do
      expect(reports['labels']).to eq(
        'GS3:Ashur' => 'Ashur (GS3)', 'GS3:Torvek' => 'Torvek (GS3)', 'GSF:Torvek' => 'Torvek (GSF)'
      )
    end

    it 'renders all four reports' do
      expect(reports['lengths'].values).to all(be > 6)
    end

    it 'lists every character in the character summary' do
      expect(reports['names_in_character']).to eq(%w[Ashur Torvek])
    end

    it 'keeps the text ASCII and narrow enough for the game window' do
      expect([reports['ascii'], reports['widest'] < 130]).to eq([true, true])
    end

    it 'handles every range' do
      expect(reports['range_lines'].except('daily').values).to all(be > 3)
    end

    it 'still answers for today shortly after midnight, when there may be nothing yet' do
      expect(reports['range_lines']['daily']).to be >= 1
    end

    it 'counts each rest reason once, from the hunt it ended' do
      expect(reports['reason_rows']).to eq([['encumbered.', '1', '50.0%', '30.0 min'], ['unhandled exit', '1', '50.0%', '5.0 min']])
    end

    it 'gives usage for an unknown range' do
      expect(reports['bad_range']).to start_with('Usage: ;analytics report exp')
    end
  end

  describe 'Dashboard' do
    subject(:dashboard) { result('dashboard') }

    it 'lists characters by game and name' do
      expect(dashboard['ids']).to eq(%w[GS3:Ashur GS3:Torvek GSF:Torvek])
    end

    it 'builds every section of a character overview' do
      expect(dashboard['fields']).to be(true)
    end

    it 'charts 24 hours, 7 days or 30 days' do
      expect(dashboard['trend_labels']).to eq([24, 7, 30])
    end

    it 'returns a character detail with rest steps, and nothing for an unknown character' do
      expect(dashboard.values_at('detail_id', 'steps', 'unknown')).to eq(['GS3:Torvek', %w[selling travel], true])
    end

    it 'serves the page with a restrictive Content-Security-Policy' do
      expect(dashboard['http_index']).to eq(['200', true, true])
    end

    it 'serves the page with the save-image button, and allows the data image it draws from' do
      expect(dashboard['export_button']).to eq([true, true, true])
    end

    it 'serves the JSON API' do
      expect(dashboard.values_at('http_api', 'http_character', 'http_unknown')).to eq([3, '200', '404'])
    end

    it 'answers only GET for known paths' do
      expect(dashboard.values_at('http_missing', 'http_post')).to eq(%w[404 405])
    end

    it "answers only this computer's names when it is not open to the network" do
      expect(dashboard['local_hosts']).to eq(%w[403 403 200 200 200 200 403])
    end

    it 'refuses a header line cut off at the length limit, so its tail cannot pose as a Host header' do
      expect(dashboard['split_headers'].values_at('padded_tail', 'padded_long', 'too_long_line', 'long_request_line'))
        .to eq(%w[403 400 400 400])
    end

    it 'refuses a second Host header, and more headers than any browser sends' do
      expect(dashboard['split_headers'].values_at('two_hosts', 'two_local_hosts', 'too_many')).to eq(%w[400 400 400])
    end

    it 'still answers a request with a large cookie header' do
      expect(dashboard['split_headers']['long_cookie']).to eq('200')
    end

    it 'answers any Host header in LAN mode' do
      expect(dashboard['lan_hosts']).to eq(%w[200 200])
    end

    it 'stops serving' do
      expect(dashboard['stopped']).to be(true)
    end
  end

  describe 'CLI' do
    subject(:cli) { result('cli') }

    it 'runs the report, status, maintenance and help commands' do
      expect(cli.values_at('report', 'status', 'stats', 'help')).to eq([true, true, true, true])
    end

    it 'catches ;analytics commands typed while the collector runs, and queues them' do
      expect(cli.values_at('caught', 'queued')).to eq([[nil, nil], 2])
    end

    it 'starts the dashboard in the running collector when --dashboard is typed' do
      expect(cli['dashboard']).to eq([[nil, ['serve']], [nil, %w[serve 9000 lan]], [';analytics --lan', nil]])
    end

    it 'lets every other line through, including a bare ;analytics' do
      expect(cli['passed']).to eq(['look', ';other thing', ';analytics'])
    end
  end

  describe 'without a running collector' do
    subject(:standalone) { result('standalone') }

    it "reads the database through Lich's helper, so it gets its lock waits" do
      expect(standalone.values_at('connected', 'opened', 'hooked', 'overview')).to eq([false, true, true, 3])
    end

    it 'builds reports from it' do
      expect(standalone['report_lines']).to be > 10
    end

    it 'says so when there is no database yet' do
      expect(standalone['missing']).to be(true)
    end
  end
end
