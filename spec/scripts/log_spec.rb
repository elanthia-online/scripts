require 'tmpdir'
require 'fileutils'
require 'ostruct'
require 'timeout'

$login_time = Time.new(2026, 4, 23, 10, 0, 0)

module XMLData
  def self.game;       "GSIV";          end
  def self.name;       "TestChar";      end
  def self.room_id;    1234;            end
  def self.room_title; "[Town Square]"; end
end

module Lich
  def self.log(_msg); end
end

# Queue-backed stand-ins for lich-5's script I/O (lib/common/script.rb).
# `get` pops Script.current.downstream_buffer, the same buffer the logger's
# upstream thread pushes its ">command" lines into, and `upstream_get` pops
# the commands an example "typed". Both raise StopIteration once idle, which
# ends GameLogger.main's `loop` instead of blocking. With nothing fed, `get`
# raises at once, exactly like the old stub, so examples that only look at
# the header and reget run as before.
module LogSpecHarness
  DOWNSTREAM = Thread::Queue.new
  UPSTREAM = Thread::Queue.new

  class << self
    attr_accessor :idle_timeout
    attr_reader :echoes

    def reset!
      DOWNSTREAM.clear
      UPSTREAM.clear
      @echoes = []
      @idle_timeout = 0
    end

    def feed(*lines)
      lines.flatten.each { |line| DOWNSTREAM << line.dup }
    end

    def type(*commands)
      commands.flatten.each { |command| UPSTREAM << command.dup }
    end

    def get
      line = DOWNSTREAM.pop(timeout: idle_timeout)
      raise StopIteration if line.nil?

      line
    end

    def upstream_get
      UPSTREAM.pop(true)
    rescue ThreadError
      raise StopIteration
    end

    def echo(msg)
      @echoes << msg.to_s
    end
  end

  reset!
end

class Script
  def self.current
    @current ||= OpenStruct.new(
      want_script_output: nil,
      want_upstream: nil,
      vars: [""],
      downstream_buffer: LogSpecHarness::DOWNSTREAM,
      name: "log"
    )
  end
end

def hide_me; end
def echo(msg) = LogSpecHarness.echo(msg)

$reget_lines = []
def reget
  $reget_lines
end

def get = LogSpecHarness.get

def upstream_get = LogSpecHarness.upstream_get

script_path = File.join(__dir__, '..', '..', 'scripts', 'log.lic')
script_content = File.read(script_path)
module_code = script_content[/^module GameLogger.*?^end/m]
raise "Failed to extract GameLogger module from #{script_path}" if module_code.nil?
raise "Extracted code does not look like a single module" unless module_code.scan(/^module GameLogger/).one?

eval(module_code, binding, script_path,
     script_content.lines.index { |l| l.start_with?('module GameLogger') } + 1)

RSpec.describe GameLogger do
  # Other spec files may redefine the top-level echo/get helpers after this
  # file loads, so route GameLogger's own calls to the harness explicitly.
  before do
    LogSpecHarness.reset!
    allow(GameLogger).to receive(:echo) { |msg| LogSpecHarness.echo(msg) }
    allow(GameLogger).to receive(:get) { LogSpecHarness.get }
    allow(GameLogger).to receive(:upstream_get) { LogSpecHarness.upstream_get }
  end

  describe GameLogger::Opts do
    describe '.parse' do
      it 'parses --timestamp flag with value' do
        result = described_class.parse(['--timestamp=%F %T %Z'])
        expect(result.timestamp).to eq('%F %T %Z')
      end

      it 'parses --rnum as boolean flag' do
        result = described_class.parse(['--rnum'])
        expect(result.rnum).to be true
      end

      it 'parses --roomnum as boolean flag' do
        result = described_class.parse(['--roomnum'])
        expect(result.roomnum).to be true
      end

      it 'parses --exclude with comma-separated values' do
        result = described_class.parse(['--exclude=288,2300,u7199'])
        expect(result.exclude).to eq(%w[288 2300 u7199])
      end

      it 'parses --exclude with single value as string' do
        result = described_class.parse(['--exclude=288'])
        expect(result.exclude).to eq('288')
      end

      # parse_flag returns strings; main calls .to_i on the result
      it 'parses --lines as string (coerced later by caller)' do
        result = described_class.parse(['--lines=50000'])
        expect(result.lines).to eq('50000')
      end

      it 'returns nil for unset options' do
        result = described_class.parse([])
        expect(result.timestamp).to be_nil
        expect(result.rnum).to be_nil
        expect(result.exclude).to be_nil
      end

      it 'parses multiple flags together' do
        result = described_class.parse(['--timestamp=%F %T', '--rnum', '--lines=10000'])
        expect(result.timestamp).to eq('%F %T')
        expect(result.rnum).to be true
        expect(result.lines).to eq('10000')
      end

      it 'parses positional commands as true' do
        result = described_class.parse(['something'])
        expect(result.something).to be true
      end

      # R-04: --timestamp is a strftime format, taken exactly as typed
      context 'with a --timestamp format that holds a comma or an equals sign' do
        it 'keeps a comma inside the format instead of splitting it into a list' do
          result = described_class.parse(['--timestamp=%b %d, %Y %T'])

          expect(result.timestamp).to eq('%b %d, %Y %T')
        end

        it 'keeps a comma with no space after it' do
          result = described_class.parse(['--timestamp=%F,%T'])

          expect(result.timestamp).to eq('%F,%T')
        end

        it 'keeps everything after the first equals sign' do
          expect(described_class.parse(['--timestamp=%H=%M']).timestamp).to eq('%H=%M')
          expect(described_class.parse(['--timestamp=t=%T']).timestamp).to eq('t=%T')
        end
      end

      it 'stores an empty --timestamp= as an empty string' do
        expect(described_class.parse(['--timestamp=']).timestamp).to eq('')
      end

      context 'when a bare --timestamp or the word timestamp follows a format' do
        it 'keeps the format given by --timestamp=FMT' do
          expect(described_class.parse(['--timestamp=%F', '--timestamp']).timestamp).to eq('%F')
          expect(described_class.parse(['--timestamp=%F', 'timestamp']).timestamp).to eq('%F')
        end
      end

      it 'still splits --exclude on commas while keeping an equals sign in a value' do
        result = described_class.parse(['--exclude=288,u7199=x'])

        expect(result.exclude).to eq(%w[288 u7199=x])
      end

      # R-03: --lines is a single number, never a list
      it 'keeps --lines=50,000 as one string instead of a two-item list' do
        result = described_class.parse(['--lines=50,000'])

        expect(result.lines).to eq('50,000')
      end

      # R-09: the quote-aware rescan of vars[0] is load-bearing
      context 'when called with no args (reads Script.current.vars)' do
        it 'reads a quoted format from vars[0] on the autostart Array path' do
          # autostart.lic stores ["--timestamp=\"%F", "%T", "%Z\"", "--rnum"] and starts the
          # script with that Array: Lich joins it into vars[0] and splits vars[1..] on spaces.
          allow(Script.current).to receive(:vars).and_return(
            ['--timestamp="%F %T %Z" --rnum', '--timestamp="%F', '%T', '%Z"', '--rnum']
          )

          result = described_class.parse

          expect(result.timestamp).to eq('%F %T %Z')
          expect(result.rnum).to be true
          expect(result.to_h.keys).to contain_exactly(:timestamp, :rnum)
        end

        it 'keeps a comma in a quoted format on the autostart Array path' do
          allow(Script.current).to receive(:vars).and_return(
            ['--timestamp="%b %d, %Y %T" --rnum', '--timestamp="%b', '%d,', '%Y', '%T"', '--rnum']
          )

          result = described_class.parse

          expect(result.timestamp).to eq('%b %d, %Y %T')
          expect(result.rnum).to be true
        end

        it 'reads the same format when the command was typed (String path)' do
          allow(Script.current).to receive(:vars).and_return(
            ['--timestamp="%F %T %Z" --rnum', '--timestamp=%F %T %Z', '--rnum']
          )

          result = described_class.parse

          expect(result.timestamp).to eq('%F %T %Z')
          expect(result.rnum).to be true
        end

        it 'uses vars[1..] when vars[0] has no quotes' do
          allow(Script.current).to receive(:vars).and_return(['--rnum --lines=500', '--rnum', '--lines=500'])

          result = described_class.parse

          expect(result.to_h).to eq(rnum: true, lines: '500')
        end
      end
    end
  end

  # R-03
  describe '.lines_per_file' do
    it 'names 30000 as the default lines per file' do
      expect(GameLogger::DEFAULT_LINES_PER_FILE).to eq(30_000)
    end

    it 'uses the default without a message when --lines was not given' do
      expect(GameLogger.lines_per_file(nil)).to eq(30_000)
      expect(LogSpecHarness.echoes).to be_empty
    end

    {
      'plain digits'          => ['50000', 50_000],
      'comma separators'      => ['50,000', 50_000],
      'underscore separators' => ['50_000', 50_000],
      'a leading zero'        => ['010', 10],
      'one'                   => ['1', 1],
      'several comma groups'  => ['1,000,000', 1_000_000],
      'a short first group'   => ['1_000', 1_000]
    }.each do |label, (given, expected)|
      it "accepts #{label} (#{given.inspect}) without a message" do
        expect(GameLogger.lines_per_file(given)).to eq(expected)
        expect(LogSpecHarness.echoes).to be_empty
      end
    end

    {
      'zero'                              => '0',
      'a negative number'                 => '-5',
      'a word'                            => 'abc',
      'a number with a suffix'            => '50k',
      'a decimal'                         => '1.5',
      'a hex number'                      => '0x10',
      'a doubled separator'               => '50,,000',
      'an empty value'                    => '',
      'a separator between single digits' => '1,0',
      'a two-digit group'                 => '50,00',
      'a separator after every digit'     => '5,0,0,0',
      'a four-digit group'                => '1,0000',
      'a four-digit first group'          => '1234,000',
      'a trailing separator'              => '50_',
      'a leading separator'               => ',500',
      'a plus sign'                       => '+50',
      'surrounding spaces'                => ' 50 ',
      'non-ASCII digits'                  => [0x0665, 0x0660].pack('U*')
    }.each do |label, given|
      it "falls back to 30000 and names the bad value for #{label} (#{given.inspect})" do
        expect(GameLogger.lines_per_file(given)).to eq(30_000)

        expect(LogSpecHarness.echoes.size).to eq(1)
        expect(LogSpecHarness.echoes.first).to include("--lines=#{given} ").and include('30000')
      end
    end

    # true comes from a bare --lines or the positional word lines, so the
    # message names neither form.
    it 'falls back to 30000 and says the value is missing for a bare --lines or the word lines' do
      expect(GameLogger.lines_per_file(true)).to eq(30_000)

      expect(LogSpecHarness.echoes).to eq(
        ['lines was given without a value; use a whole number above 0, like --lines=50000. Using the default of 30000 lines per file.']
      )
    end
  end

  describe '.main' do
    let(:log_dir) { Dir.mktmpdir }
    let(:frozen_time) { Time.new(2026, 4, 23, 10, 0, 5) }

    before do
      stub_const('LICH_DIR', log_dir)
      allow(Time).to receive(:now).and_return(frozen_time)
      $login_time = Time.new(2026, 4, 23, 10, 0, 0)
    end

    after do
      FileUtils.rm_rf(log_dir)
    end

    # The timeout turns a logger that spins without reading a line into a
    # failure instead of a hung suite.
    def run_main
      Timeout.timeout(5) { GameLogger.main }
    end

    def find_log_file
      Dir.glob(File.join(log_dir, '**', '*.log')).first
    end

    def log_content
      File.read(find_log_file)
    end

    context 'with timestamps enabled' do
      before do
        GameLogger.instance_variable_set(:@options, OpenStruct.new(timestamp: '%F %T'))
      end

      it 'timestamps reget lines with $login_time' do
        $reget_lines = ['You see a door.', 'Obvious exits: north, south.']
        run_main
        expect(log_content).to include('2026-04-23 10:00:00: You see a door.')
        expect(log_content).to include('2026-04-23 10:00:00: Obvious exits: north, south.')
      end

      it 'filters pushStream tags from reget lines' do
        $reget_lines = ['<pushStream id="room"/>', 'You see a door.', '<popStream/>']
        run_main
        expect(log_content).not_to include('pushStream')
        expect(log_content).not_to include('popStream')
        expect(log_content).to include('2026-04-23 10:00:00: You see a door.')
      end

      it 'uses $login_time not current time for reget timestamps' do
        $login_time = Time.new(2026, 1, 1, 12, 30, 45)
        allow(Time).to receive(:now).and_return(Time.new(2026, 1, 1, 12, 30, 50))
        $reget_lines = ['Test line']
        run_main
        expect(log_content).to include('2026-01-01 12:30:45: Test line')
      end
    end

    context 'without timestamps' do
      before do
        GameLogger.instance_variable_set(:@options, OpenStruct.new)
      end

      it 'writes reget lines without timestamps' do
        $reget_lines = ['You see a door.']
        run_main
        door_line = log_content.lines.find { |l| l.include?('You see a door.') }
        expect(door_line).to start_with('You see a door.')
      end

      it 'still filters pushStream/popStream from reget' do
        $reget_lines = ['<pushStream id="room"/>', 'content line', '<popStream/>']
        run_main
        expect(log_content).not_to include('pushStream')
        expect(log_content).not_to include('popStream')
        expect(log_content).to include('content line')
      end
    end

    context 'when login was more than 30 seconds ago' do
      before do
        $login_time = frozen_time - 60
        GameLogger.instance_variable_set(:@options, OpenStruct.new(timestamp: '%F %T'))
      end

      it 'does not write reget lines' do
        $reget_lines = ['Should not appear']
        run_main
        expect(log_content).not_to include('Should not appear')
      end

      it 'does not write reget marker comment' do
        $reget_lines = ['ignored']
        run_main
        expect(log_content).not_to include('Above contents from reget')
      end
    end

    it 'writes reget marker comment when reget is used' do
      $login_time = frozen_time - 5
      $reget_lines = ['test']
      GameLogger.instance_variable_set(:@options, OpenStruct.new)
      run_main
      expect(log_content).to include('<!-- Above contents from reget; full logging now active -->')
    end

    it 'creates log directory with game and character name' do
      $reget_lines = []
      GameLogger.instance_variable_set(:@options, OpenStruct.new)
      run_main
      expect(find_log_file).to include('GSIV-TestChar')
    end

    it 'handles empty reget buffer' do
      $reget_lines = []
      GameLogger.instance_variable_set(:@options, OpenStruct.new(timestamp: '%F %T'))
      run_main
      expect(log_content).to include('<!-- Above contents from reget; full logging now active -->')
      expect(log_content.lines.count { |l| l.include?('2026-04-23 10:00:00:') }).to eq(0)
    end

    def log_lines
      log_content.lines.map(&:chomp)
    end

    let(:default_stamp) { frozen_time.strftime("%Y-%m-%d %H:%M:%S.%L %:z") }

    # R-04
    context 'with a --timestamp format that holds a comma' do
      it 'writes the header and each line with the whole format' do
        $reget_lines = []
        GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse(['--timestamp=%b %d, %Y %T']))
        LogSpecHarness.feed('You see a door.')

        run_main

        expect(log_lines).to eq(
          [
            'Apr 23, 2026 10:00:05',
            '<!-- Above contents from reget; full logging now active -->',
            'Apr 23, 2026 10:00:05: You see a door.'
          ]
        )
      end
    end

    context 'with a --timestamp format that holds an equals sign' do
      it 'prefixes each line with the whole format' do
        $reget_lines = []
        GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse(['--timestamp=%H=%M']))
        LogSpecHarness.feed('You see a door.')

        run_main

        expect(log_lines.last).to eq('10=00: You see a door.')
      end
    end

    let(:no_format_echo) do
      'timestamp was given without a format, so it is ignored; to add timestamps use --timestamp="%F %T %Z".'
    end

    # Defines GameLogger.get_settings (as Lich does for DR) for one run.
    def run_main_with_settings(settings)
      GameLogger.define_singleton_method(:get_settings) { settings }
      run_main
    ensure
      GameLogger.singleton_class.send(:remove_method, :get_settings)
    end

    context 'with a bare --timestamp, the word timestamp, or an empty --timestamp=' do
      [['--timestamp'], ['timestamp'], ['--timestamp=']].each do |args|
        it "logs without timestamps for #{args.first} and says the option was ignored" do
          $reget_lines = []
          GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse(args))
          LogSpecHarness.feed('You see a door.')

          run_main

          expect(log_lines).to eq(
            [
              default_stamp,
              '<!-- Above contents from reget; full logging now active -->',
              'You see a door.'
            ]
          )
          expect(LogSpecHarness.echoes).to eq(
            [no_format_echo, "Non-XML Logging started, currently logging to #{find_log_file}"]
          )
        end
      end

      it 'keeps the DR yaml timestamp format when the yaml enables timestamps' do
        $reget_lines = []
        GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse(['--timestamp']))
        LogSpecHarness.feed('You see a door.')

        run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))

        expect(log_lines).to eq(
          ['10:00', '<!-- Above contents from reget; full logging now active -->', '10:00: You see a door.']
        )
        expect(LogSpecHarness.echoes.first).to eq(no_format_echo)
      end
    end

    # R-04 through the settings path: the yaml format is checked like the
    # --timestamp one before it reaches strftime.
    context 'when the yaml enables timestamps without a usable format' do
      { 'no format' => nil, 'an empty format' => '', 'a non-String format' => 5 }.each do |label, format|
        it "stamps with %F %T %Z and says so for #{label} (#{format.inspect})" do
          $reget_lines = []
          GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse([]))
          LogSpecHarness.feed('You see a door.')

          run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: format))

          stamp = frozen_time.strftime('%F %T %Z')
          expect(log_lines).to eq(
            [stamp, '<!-- Above contents from reget; full logging now active -->', "#{stamp}: You see a door."]
          )
          expect(LogSpecHarness.echoes).to eq(
            [
              "log_timestamp is on in your settings, but log_timestamp_format #{format.inspect} is not a format; using \"%F %T %Z\".",
              "Non-XML Logging started, currently logging to #{find_log_file}"
            ]
          )
        end
      end

      it 'uses a --timestamp=FMT without a message' do
        $reget_lines = []
        GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse(['--timestamp=%H:%M']))
        LogSpecHarness.feed('You see a door.')

        run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: nil))

        expect(log_lines.last).to eq('10:00: You see a door.')
        expect(LogSpecHarness.echoes.size).to eq(1)
      end

      it 'logs without timestamps and without a message when the yaml leaves timestamps off' do
        $reget_lines = []
        GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse([]))
        LogSpecHarness.feed('You see a door.')

        run_main_with_settings(OpenStruct.new(log_timestamp: false, log_timestamp_format: nil))

        expect(log_lines.last).to eq('You see a door.')
        expect(LogSpecHarness.echoes.size).to eq(1)
      end
    end

    # R-03
    context 'with an invalid --lines value' do
      %w[0 -5 abc].each do |given|
        it "logs the game with 30000 lines per file for --lines=#{given} instead of spinning" do
          $reget_lines = []
          GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse(["--lines=#{given}"]))
          LogSpecHarness.feed('line 1', 'line 2')

          run_main

          expect(log_lines).to eq(
            [default_stamp, '<!-- Above contents from reget; full logging now active -->', 'line 1', 'line 2']
          )
          expect(LogSpecHarness.echoes.first).to start_with("--lines=#{given} is not a valid line count")
        end
      end

      [['--lines'], ['lines']].each do |args|
        it "logs the game for #{args.first} with no value instead of crashing at startup" do
          $reget_lines = []
          GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse(args))
          LogSpecHarness.feed('line 1')

          run_main

          expect(log_lines.last).to eq('line 1')
          expect(LogSpecHarness.echoes.first).to start_with('lines was given without a value;')
        end
      end
    end

    context 'with --lines=1,000' do
      it 'starts a new file after 1000 game lines' do
        $reget_lines = []
        GameLogger.instance_variable_set(:@options, GameLogger::Opts.parse(['--lines=1,000']))
        LogSpecHarness.feed((1..1001).map { |n| "line #{n}" })

        run_main

        # The clock is frozen, so the second file has the same name and the
        # rollover shows up as footer + header lines in one file.
        expect(log_lines[1001]).to eq('line 1000')
        expect(log_lines[1002]).to eq(default_stamp)
        expect(log_lines[1003]).to eq(default_stamp)
        expect(log_lines[1004]).to eq('line 1001')
        expect(log_lines.size).to eq(1005)
        expect(LogSpecHarness.echoes).to eq(["Non-XML Logging started, currently logging to #{find_log_file}"])
      end
    end

    context 'with a typed command' do
      it 'logs it as >command with the leading <c> removed' do
        $reget_lines = []
        GameLogger.instance_variable_set(:@options, OpenStruct.new)
        LogSpecHarness.idle_timeout = 0.5
        LogSpecHarness.type('<c>look')

        run_main

        expect(log_lines.last).to eq('>look')
      end
    end

    context 'log file header/footer format' do
      it 'uses --timestamp format for header when enabled' do
        $reget_lines = []
        GameLogger.instance_variable_set(:@options, OpenStruct.new(timestamp: '%F %T %Z'))
        run_main
        header_line = log_content.lines.first.chomp
        expect(header_line).to eq(frozen_time.strftime('%F %T %Z'))
      end

      it 'uses default format for header when timestamps disabled' do
        $reget_lines = []
        GameLogger.instance_variable_set(:@options, OpenStruct.new)
        run_main
        header_line = log_content.lines.first.chomp
        expect(header_line).to eq(frozen_time.strftime("%Y-%m-%d %H:%M:%S.%L %:z"))
      end
    end
  end
end
