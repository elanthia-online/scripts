require 'tmpdir'
require 'fileutils'
require 'ostruct'
require 'timeout'

# logxml.lic is a top-level script, not a module, so these examples run its
# real body (everything after the =end header) on a fresh object whose
# singleton methods stand in for the Lich script helpers. Nothing is defined
# at the top level, so other spec files keep their own helpers.
RSpec.describe 'logxml.lic timestamp settings' do
  let(:script_path) { File.expand_path('../../scripts/logxml.lic', __dir__) }
  let(:script_lines) { File.readlines(script_path) }
  # First line after the =end header, 1-based, so backtraces point at logxml.lic.
  let(:body_line) { script_lines.index { |l| l.start_with?('=end') } + 2 }
  let(:body) { script_lines.drop(body_line - 1).join }

  let(:log_dir) { Dir.mktmpdir }
  let(:frozen_time) { Time.new(2026, 4, 23, 10, 0, 5) }
  let(:echoes) { [] }
  let(:default_header) { '2026-04-23 10:00am' }
  let(:fallback_stamp) { frozen_time.strftime('%F %T %Z') }
  let(:started_echo) { "XML Logging started, currently logging to #{log_file}" }

  before do
    stub_const('LICH_DIR', log_dir)
    stub_const('XMLData', Module.new do
      def self.game = 'GSIV'
      def self.name = 'TestChar'
    end)
    allow(Time).to receive(:now).and_return(frozen_time)
    $login_time = frozen_time - 3600
  end

  after do
    FileUtils.rm_rf(log_dir)
  end

  # Runs logxml.lic once with +vars+ as typed and the given DR settings
  # (+nil+ for none, as in GS). Ends when the fed lines run out.
  def run_logxml(vars: [], settings: nil, lines: ['<output>You see a door.</output>'])
    script = OpenStruct.new(want_script_output: nil, vars: [vars.join(' '), *vars], downstream_buffer: [], name: 'logxml')
    stub_const('Script', Class.new { define_singleton_method(:current) { script } })
    pending_lines = lines.dup
    sink = echoes
    runner = Object.new
    runner.define_singleton_method(:hide_me) { nil }
    runner.define_singleton_method(:echo) { |msg| sink << msg.to_s }
    runner.define_singleton_method(:reget) { [] }
    runner.define_singleton_method(:get) { pending_lines.shift || raise(StopIteration) }
    runner.define_singleton_method(:upstream_get) { Thread.current.kill }
    runner.define_singleton_method(:get_settings) { settings } unless settings.nil?
    Timeout.timeout(5) { runner.instance_eval(body, script_path, body_line) }
  end

  def log_file
    Dir.glob(File.join(log_dir, '**', '*.xml')).first
  end

  def log_lines
    File.read(log_file).lines(chomp: true)
  end

  context 'when the yaml enables timestamps without a usable format' do
    { 'no format' => nil, 'an empty format' => '', 'a non-String format' => 5 }.each do |label, format|
      it "stamps with %F %T %Z and says so for #{label} (#{format.inspect})" do
        run_logxml(settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: format))

        expect(log_lines).to eq([fallback_stamp, "#{fallback_stamp}: <output>You see a door.</output>"])
        expect(echoes).to eq(
          [
            "log_timestamp is on in your settings, but log_timestamp_format #{format.inspect} is not a format; using \"%F %T %Z\".",
            started_echo
          ]
        )
      end
    end

    it 'uses a --timestamp=FMT without a message' do
      run_logxml(vars: ['--timestamp=%H:%M'], settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: nil))

      expect(log_lines).to eq(['10:00', '10:00: <output>You see a door.</output>'])
      expect(echoes).to eq([started_echo])
    end
  end

  it 'uses the yaml format when it is a format' do
    run_logxml(settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))

    expect(log_lines).to eq(['10:00', '10:00: <output>You see a door.</output>'])
    expect(echoes).to eq([started_echo])
  end

  it 'stays off when the yaml turns timestamps off, whatever the format' do
    run_logxml(settings: OpenStruct.new(log_timestamp: false, log_timestamp_format: nil))

    expect(log_lines).to eq([default_header, '<output>You see a door.</output>'])
    expect(echoes).to eq([started_echo])
  end

  context 'with an empty --timestamp=' do
    it 'logs without timestamps and says the option was ignored' do
      run_logxml(vars: ['--timestamp='])

      expect(log_lines).to eq([default_header, '<output>You see a door.</output>'])
      expect(echoes).to eq(
        [
          'timestamp was given without a format, so it is ignored; to add timestamps use --timestamp="%F %T %Z".',
          started_echo
        ]
      )
    end

    it 'treats --timestamp="" in vars[0] the same way' do
      run_logxml(vars: ['--timestamp=""'])

      expect(log_lines).to eq([default_header, '<output>You see a door.</output>'])
      expect(echoes.first).to start_with('timestamp was given without a format')
    end

    it 'keeps the yaml format when the yaml enables timestamps' do
      run_logxml(vars: ['--timestamp='], settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))

      expect(log_lines).to eq(['10:00', '10:00: <output>You see a door.</output>'])
    end
  end

  it 'keeps a comma in a quoted --timestamp format' do
    run_logxml(vars: ['--timestamp="%b %d, %H:%M"'])

    expect(log_lines).to eq(['Apr 23, 10:00', 'Apr 23, 10:00: <output>You see a door.</output>'])
  end
end
