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

    it 'keeps only the total when a withdrawal comes before any BANK ACCOUNT' do
      expect(game_text['withdraw_total_only']).to eq([357_850_148, 'withdraw'])
    end

    it 'records a BANK ACCOUNT listing, then updates that bank on a deposit' do
      expect(game_text['one_bank']).to eq(
        [['Vornavis Bank of Solhaven', 422_471_304, nil, 'bank_account'], ['__total__', 422_471_304, 64_621_156, 'bank_account'],
         ['Vornavis Bank of Solhaven', 422_476_116, 4812, 'deposit'], ['__total__', 422_476_116, 4812, 'deposit']]
      )
    end

    it 'records nothing for a deposit that cannot be placed among several banks' do
      expect(game_text['ambiguous_rows']).to eq(0)
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
      expect(reports['min_range_lines']).to be > 3
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

    it 'serves the JSON API' do
      expect(dashboard.values_at('http_api', 'http_character', 'http_unknown')).to eq([3, '200', '404'])
    end

    it 'answers only GET for known paths' do
      expect(dashboard.values_at('http_missing', 'http_post')).to eq(%w[404 405])
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

    it 'reads the database read-only' do
      expect(standalone.values_at('connected', 'overview', 'write_refused')).to eq([false, 3, true])
    end

    it 'builds reports from it' do
      expect(standalone['report_lines']).to be > 10
    end

    it 'says so when there is no database yet' do
      expect(standalone['missing']).to be(true)
    end
  end
end
