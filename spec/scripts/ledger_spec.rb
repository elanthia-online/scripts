# Spec for ledger.lic rolling windows and hourly_chart bucket derivation.
#
# We do NOT load the .lic file: it opens a SQLite database at require time and
# needs the whole Lich runtime (Settings, XMLData, Char, Script, DATA_DIR ...).
# Instead the real method bodies are extracted from scripts/ledger.lic and
# evaluated against stubs, so these specs exercise production code and fail if
# that code changes shape.
#
# Every stub lives inside LedgerRollingSpec::Harness rather than at top level, so
# running the whole suite in one process cannot collide with constants other
# specs define. In particular Harness::Ledger shadows any top level Ledger, which
# is what the extracted bodies resolve when they say Ledger::Settings.

require 'date'

module LedgerRollingSpec
  SOURCE_PATH = File.expand_path('../../scripts/ledger.lic', __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")

  def self.extract(pattern, label)
    found = SOURCE[pattern]
    raise "could not extract #{label} from ledger.lic" unless found

    found
  end

  WINDOW_SRC = extract(/^  module Window\n.*?^  end$/m, 'Window module')
  CURRENT_GAIN_LOSS_SRC = extract(/^      def self\.current_gain_loss\(period, type:\).*?^      end$/m,
                                  'Query.current_gain_loss')
  CHART_SLOTS_SRC = extract(/^      hours = \(0\.\.\.number\)\.to_a\.map \{ \|offset\|\n.*?^      \}\.reverse$/m,
                            'hourly_chart slot mapping')
  PARSE_CLI_SRC = extract(/^    def self\.parse_cli_args\(args\).*?^    end$/m, 'parse_cli_args')
  PARSE_BOOL_SRC = extract(/^    def self\.parse_boolean_value\(value, default_true = true\).*?^    end$/m,
                           'parse_boolean_value')
  CHART_REQUESTED_SRC = extract(/^    def self\.chart_requested\?.*?^    end$/m, 'chart_requested?')
  BAR_CONSTANTS_SRC = extract(/^    HALF_BAR_WIDTH = .*?^    BAR_SEGMENT = .*?$/m,
                              'bar drawing constants')
  SIGNED_BAR_SRC = extract(/^    def self\.signed_bar\(amount, max_magnitude\).*?^    end$/m, 'signed_bar')
  NO_ACTIVITY_SRC = extract(/^        max_magnitude = hours\.map.*?if max_magnitude\.zero\?$/m,
                            'no activity guard')

  class Harness
    # Stands in for the Ledger namespace the extracted bodies reach for.
    module Ledger
      module Settings
        class << self
          attr_accessor :rolling

          def enabled?(key)
            key == 'rolling' && rolling == true
          end
        end
      end
    end

    # Real Window code under test, evaluated so Ledger:: resolves to the stub above.
    module_eval(WINDOW_SRC, SOURCE_PATH)
    Ledger::Window = Window

    # Records what the query layer was asked for instead of touching a database.
    module Query
      class << self
        attr_reader :calls

        def reset!
          @calls = []
        end

        # Keyword defaults mirror the real signature so current_gain_loss can call
        # this with only `type:`.
        def hourly_gain_loss(type:, hour: Time.now.hour, day: Time.now.day,
                             month: Time.now.month, year: Time.now.year)
          @calls << { method: :hourly_gain_loss, type: type, hour: hour, day: day,
                      month: month, year: year }
          0
        end

        def daily_gain_loss(type:)
          @calls << { method: :daily_gain_loss, type: type }
          0
        end

        def monthly_gain_loss(type:)
          @calls << { method: :monthly_gain_loss, type: type }
          0
        end

        def yearly_gain_loss(type:)
          @calls << { method: :yearly_gain_loss, type: type }
          0
        end

        def rolling_gain_loss(period, type:)
          @calls << { method: :rolling_gain_loss, period: period, type: type }
          0
        end

        def range_gain_loss(type:, from:, to:)
          @calls << { method: :range_gain_loss, type: type, from: from, to: to }
          0
        end
      end

      # Real dispatcher code under test. Evaluated at module level, not inside
      # `class << self`, so `def self.` lands on Query itself.
      module_eval(CURRENT_GAIN_LOSS_SRC, SOURCE_PATH)
    end

    # Wraps the real slot mapping block from hourly_chart so it can be driven
    # directly. The block closes over `number`, `from`, `rolling` and `type`.
    def self.chart_slots(type:, from:, number:, rolling:)
      module_eval(<<~RUBY, SOURCE_PATH)
        def self.__chart_slots(type, from, number, rolling)
        #{CHART_SLOTS_SRC}
          hours
        end
      RUBY
      __chart_slots(type, from, number, rolling)
    end

    # Settings stub carrying the real CLI parsing code.
    module CliSettings
      @defaults = { 'report_character' => false, 'report_fees' => false, 'rolling' => false }
      @settings = nil
      @saved = false

      class << self
        attr_reader :saved

        def reset!
          @settings = @defaults.dup
          @saved = false
          # Mirrors the production module body, which re-runs (and so re-clears this)
          # each time the script is loaded.
          @chart_requested = false
        end

        def [](key)
          @settings[key]
        end

        def settings_keys
          @settings.keys
        end

        def save_settings
          @saved = true
        end

        def display_help
          @settings['helped'] = true
        end

        def echo(_msg); end
      end

      module_eval(PARSE_CLI_SRC, SOURCE_PATH)
      module_eval(PARSE_BOOL_SRC, SOURCE_PATH)
      module_eval(CHART_REQUESTED_SRC, SOURCE_PATH)
    end

    # Real bar drawing code under test, with the chart's own constants.
    module ChartRender
      module_eval(BAR_CONSTANTS_SRC, SOURCE_PATH)
      module_eval(SIGNED_BAR_SRC, SOURCE_PATH)

      class << self
        # Drives the real no-activity guard. Returns the message when the chart
        # would bail out, or nil when it considers the window to have activity.
        def no_activity_message(hours, type = 'silver', number = hours.size)
          module_eval(<<~RUBY, SOURCE_PATH)
            def self.__guard(hours, type, number)
            #{NO_ACTIVITY_SRC}
              nil
            end
          RUBY
          __guard(hours, type, number)
        end

        def _respond(msg)
          msg
        end
      end
    end
  end
end

RSpec.describe 'ledger.lic rolling windows' do
  # Referenced through methods rather than constants: a constant assigned inside a
  # describe block lands on Object, not the example group, and would collide with
  # any other spec defining the same name.
  def harness
    LedgerRollingSpec::Harness
  end

  def window
    LedgerRollingSpec::Harness::Window
  end

  def query
    LedgerRollingSpec::Harness::Query
  end

  def rolling_setting
    LedgerRollingSpec::Harness::Ledger::Settings
  end

  def cli_settings
    LedgerRollingSpec::Harness::CliSettings
  end

  def chart_render
    LedgerRollingSpec::Harness::ChartRender
  end

  describe 'Window.start_of' do
    # 13:35 on a Thursday, the example from the original report.
    let(:from) { Time.local(2026, 8, 6, 13, 35, 0) }

    it 'starts the hourly window 60 minutes before now, not at the top of the hour' do
      expect(window.start_of(:hourly, from: from)).to eq(Time.local(2026, 8, 6, 12, 35, 0))
    end

    it 'starts the daily window 24 hours before now, not at midnight' do
      expect(window.start_of(:daily, from: from)).to eq(Time.local(2026, 8, 5, 13, 35, 0))
    end

    it 'starts the monthly window 30 days before now' do
      expect(window.start_of(:monthly, from: from)).to eq(Time.local(2026, 7, 7, 13, 35, 0))
    end

    it 'starts the yearly window 12 calendar months before now' do
      expect(window.start_of(:yearly, from: from)).to eq(Time.local(2025, 8, 6, 13, 35, 0))
    end

    it 'rejects an unknown period rather than silently returning nil' do
      expect { window.start_of(:weekly, from: from) }.to raise_error(ArgumentError, /weekly/)
    end
  end

  describe 'Window.months_ago' do
    it 'preserves time of day' do
      result = window.months_ago(12, Time.local(2026, 3, 15, 9, 7, 42))
      expect(result).to eq(Time.local(2025, 3, 15, 9, 7, 42))
    end

    it 'clamps a leap day back to the last valid day instead of raising' do
      result = window.months_ago(12, Time.local(2028, 2, 29, 10, 0, 0))
      expect(result).to eq(Time.local(2027, 2, 28, 10, 0, 0))
    end

    it 'crosses a year boundary' do
      result = window.months_ago(12, Time.local(2026, 1, 1, 0, 30, 0))
      expect(result).to eq(Time.local(2025, 1, 1, 0, 30, 0))
    end
  end

  describe 'Window.rolling?' do
    after { rolling_setting.rolling = nil }

    it 'is false by default' do
      rolling_setting.rolling = false
      expect(window.rolling?).to be false
    end

    it 'is true when the setting is enabled' do
      rolling_setting.rolling = true
      expect(window.rolling?).to be true
    end
  end

  describe 'hourly_chart slot derivation' do
    before { query.reset! }

    context 'with calendar buckets (rolling off)' do
      # 02:30 so the 6 hour window wraps back past midnight.
      let(:from) { Time.local(2026, 8, 6, 2, 30, 0) }
      let(:slots) { harness.chart_slots(type: 'silver', from: from, number: 6, rolling: false) }

      it 'includes hour 0 rather than the unmatchable hour 24' do
        expect(slots.map(&:first)).to eq([21, 22, 23, 0, 1, 2])
      end

      it 'queries the previous day for buckets that wrap past midnight' do
        slots
        queried = query.calls.map { |c| [c[:hour], c[:day]] }
        expect(queried).to contain_exactly([2, 6], [1, 6], [0, 6], [23, 5], [22, 5], [21, 5])
      end

      it 'passes month and year so a month boundary is not mis-attributed' do
        query.reset!
        harness.chart_slots(type: 'silver', from: Time.local(2026, 1, 1, 1, 0, 0),
                            number: 3, rolling: false)
        queried = query.calls.map { |c| [c[:year], c[:month], c[:day], c[:hour]] }
        expect(queried).to contain_exactly([2026, 1, 1, 1], [2026, 1, 1, 0], [2025, 12, 31, 23])
      end

      it 'uses the bucket query, not the range query' do
        slots
        expect(query.calls.map { |c| c[:method] }.uniq).to eq([:hourly_gain_loss])
      end
    end

    context 'with rolling windows (rolling on)' do
      let(:from) { Time.local(2026, 8, 6, 13, 35, 0) }
      let(:slots) { harness.chart_slots(type: 'silver', from: from, number: 3, rolling: true) }

      it 'asks for trailing 60 minute ranges ending at from' do
        slots
        ranges = query.calls.map { |c| [c[:from], c[:to]] }
        expect(ranges).to eq([
                               [Time.local(2026, 8, 6, 12, 35, 0), Time.local(2026, 8, 6, 13, 35, 0)],
                               [Time.local(2026, 8, 6, 11, 35, 0), Time.local(2026, 8, 6, 12, 35, 0)],
                               [Time.local(2026, 8, 6, 10, 35, 0), Time.local(2026, 8, 6, 11, 35, 0)]
                             ])
      end

      it 'produces contiguous non overlapping slots' do
        slots
        ranges = query.calls.map { |c| [c[:from], c[:to]] }.reverse
        ranges.each_cons(2) { |(_, prev_to), (next_from, _)| expect(next_from).to eq(prev_to) }
      end

      it 'uses the range query, not the bucket query' do
        slots
        expect(query.calls.map { |c| c[:method] }.uniq).to eq([:range_gain_loss])
      end
    end
  end

  describe 'Query.current_gain_loss' do
    before { query.reset! }
    after { rolling_setting.rolling = nil }

    context 'when rolling is off' do
      before { rolling_setting.rolling = false }

      {
        hourly:  :hourly_gain_loss,
        daily:   :daily_gain_loss,
        monthly: :monthly_gain_loss,
        yearly:  :yearly_gain_loss
      }.each do |period, expected|
        it "routes #{period} to #{expected}" do
          query.current_gain_loss(period, type: 'silver')
          expect(query.calls.first[:method]).to eq(expected)
        end
      end
    end

    context 'when rolling is on' do
      before { rolling_setting.rolling = true }

      %i[hourly daily monthly yearly].each do |period|
        it "routes #{period} to rolling_gain_loss preserving the period" do
          query.current_gain_loss(period, type: 'bounty')
          expect(query.calls.first)
            .to eq({ method: :rolling_gain_loss, period: period, type: 'bounty' })
        end
      end
    end

    it 'rejects an unknown period' do
      rolling_setting.rolling = false
      expect { query.current_gain_loss(:weekly, type: 'silver') }
        .to raise_error(ArgumentError, /weekly/)
    end
  end

  describe '--rolling CLI parsing' do
    before { cli_settings.reset! }

    it 'defaults to off' do
      cli_settings.parse_cli_args([])
      expect(cli_settings['rolling']).to be false
    end

    ['--rolling', '--rolling=on', '--rolling=true', '-rolling', '--ROLLING'].each do |arg|
      it "enables rolling for #{arg}" do
        cli_settings.parse_cli_args([arg])
        expect(cli_settings['rolling']).to be true
      end
    end

    ['--rolling=off', '--rolling=false', '--rolling=0', '--rolling=no'].each do |arg|
      it "disables rolling for #{arg}" do
        cli_settings.parse_cli_args([arg])
        expect(cli_settings['rolling']).to be false
      end
    end

    it 'persists the change' do
      cli_settings.parse_cli_args(['--rolling'])
      expect(cli_settings.saved).to be true
    end

    it 'leaves the other flags alone' do
      cli_settings.parse_cli_args(['--rolling'])
      expect(cli_settings['report_character']).to be false
      expect(cli_settings['report_fees']).to be false
    end

    it 'still parses the pre-existing flags' do
      cli_settings.parse_cli_args(['--report-fees', '--report-character'])
      expect(cli_settings['report_fees']).to be true
      expect(cli_settings['report_character']).to be true
      expect(cli_settings['rolling']).to be false
    end
  end

  describe 'constant redefinition guards' do
    # Lich re-evaluates a .lic in the same process, so an unguarded constant emits
    # "already initialized constant" on every run after the first.
    source = LedgerRollingSpec::SOURCE

    {
      'Window' => %w[HOUR DAY MONTH_DAYS YEAR_MONTHS],
      'chart'  => %w[HALF_BAR_WIDTH BAR_AXIS BAR_SEGMENT]
    }.each do |group, names|
      names.each do |name|
        it "guards #{group} constant #{name} against redefinition" do
          line = source.lines.find { |l| l =~ /^\s+#{name} = / }
          expect(line).not_to be_nil
          expect(line).to match(/unless const_defined\?\(:#{name}, false\)/)
        end
      end
    end

    it 'uses const_defined? with inherit false rather than defined?, which would be shadowed' do
      # defined?(NAME) also searches enclosing scopes and Object, so a top level
      # constant of the same name from another script would suppress the assignment
      # and leave this module reading the foreign value.
      expect(source).not_to match(/^\s+(?:HOUR|DAY|MONTH_DAYS|YEAR_MONTHS|HALF_BAR_WIDTH|BAR_AXIS|BAR_SEGMENT) = .*unless defined\?/)
    end

    it 're-evaluating the Window module twice emits no warning and keeps its own values' do
      warnings = []
      original_warn = Warning.method(:warn)
      Warning.singleton_class.define_method(:warn) { |msg, **| warnings << msg }

      begin
        holder = Module.new
        2.times { holder.module_eval(LedgerRollingSpec::WINDOW_SRC, LedgerRollingSpec::SOURCE_PATH) }
        expect(warnings.grep(/already initialized constant/)).to be_empty
        expect(holder.const_get(:Window)::DAY).to eq(86_400)
      ensure
        Warning.singleton_class.define_method(:warn) { |*args, **kw| original_warn.call(*args, **kw) }
      end
    end
  end

  describe '--chart CLI parsing' do
    before { cli_settings.reset! }

    it 'is not requested by default' do
      cli_settings.parse_cli_args([])
      expect(cli_settings.chart_requested?).to be false
    end

    ['--chart', '-chart', '--CHART'].each do |arg|
      it "requests the chart for #{arg}" do
        cli_settings.parse_cli_args([arg])
        expect(cli_settings.chart_requested?).to be true
      end
    end

    # The whole point of keeping it out of @settings: a persisted --chart would make
    # every later run print a chart and exit instead of tracking transactions.
    it 'never becomes a persisted setting' do
      cli_settings.parse_cli_args(['--chart'])
      expect(cli_settings['chart']).to be_nil
      expect(cli_settings.settings_keys).to contain_exactly('report_character', 'report_fees', 'rolling')
    end

    it 'combines with --rolling without disturbing it' do
      cli_settings.parse_cli_args(['--chart', '--rolling'])
      expect(cli_settings.chart_requested?).to be true
      expect(cli_settings['rolling']).to be true
    end

    it 'does not enable the chart for an unrelated flag' do
      cli_settings.parse_cli_args(['--report-fees'])
      expect(cli_settings.chart_requested?).to be false
    end
  end

  describe 'signed_bar rendering' do
    # 41 chars: HALF_BAR_WIDTH either side plus the axis.
    let(:full_width) { (chart_render::HALF_BAR_WIDTH * 2) + 1 }

    it 'does not raise when an amount is negative relative to a positive maximum' do
      # This is the exact shape that raised ArgumentError (negative argument).
      expect { chart_render.signed_bar(-5000, 1000) }.not_to raise_error
    end

    it 'draws negative amounts to the left of the axis' do
      bar = chart_render.signed_bar(-500, 500)
      left, right = bar.split(chart_render::BAR_AXIS, 2)
      expect(left.strip).to eq(chart_render::BAR_SEGMENT * chart_render::HALF_BAR_WIDTH)
      expect(right.strip).to be_empty
    end

    it 'draws positive amounts to the right of the axis' do
      bar = chart_render.signed_bar(500, 500)
      left, right = bar.split(chart_render::BAR_AXIS, 2)
      expect(left.strip).to be_empty
      expect(right.strip).to eq(chart_render::BAR_SEGMENT * chart_render::HALF_BAR_WIDTH)
    end

    it 'draws no segments for zero but keeps the axis' do
      bar = chart_render.signed_bar(0, 500)
      expect(bar.delete(' ')).to eq(chart_render::BAR_AXIS)
    end

    it 'scales proportionally to the magnitude' do
      bar = chart_render.signed_bar(250, 500)
      _, right = bar.split(chart_render::BAR_AXIS, 2)
      expect(right.strip.length).to eq(chart_render::HALF_BAR_WIDTH / 2)
    end

    it 'clamps a magnitude larger than the maximum instead of overflowing' do
      bar = chart_render.signed_bar(-9999, 100)
      expect(bar.length).to eq(full_width)
      left, = bar.split(chart_render::BAR_AXIS, 2)
      expect(left.strip.length).to eq(chart_render::HALF_BAR_WIDTH)
    end

    it 'keeps every bar the same width so amounts align in a column' do
      widths = [-5000, -1, 0, 1, 5000].map { |a| chart_render.signed_bar(a, 5000).length }
      expect(widths.uniq).to eq([full_width])
    end

    it 'tolerates a zero maximum without dividing by zero' do
      expect { chart_render.signed_bar(0, 0) }.not_to raise_error
      expect(chart_render.signed_bar(0, 0).length).to eq(full_width)
    end
  end

  describe 'chart no-activity detection' do
    it 'reports no activity when every amount is zero' do
      result = chart_render.no_activity_message([[9, 0], [10, 0], [11, 0]])
      expect(result).to match(/No silver activity/)
    end

    # Previously `max_value.zero?` treated a zero maximum as an empty window even
    # though negative activity existed.
    it 'does not report no activity when the maximum is zero but withdrawals exist' do
      expect(chart_render.no_activity_message([[9, 0], [10, -500], [11, 0]])).to be_nil
    end

    it 'does not report no activity when every amount is negative' do
      expect(chart_render.no_activity_message([[9, -100], [10, -500]])).to be_nil
    end

    it 'does not report no activity for ordinary positive amounts' do
      expect(chart_render.no_activity_message([[9, 100], [10, 500]])).to be_nil
    end
  end
end
