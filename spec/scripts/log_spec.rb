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
  def self.room_count = 0
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

# lich-5's reget (global_defs.rb) answers nil, never [], when the buffer
# holds nothing, so an empty $reget_lines reads as nil here too.
$reget_lines = []
def reget
  $reget_lines.nil? || $reget_lines.empty? ? nil : $reget_lines
end

def get = LogSpecHarness.get

def upstream_get = LogSpecHarness.upstream_get

script_path = File.join(__dir__, '..', '..', 'scripts', 'log.lic')
script_content = File.read(script_path)
module_code = script_content[/^module GameLogger.*?^end/m]
raise "Failed to extract GameLogger module from #{script_path}" if module_code.nil?
raise "Extracted code does not look like a single module" unless module_code.scan(/^module GameLogger/).one?

module_line = script_content.lines.index { |l| l.start_with?('module GameLogger') } + 1

# Evaluates log.lic's `module GameLogger` body, as Lich does each time the
# script starts: every run of log.lic in a session evaluates the module again
# in the same namespace, while earlier runs may still be logging.
LogSpecHarness.define_singleton_method(:evaluate_game_logger) do
  eval(module_code, TOPLEVEL_BINDING, script_path, module_line)
end
LogSpecHarness.evaluate_game_logger

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

      it 'lets the last valued flag win when one is given twice' do
        expect(described_class.parse(['--timestamp=%T', '--timestamp=%H']).timestamp).to eq('%H')
        expect(described_class.parse(['--lines=100', '--lines=200']).lines).to eq('200')
      end

      context 'with a flag that has no name' do
        before do
          allow(described_class).to receive(:echo) { |msg| LogSpecHarness.echo(msg) }
        end

        it 'ignores -- and says so instead of crashing' do
          result = described_class.parse(['--', '--rnum'])

          expect(result.to_h).to eq(rnum: true)
          expect(LogSpecHarness.echoes).to eq(['-- has no option name, so it is ignored.'])
        end

        it 'ignores --=x and says so instead of storing an empty name' do
          result = described_class.parse(['--=x'])

          expect(result.to_h).to eq({})
          expect(LogSpecHarness.echoes).to eq(['--=x has no option name, so it is ignored.'])
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
      # Lich's LOG_DIR (lib/constants.rb) is hidden unless an example sets
      # it, so files land under LICH_DIR/logs whatever the suite loaded.
      hide_const('LOG_DIR')
      allow(Time).to receive(:now).and_return(frozen_time)
      $login_time = Time.new(2026, 4, 23, 10, 0, 0)
      # Examples that set reget lines would otherwise leave them for the
      # next example, whose file would start with them in random order.
      $reget_lines = []
    end

    after do
      FileUtils.rm_rf(log_dir)
    end

    # Sets the options the next run_main hands to GameLogger.main, as
    # GameLogger::Opts.parse would return them for the script's arguments.
    # Without it, main parses Script.current.vars itself.
    def use_options(options)
      @run_options = options
    end

    # Runs GameLogger.main with the options from use_options, if any.
    def start_main
      @run_options ? GameLogger.main(@run_options) : GameLogger.main
    end

    # The timeout turns a logger that spins without reading a line into a
    # failure instead of a hung suite.
    def run_main
      Timeout.timeout(5) { start_main }
    end

    def find_log_file
      Dir.glob(File.join(log_dir, '**', '*.log')).first
    end

    def log_content
      File.read(find_log_file)
    end

    context 'with timestamps enabled' do
      before do
        use_options(OpenStruct.new(timestamp: '%F %T'))
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
        use_options(OpenStruct.new)
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
        use_options(OpenStruct.new(timestamp: '%F %T'))
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
      use_options(OpenStruct.new)
      run_main
      expect(log_content).to include('<!-- Above contents from reget; full logging now active -->')
    end

    # R-24: Lich's --logs= sets LOG_DIR (lich.rbw), and pilepull.lic reads
    # these session logs from LOG_DIR.
    context 'with Lich started with --logs=' do
      let(:logs_dir) { Dir.mktmpdir }

      after { FileUtils.rm_rf(logs_dir) }

      it 'writes the log under LOG_DIR in the <game>-<name>/<year>/<month> layout' do
        stub_const('LOG_DIR', logs_dir)
        use_options(OpenStruct.new)

        run_main

        expect(Dir.glob(File.join(logs_dir, '**', '*.log'))).to eq(
          [File.join(logs_dir, 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.log')]
        )
        expect(Dir.glob(File.join(log_dir, '**', '*.log'))).to eq([])
      end
    end

    it 'writes under LICH_DIR/logs when LOG_DIR is not defined' do
      use_options(OpenStruct.new)

      run_main

      expect(find_log_file).to eq(File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.log'))
    end

    it 'writes under LICH_DIR/logs when LOG_DIR is empty' do
      stub_const('LOG_DIR', '')
      use_options(OpenStruct.new)

      run_main

      expect(find_log_file).to eq(File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.log'))
    end

    it 'creates log directory with game and character name' do
      $reget_lines = []
      use_options(OpenStruct.new)
      run_main
      expect(find_log_file).to include('GSIV-TestChar')
    end

    it 'handles empty reget buffer' do
      $reget_lines = []
      use_options(OpenStruct.new(timestamp: '%F %T'))
      run_main
      expect(log_content).to include('<!-- Above contents from reget; full logging now active -->')
      expect(log_content.lines.count { |l| l.include?('2026-04-23 10:00:00:') }).to eq(0)
    end

    # R-14: lich-5's reget returns nil when the buffer is empty. log.lic
    # only survived that in game through Lich's NilClass patch.
    it 'writes only the marker when reget returns nil (empty buffer)' do
      $reget_lines = nil
      use_options(OpenStruct.new)

      run_main

      expect(File.read(find_log_file).lines(chomp: true).first(2)).to eq(
        [frozen_time.strftime("%Y-%m-%d %H:%M:%S.%L %:z"), '<!-- Above contents from reget; full logging now active -->']
      )
    end

    # R-15: $_SERVERBUFFER_ keeps the server's CRLF line ends and reget
    # splits on "\n", so each reget line ends in "\r".
    context 'when the reget lines end in a carriage return' do
      it 'writes them without it, timestamps off' do
        $reget_lines = ["You see a door.\r", "Obvious exits: north.\r"]
        use_options(OpenStruct.new)

        run_main

        expect(File.binread(find_log_file)).not_to include("\r")
        expect(log_content.lines(chomp: true)[1, 2]).to eq(['You see a door.', 'Obvious exits: north.'])
      end

      it 'writes them without it, timestamps on' do
        $reget_lines = ["You see a door.\r"]
        use_options(OpenStruct.new(timestamp: '%F %T'))

        run_main

        expect(File.binread(find_log_file)).not_to include("\r")
        expect(log_content.lines(chomp: true)[1]).to eq('2026-04-23 10:00:00: You see a door.')
      end
    end

    def log_lines
      log_content.lines.map(&:chomp)
    end

    let(:default_stamp) { frozen_time.strftime("%Y-%m-%d %H:%M:%S.%L %:z") }

    # R-04
    context 'with a --timestamp format that holds a comma' do
      it 'writes the header and each line with the whole format' do
        $reget_lines = []
        use_options(GameLogger::Opts.parse(['--timestamp=%b %d, %Y %T']))
        LogSpecHarness.feed('You see a door.')

        run_main

        expect(log_lines).to eq(
          [
            'Apr 23, 2026 10:00:05',
            '<!-- Above contents from reget; full logging now active -->',
            'Apr 23, 2026 10:00:05: You see a door.',
            'Apr 23, 2026 10:00:05'
          ]
        )
      end
    end

    context 'with a --timestamp format that holds an equals sign' do
      it 'prefixes each line with the whole format' do
        $reget_lines = []
        use_options(GameLogger::Opts.parse(['--timestamp=%H=%M']))
        LogSpecHarness.feed('You see a door.')

        run_main

        expect(log_lines.last(2)).to eq(['10=00: You see a door.', '10=00'])
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
          use_options(GameLogger::Opts.parse(args))
          LogSpecHarness.feed('You see a door.')

          run_main

          expect(log_lines).to eq(
            [
              default_stamp,
              '<!-- Above contents from reget; full logging now active -->',
              'You see a door.',
              default_stamp
            ]
          )
          expect(LogSpecHarness.echoes).to eq(
            [no_format_echo, "Non-XML Logging started, currently logging to #{find_log_file}"]
          )
        end
      end

      it 'keeps the DR yaml timestamp format when the yaml enables timestamps' do
        $reget_lines = []
        use_options(GameLogger::Opts.parse(['--timestamp']))
        LogSpecHarness.feed('You see a door.')

        run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))

        expect(log_lines).to eq(
          ['10:00', '<!-- Above contents from reget; full logging now active -->', '10:00: You see a door.', '10:00']
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
          use_options(GameLogger::Opts.parse([]))
          LogSpecHarness.feed('You see a door.')

          run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: format))

          stamp = frozen_time.strftime('%F %T %Z')
          expect(log_lines).to eq(
            [stamp, '<!-- Above contents from reget; full logging now active -->', "#{stamp}: You see a door.", stamp]
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
        use_options(GameLogger::Opts.parse(['--timestamp=%H:%M']))
        LogSpecHarness.feed('You see a door.')

        run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: nil))

        expect(log_lines.last(2)).to eq(['10:00: You see a door.', '10:00'])
        expect(LogSpecHarness.echoes.size).to eq(1)
      end

      it 'logs without timestamps and without a message when the yaml leaves timestamps off' do
        $reget_lines = []
        use_options(GameLogger::Opts.parse([]))
        LogSpecHarness.feed('You see a door.')

        run_main_with_settings(OpenStruct.new(log_timestamp: false, log_timestamp_format: nil))

        expect(log_lines.last(2)).to eq(['You see a door.', default_stamp])
        expect(LogSpecHarness.echoes.size).to eq(1)
      end
    end

    # R-03
    context 'with an invalid --lines value' do
      %w[0 -5 abc].each do |given|
        it "logs the game with 30000 lines per file for --lines=#{given} instead of spinning" do
          $reget_lines = []
          use_options(GameLogger::Opts.parse(["--lines=#{given}"]))
          LogSpecHarness.feed('line 1', 'line 2')

          run_main

          expect(log_lines).to eq(
            [default_stamp, '<!-- Above contents from reget; full logging now active -->', 'line 1', 'line 2', default_stamp]
          )
          expect(LogSpecHarness.echoes.first).to start_with("--lines=#{given} is not a valid line count")
        end
      end

      [['--lines'], ['lines']].each do |args|
        it "logs the game for #{args.first} with no value instead of crashing at startup" do
          $reget_lines = []
          use_options(GameLogger::Opts.parse(args))
          LogSpecHarness.feed('line 1')

          run_main

          expect(log_lines.last(2)).to eq(['line 1', default_stamp])
          expect(LogSpecHarness.echoes.first).to start_with('lines was given without a value;')
        end
      end
    end

    context 'with --lines=1,000' do
      it 'starts a new file after 1000 game lines' do
        $reget_lines = []
        use_options(GameLogger::Opts.parse(['--lines=1,000']))
        LogSpecHarness.feed((1..1001).map { |n| "line #{n}" })

        run_main

        # R-25: the clock is frozen, so the second file starts within the
        # same second and gets an _01 suffix instead of being appended to the
        # first one.
        month = File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04')
        first = File.read(File.join(month, '2026-04-23_10-00-05.log')).lines(chomp: true)
        second = File.read(File.join(month, '2026-04-23_10-00-05_01.log')).lines(chomp: true)
        expect(first.size).to eq(1003)
        expect(first.last(2)).to eq(['line 1000', default_stamp])
        expect(second).to eq([default_stamp, 'line 1001', default_stamp])
        expect(LogSpecHarness.echoes).to eq(
          ["Non-XML Logging started, currently logging to #{File.join(month, '2026-04-23_10-00-05.log')}"]
        )
      end
    end

    context 'with a typed command' do
      it 'logs it as >command with the leading <c> removed' do
        $reget_lines = []
        use_options(OpenStruct.new)
        LogSpecHarness.idle_timeout = 0.5
        LogSpecHarness.type('<c>look')

        run_main

        expect(log_lines.last(2)).to eq(['>look', default_stamp])
      end
    end

    # R-05, R-07, R-18, R-19, R-34: --rnum and --exclude take the room from
    # XMLData and the map's UID table only (Q-13 A), never from
    # Room.current or Map.current, which can send LOCATION/PEER from the
    # logger and rescan the whole map on every line.
    describe 'room lookups for --rnum and --exclude' do
      # The parser's room as the logger sees it when it reads a line. A Hash
      # fed between lines moves the parser to another room (see the get stub).
      let(:room) { { game: 'GSIV', count: 1, uid: 4_216_015, title: '[Sanctum of Scales, Columns]' } }
      # UID => Lich ids, as Map.ids_from_uid answers from the map's UID table.
      let(:uid_table) { {} }
      # Strict doubles: any call other than Map.ids_from_uid and Map.loaded?
      # (the map is loaded unless an example says otherwise) fails the example.
      let(:map) { double('Map') }
      let(:room_class) { double('Room') }

      before do
        $reget_lines = []
        stub_const('Map', map)
        stub_const('Room', room_class)
        allow(map).to receive(:ids_from_uid) { |uid| uid_table.fetch(uid, []) }
        allow(map).to receive(:loaded?).and_return(true)
        allow(XMLData).to receive(:game) { room[:game] }
        allow(XMLData).to receive(:room_count) { room[:count] }
        allow(XMLData).to receive(:room_id) { room[:uid] }
        allow(XMLData).to receive(:room_title) { room[:title] }
        allow(GameLogger).to receive(:get) do
          item = LogSpecHarness.get
          while item.is_a?(Hash)
            room.merge!(item)
            item = LogSpecHarness.get
          end
          item
        end
      end

      # Runs the logger with these arguments and returns the logged game
      # lines (the header, the reget marker and the footer dropped; the
      # footer is checked here, as every file ends with one).
      def log_with(*args)
        use_options(GameLogger::Opts.parse(args))
        run_main
        expect(log_lines.last).to eq(default_stamp)
        log_lines[2..-2]
      end

      context 'with --rnum in GemStone' do
        it 'adds the Lich id from the UID table and the u-id to the room title only' do
          uid_table[4_216_015] = [228]
          LogSpecHarness.feed('[Sanctum of Scales, Columns]', 'You also see a door.')

          expect(log_with('--rnum')).to eq(
            ['[Sanctum of Scales, Columns - 228] (u4216015)', 'You also see a door.']
          )
        end

        it 'keeps the game-shown (4216015) instead of adding a second u-id' do
          uid_table[4_216_015] = [228]
          LogSpecHarness.feed('[Sanctum of Scales, Columns] (4216015)')

          expect(log_with('--rnum')).to eq(['[Sanctum of Scales, Columns - 228] (4216015)'])
        end

        it "writes no ' - ]' when the UID is not in the map, only the u-id" do
          LogSpecHarness.feed('[Sanctum of Scales, Columns]', '[Sanctum of Scales, Columns] (4216015)')

          expect(log_with('--rnum')).to eq(
            ['[Sanctum of Scales, Columns] (u4216015)', '[Sanctum of Scales, Columns] (4216015)']
          )
        end

        it 'adds no Lich id when the UID maps to more than one room' do
          uid_table[4_216_015] = [228, 229]
          LogSpecHarness.feed('[Sanctum of Scales, Columns]')

          expect(log_with('--rnum')).to eq(['[Sanctum of Scales, Columns] (u4216015)'])
        end

        it 'leaves every line alone while the parser has no room title yet' do
          room[:title] = ''
          LogSpecHarness.feed('[Gabriel] says, "hi [there]"', 'You also see a door.')

          expect(log_with('--rnum')).to eq(['[Gabriel] says, "hi [there]"', 'You also see a door.'])
        end

        # GS main_subtitle builds "[" + subtitle[3..-1] + "]", so a " - "
        # subtitle leaves the title as "[]".
        it 'leaves every line alone when the room title is an empty []' do
          room[:title] = '[]'
          LogSpecHarness.feed('[] says nothing', 'You also see a door.')

          expect(log_with('--rnum')).to eq(['[] says nothing', 'You also see a door.'])
        end

        it 'leaves a line that shows the room title after its start' do
          uid_table[4_216_015] = [228]
          LogSpecHarness.feed('Gabriel says, "Meet me at [Sanctum of Scales, Columns]."')

          expect(log_with('--rnum')).to eq(['Gabriel says, "Meet me at [Sanctum of Scales, Columns]."'])
        end

        # A UTF-8 room title with a non-ASCII letter made a UTF-8 pattern,
        # which raised Encoding::CompatibilityError on any binary
        # (ASCII-8BIT) line with high bytes and ended the logger. The
        # non-ASCII data is built at runtime (Custom/AsciiOnlySource).
        context 'when the room title has letters outside ASCII' do
          let(:e_acute) { [0xe9].pack('U') }
          let(:title) { "[Caf#{e_acute} Row]" }
          let(:high_byte_line) { "some #{[0xff].pack('C')} text".b }

          before { room[:title] = title }

          it 'numbers a binary title line and logs other binary lines with high bytes unchanged' do
            uid_table[4_216_015] = [228]
            LogSpecHarness.feed(title.b, high_byte_line, 'You also see a door.')

            expect(log_with('--rnum').map(&:b)).to eq(
              ["[Caf#{e_acute} Row - 228] (u4216015)".b, high_byte_line, 'You also see a door.'.b]
            )
          end

          it 'numbers a UTF-8 title line too' do
            uid_table[4_216_015] = [228]
            LogSpecHarness.feed("#{title} (4216015)")

            expect(log_with('--rnum')).to eq(["[Caf#{e_acute} Row - 228] (4216015)"])
          end
        end

        it 'builds the title matcher once per room, not once per line' do
          allow(GameLogger).to receive(:room_title_pattern).and_call_original
          LogSpecHarness.feed(
            '[Sanctum of Scales, Columns]', 'line 1', 'line 2',
            { count: 2, uid: 4_216_016, title: '[Sanctum of Scales, Pool]' },
            '[Sanctum of Scales, Pool]', 'line 3'
          )

          expect(log_with('--rnum')).to eq(
            [
              '[Sanctum of Scales, Columns] (u4216015)', 'line 1', 'line 2',
              '[Sanctum of Scales, Pool] (u4216016)', 'line 3'
            ]
          )
          expect(GameLogger).to have_received(:room_title_pattern).twice
        end
      end

      context 'with --rnum in DragonRealms' do
        # lich-5 wraps the subtitle's bracketed title in one more pair of
        # brackets, so XMLData.room_title is [[...]] while the game line
        # shows [...] (proofs/verify/dr_rnum.out).
        before do
          room.merge!(game: 'DR', uid: 230_008, title: "[[Bosque Deriel, Hermit's Shacks]]")
        end

        it 'adds the Lich id to the room title line and no u-id' do
          uid_table[230_008] = [12_345]
          LogSpecHarness.feed("[Bosque Deriel, Hermit's Shacks] (230008)", 'Obvious paths: north.')

          expect(log_with('--rnum')).to eq(
            ["[Bosque Deriel, Hermit's Shacks - 12345] (230008)", 'Obvious paths: north.']
          )
        end

        it 'adds the Lich id when the game does not show the room id' do
          uid_table[230_008] = [12_345]
          LogSpecHarness.feed("[Bosque Deriel, Hermit's Shacks]")

          expect(log_with('--roomnum')).to eq(["[Bosque Deriel, Hermit's Shacks - 12345]"])
        end

        it 'leaves the title alone when the UID is not in the map' do
          LogSpecHarness.feed("[Bosque Deriel, Hermit's Shacks] (230008)")

          expect(log_with('--rnum')).to eq(["[Bosque Deriel, Hermit's Shacks] (230008)"])
        end
      end

      context 'when looking up the room' do
        it 'never calls Room.current or Map.current and asks the UID table once per room' do
          uid_table.merge!(4_216_015 => [228], 4_216_016 => [229])
          LogSpecHarness.feed(
            '[Sanctum of Scales, Columns]', 'line 1', 'line 2',
            { count: 2, uid: 4_216_016, title: '[Sanctum of Scales, Pool]' },
            '[Sanctum of Scales, Pool]', 'line 3',
            { count: 3, uid: 4_216_015, title: '[Sanctum of Scales, Columns]' },
            'line 4'
          )
          expect(room_class).not_to receive(:current)
          expect(map).not_to receive(:current)

          lines = log_with('--rnum', '--exclude=999')

          expect(lines).to eq(
            [
              '[Sanctum of Scales, Columns - 228] (u4216015)', 'line 1', 'line 2',
              '[Sanctum of Scales, Pool - 229] (u4216016)', 'line 3', 'line 4'
            ]
          )
          expect(map).to have_received(:ids_from_uid).with(4_216_015).twice
          expect(map).to have_received(:ids_from_uid).with(4_216_016).once
        end

        it 'looks the room up again when the UID changes within one room count' do
          uid_table.merge!(4_216_015 => [228], 4_216_016 => [229])
          LogSpecHarness.feed(
            '[Sanctum of Scales, Columns]',
            { uid: 4_216_016 },
            '[Sanctum of Scales, Columns]'
          )

          expect(log_with('--rnum')).to eq(
            ['[Sanctum of Scales, Columns - 228] (u4216015)', '[Sanctum of Scales, Columns - 229] (u4216016)']
          )
        end

        it 'rebuilds the title matcher when the title changes within one room count' do
          LogSpecHarness.feed(
            '[Sanctum of Scales, Columns]',
            { title: '[Sanctum of Scales, Pool]' },
            '[Sanctum of Scales, Pool]'
          )

          expect(log_with('--rnum')).to eq(
            ['[Sanctum of Scales, Columns] (u4216015)', '[Sanctum of Scales, Pool] (u4216015)']
          )
        end

        # Map.ids_from_uid never loads the map: until the map is loaded (by
        # the logger's own load, see below, or by anything else) or learns
        # the UID, the table answers [] for every room.
        context 'when the map learns the UID while the logger is in the room' do
          before do
            answers = [[], [288]]
            allow(map).to receive(:ids_from_uid) { answers.size > 1 ? answers.shift : answers.first }
          end

          it 'starts skipping an excluded room once the map has its UID' do
            LogSpecHarness.feed('first line at login', 'second line', 'third line')

            expect(log_with('--exclude=288')).to eq(['first line at login'])
          end

          it 'numbers the room title once the map has its UID' do
            LogSpecHarness.feed('[Sanctum of Scales, Columns]', '[Sanctum of Scales, Columns]')

            expect(log_with('--rnum')).to eq(
              ['[Sanctum of Scales, Columns] (u4216015)', '[Sanctum of Scales, Columns - 288] (u4216015)']
            )
          end

          it 'stops asking the map once it has answered with the Lich id' do
            LogSpecHarness.feed('line 1', 'line 2', 'line 3', 'line 4')

            expect(log_with('--rnum')).to eq(['line 1', 'line 2', 'line 3', 'line 4'])
            expect(map).to have_received(:ids_from_uid).twice
          end
        end

        it 'does not look up the Lich id when only u-ids are excluded and --rnum is off' do
          LogSpecHarness.feed('line 1', { count: 2, uid: 4_216_016 }, 'line 2')

          expect(log_with('--exclude=u7199')).to eq(['line 1', 'line 2'])
          expect(map).not_to have_received(:ids_from_uid)
        end
      end

      # A-1: Lich loads the map only when something asks for it (in DR its
      # own room display does not by default), so with a Lich number to find
      # the logger loads it once, in a thread of its own.
      context 'when nothing has loaded the map' do
        let(:loaders) { [] }

        before do
          allow(map).to receive(:loaded?).and_return(false)
          allow(map).to receive(:load).and_return(true)
          allow(GameLogger).to receive(:start_map_load).and_wrap_original do |original|
            original.call.tap { |loader| loaders << loader }
          end
        end

        after { loaders.compact.each { |loader| loader.join(2) } }

        def wait_for_loaders
          loaders.compact.each { |loader| expect(loader.join(2)).not_to be_nil }
        end

        { '--rnum' => ['--rnum'], 'a Lich id in --exclude' => ['--exclude=u7199,288'] }.each do |label, args|
          it "loads the map once, in its own thread, for #{label}" do
            LogSpecHarness.feed('line 1', { count: 2, uid: 4_216_016 }, 'line 2')

            expect(log_with(*args)).to eq(['line 1', 'line 2'])
            wait_for_loaders
            expect(GameLogger).to have_received(:start_map_load).once
            expect(loaders.first).to be_a(Thread)
            expect(map).to have_received(:load).once
          end
        end

        { 'no room options' => [], 'only u-ids in --exclude' => ['--exclude=u7199'],
          'a bare --exclude' => ['--exclude'] }.each do |label, args|
          it "does not load the map with #{label}" do
            LogSpecHarness.feed('line 1')

            expect(log_with(*args)).to eq(['line 1'])
            expect(GameLogger).not_to have_received(:start_map_load)
            expect(map).not_to have_received(:loaded?)
            expect(map).not_to have_received(:load)
          end
        end

        it 'does not load the map again when it is already loaded' do
          allow(map).to receive(:loaded?).and_return(true)
          LogSpecHarness.feed('line 1')

          expect(log_with('--rnum', '--exclude=288')).to eq(['line 1'])
          expect(loaders).to eq([nil])
          expect(map).not_to have_received(:load)
        end

        it 'keeps reading lines while the map loads, and excludes the room once it has' do
          gate = Thread::Queue.new
          allow(map).to receive(:load) do
            gate.pop
            uid_table[4_216_015] = [288]
            true
          end
          LogSpecHarness.feed('line 1', 'line 2')

          expect(log_with('--exclude=288')).to eq(['line 1', 'line 2'])
          expect(loaders.first).to be_alive

          gate << :loaded
          wait_for_loaders
          expect(GameLogger.lich_room_id(4_216_015)).to eq(288)
        end

        # The UID table is cleared and rebuilt one room at a time, so mid-load
        # a UID shared by two rooms can show only the first.
        it 'asks again for a Lich id found while the load is still running' do
          gate = Thread::Queue.new
          allow(map).to receive(:load) do
            gate.pop
            true
          end
          answers = [[228], [228, 229]]
          allow(map).to receive(:ids_from_uid) { answers.size > 1 ? answers.shift : answers.first }
          LogSpecHarness.feed('[Sanctum of Scales, Columns]', '[Sanctum of Scales, Columns]')

          expect(log_with('--rnum')).to eq(
            ['[Sanctum of Scales, Columns - 228] (u4216015)', '[Sanctum of Scales, Columns] (u4216015)']
          )
          expect(map).to have_received(:ids_from_uid).twice
          gate << :loaded
        end

        it 'says so when no map database can be loaded' do
          allow(map).to receive(:load).and_return(false)
          LogSpecHarness.feed('line 1')

          expect(log_with('--exclude=288')).to eq(['line 1'])
          wait_for_loaders
          expect(LogSpecHarness.echoes).to include(
            'no map database could be loaded, so Lich room numbers in --exclude and --rnum match no room; u<uid> entries still work.'
          )
        end

        it 'says so and keeps logging when the load raises' do
          allow(map).to receive(:load).and_raise(Errno::EACCES, 'map.json')
          LogSpecHarness.feed('line 1')

          expect(log_with('--rnum')).to eq(['line 1'])
          wait_for_loaders
          expect(LogSpecHarness.echoes).to include(
            'the map failed to load (Permission denied - map.json), so Lich room numbers in --exclude and --rnum match no room; u<uid> entries still work.'
          )
        end
      end

      context 'with --exclude' do
        it 'skips lines in a room excluded by u-id and logs the rest' do
          LogSpecHarness.feed('in the columns', { count: 2, uid: 4_216_016 }, 'in the pool')

          expect(log_with('--exclude=u4216015')).to eq(['in the pool'])
        end

        it 'skips lines in a room whose UID maps to an excluded Lich id' do
          uid_table.merge!(4_216_015 => [288], 4_216_016 => [300])
          LogSpecHarness.feed('in the columns', { count: 2, uid: 4_216_016 }, 'in the pool')

          expect(log_with('--exclude=288,2300')).to eq(['in the pool'])
        end

        it 'checks u-id entries first, without asking the UID table, when they match' do
          LogSpecHarness.feed('in the columns', 'still in the columns')

          expect(log_with('--exclude=u4216015,288')).to eq([])
          expect(map).not_to have_received(:ids_from_uid)
        end

        it 'logs a room whose UID is not in the map even when Lich ids are excluded' do
          LogSpecHarness.feed('in an unmapped room')

          expect(log_with('--exclude=288')).to eq(['in an unmapped room'])
        end

        it 'logs a room whose UID maps to more than one Lich id' do
          uid_table[4_216_015] = [288, 289]
          LogSpecHarness.feed('in a multi-id room')

          expect(log_with('--exclude=288')).to eq(['in a multi-id room'])
        end

        it 'ignores an empty entry (--exclude=,288) instead of excluding every unmapped room' do
          uid_table[4_216_016] = [288]
          LogSpecHarness.feed('in an unmapped room', { count: 2, uid: 4_216_016 }, 'in room 288')

          expect(log_with('--exclude=,288')).to eq(['in an unmapped room'])
        end

        it 'does not treat an empty entry as a Lich id to look up (--exclude=,u7199)' do
          LogSpecHarness.feed('line 1')

          expect(log_with('--exclude=,u7199')).to eq(['line 1'])
          expect(map).not_to have_received(:ids_from_uid)
        end

        it 'excludes nothing for a bare --exclude' do
          LogSpecHarness.feed('line 1')

          expect(log_with('--exclude')).to eq(['line 1'])
          expect(map).not_to have_received(:ids_from_uid)
        end

        it 'also skips commands typed in an excluded room' do
          LogSpecHarness.idle_timeout = 0.5
          LogSpecHarness.type('look')

          expect(log_with('--exclude=u4216015')).to eq([])
        end
      end
    end

    # R-13: the line was written before the date check, so the first line
    # after midnight went into yesterday's file; an --exclude `next`
    # skipped the date check; excluded lines used up the --lines budget.
    describe 'starting a new file' do
      let(:marker) { '<!-- Above contents from reget; full logging now active -->' }
      let(:next_day) { Time.new(2026, 4, 24, 0, 0, 1) }
      let(:next_day_stamp) { next_day.strftime('%Y-%m-%d %H:%M:%S.%L %:z') }
      # The parser's room as the logger sees it when it reads a line.
      let(:room) { { count: 1, uid: 1234 } }

      # A Time fed between lines moves the clock; a Hash moves the parser to
      # another room.
      before do
        clock = frozen_time
        allow(Time).to receive(:now) { clock }
        allow(XMLData).to receive(:room_count) { room[:count] }
        allow(XMLData).to receive(:room_id) { room[:uid] }
        allow(GameLogger).to receive(:get) do
          item = LogSpecHarness.get
          until item.is_a?(String)
            item.is_a?(Time) ? clock = item : room.merge!(item)
            item = LogSpecHarness.get
          end
          item
        end
      end

      # Every log file's lines, by path relative to the character folder.
      def log_files
        root = File.join(log_dir, 'logs', 'GSIV-TestChar')
        Dir.glob(File.join(root, '**', '*.log')).to_h do |path|
          [path.delete_prefix("#{root}/"), File.read(path).lines(chomp: true)]
        end
      end

      it "logs the first line after midnight in the new day's file" do
        use_options(OpenStruct.new)
        LogSpecHarness.feed('line 1', next_day, 'line 2')

        run_main

        expect(log_files).to eq(
          '2026/04/2026-04-23_10-00-05.log' => [default_stamp, marker, 'line 1', next_day_stamp],
          '2026/04/2026-04-24_00-00-01.log' => [next_day_stamp, 'line 2', next_day_stamp]
        )
      end

      it 'starts the new file on the first line after midnight even in an excluded room' do
        use_options(GameLogger::Opts.parse(['--exclude=u7199']))
        LogSpecHarness.feed('line 1', { count: 2, uid: 7199 }, next_day, 'excluded line')

        run_main

        expect(log_files).to eq(
          '2026/04/2026-04-23_10-00-05.log' => [default_stamp, marker, 'line 1', next_day_stamp],
          '2026/04/2026-04-24_00-00-01.log' => [next_day_stamp, next_day_stamp]
        )
      end

      it "logs the first line after leaving an excluded room past midnight in the new day's file" do
        use_options(GameLogger::Opts.parse(['--exclude=u7199']))
        LogSpecHarness.feed(
          'line 1', { count: 2, uid: 7199 }, 'excluded 1', next_day, 'excluded 2', { count: 3, uid: 1234 }, 'line 2'
        )

        run_main

        expect(log_files['2026/04/2026-04-24_00-00-01.log']).to eq([next_day_stamp, 'line 2', next_day_stamp])
        expect(log_files['2026/04/2026-04-23_10-00-05.log']).to eq([default_stamp, marker, 'line 1', next_day_stamp])
      end

      # The clock stays at 10:00:05, so the second file gets an _01 suffix.
      it 'counts only written lines toward --lines, not lines in an excluded room' do
        use_options(GameLogger::Opts.parse(['--lines=2', '--exclude=u7199']))
        LogSpecHarness.feed('a', { count: 2, uid: 7199 }, 'x1', 'x2', 'x3', { count: 3, uid: 1234 }, 'b', 'c')

        run_main

        expect(log_files).to eq(
          '2026/04/2026-04-23_10-00-05.log'    => [default_stamp, marker, 'a', 'b', default_stamp],
          '2026/04/2026-04-23_10-00-05_01.log' => [default_stamp, 'c', default_stamp]
        )
      end

      it 'counts only written lines toward --lines, not filtered stream lines' do
        use_options(GameLogger::Opts.parse(['--lines=2']))
        LogSpecHarness.feed('a', '<pushStream id="inv"/>', '<popStream/>', 'b', 'c')

        run_main

        expect(log_files).to eq(
          '2026/04/2026-04-23_10-00-05.log'    => [default_stamp, marker, 'a', 'b', default_stamp],
          '2026/04/2026-04-23_10-00-05_01.log' => [default_stamp, 'c', default_stamp]
        )
      end

      # R-25: a rotation within one second appended to the same file.
      it 'gives each file started within the same second its own _NN name' do
        use_options(GameLogger::Opts.parse(['--lines=1']))
        LogSpecHarness.feed('a', 'b', 'c')

        run_main

        expect(log_files).to eq(
          '2026/04/2026-04-23_10-00-05.log'    => [default_stamp, marker, 'a', default_stamp],
          '2026/04/2026-04-23_10-00-05_01.log' => [default_stamp, 'b', default_stamp],
          # no _03: the file after a full one opens only when its first
          # line comes, and here the logger stops first
          '2026/04/2026-04-23_10-00-05_02.log' => [default_stamp, 'c', default_stamp]
        )
      end

      # A file opened at once after a --lines rotation waited for a line; when
      # the first one came after midnight it went to the new day's file and
      # the waiting file kept only its header and footer, under the old day.
      it 'opens the file after a --lines rotation only when its first line comes, also past midnight' do
        use_options(GameLogger::Opts.parse(['--lines=1']))
        LogSpecHarness.feed('a', next_day, 'b')

        run_main

        expect(log_files).to eq(
          '2026/04/2026-04-23_10-00-05.log' => [default_stamp, marker, 'a', default_stamp],
          '2026/04/2026-04-24_00-00-01.log' => [next_day_stamp, 'b', next_day_stamp]
        )
      end

      it 'appends to an existing file of the same name when the logger starts' do
        month = File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04')
        FileUtils.mkdir_p(month)
        File.write(File.join(month, '2026-04-23_10-00-05.log'), "earlier run\n")
        use_options(OpenStruct.new)
        LogSpecHarness.feed('a')

        run_main

        expect(log_files).to eq(
          '2026/04/2026-04-23_10-00-05.log' => ['earlier run', default_stamp, marker, 'a', default_stamp]
        )
      end
    end

    # R-23: the footer was written only when a new file started, so a file
    # closed by ;kill, logout or Lich exiting (most files) had none.
    context 'when the logger stops' do
      let(:marker) { '<!-- Above contents from reget; full logging now active -->' }

      # Records every File the logger opens.
      def opened_files
        @opened_files ||= [].tap do |opened|
          allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
            original.call(*args, &block).tap { |file| opened << file if file.is_a?(File) }
          end
        end
      end

      it 'ends the file with the footer once, after the last line' do
        use_options(OpenStruct.new)
        LogSpecHarness.feed('line 1')

        run_main

        expect(log_lines).to eq([default_stamp, marker, 'line 1', default_stamp])
      end

      it 'stamps the footer with the --timestamp format' do
        use_options(OpenStruct.new(timestamp: '%H:%M'))
        LogSpecHarness.feed('line 1')

        run_main

        expect(log_lines).to eq(['10:00', marker, '10:00: line 1', '10:00'])
      end

      # lich-5 stops a script by Thread#kill on its threads (script.rb kill).
      it 'writes the footer when the thread is killed, as ;kill log does' do
        use_options(OpenStruct.new)
        LogSpecHarness.idle_timeout = 5
        LogSpecHarness.feed('line 1')
        logger = Thread.new { start_main }
        Timeout.timeout(2) { sleep 0.01 until find_log_file && File.read(find_log_file).include?("line 1\n") }

        logger.kill
        logger.join(2)

        expect(log_lines).to eq([default_stamp, marker, 'line 1', default_stamp])
      end

      it 'closes the file, logs the failed footer and lets the reason through when the footer cannot be written' do
        use_options(OpenStruct.new)
        allow(Lich).to receive(:log)
        files = opened_files
        allow(GameLogger).to receive(:get) do
          allow(files.first).to receive(:puts).and_raise(Errno::ENOSPC)
          raise StopIteration
        end

        expect { run_main }.not_to raise_error

        expect(files.size).to eq(1)
        expect(files.first).to be_closed
        expect(log_lines).to eq([default_stamp, marker])
        expect(Lich).to have_received(:log).with(
          "log: the footer of #{find_log_file} was not written while the logger stopped (Errno::ENOSPC: No space left on device)"
        )
      end

      # A footer that fails when a full file is closed for the next one is
      # not part of stopping: it raises, as the plain puts before 1.2.4 did,
      # instead of being dropped while the logger moves on.
      it 'closes the file and raises when the footer of a full file cannot be written' do
        use_options(GameLogger::Opts.parse(['--lines=1']))
        allow(Lich).to receive(:log)
        files = opened_files
        LogSpecHarness.feed('a', 'b')
        # The first write after "a" on the first file is its footer.
        a_written = false
        allow(GameLogger).to receive(:get).and_wrap_original do |original|
          original.call.tap do |line|
            next unless line == 'a'

            allow(files.first).to receive(:puts).and_wrap_original do |puts, *args|
              raise Errno::EIO if a_written

              a_written = true
              puts.call(*args)
            end
          end
        end

        expect { run_main }.to raise_error(Errno::EIO)

        expect(files.size).to eq(1)
        expect(files.first).to be_closed
        expect(log_lines).to eq([default_stamp, marker, 'a'])
        expect(Lich).not_to have_received(:log)
      end
    end

    # R-22: the header was written before the begin/ensure that closes the
    # file, so an error there left the File open.
    context 'when the header cannot be written' do
      it 'closes the file without a footer and raises the error' do
        use_options(OpenStruct.new)
        opened = []
        header_failed = false
        allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
          original.call(*args, &block).tap do |file|
            next unless file.is_a?(File)

            # Only the first write (the header) fails, so a footer would land.
            allow(file).to receive(:puts).and_wrap_original do |puts, *lines|
              unless header_failed
                header_failed = true
                raise Errno::ENOSPC
              end
              puts.call(*lines)
            end
            opened << file
          end
        end

        expect { run_main }.to raise_error(Errno::ENOSPC)

        expect(opened.size).to eq(1)
        expect(opened.first).to be_closed
        expect(File.read(find_log_file)).to eq('')
      end
    end

    # R-08: the module body parsed the arguments into a module instance
    # variable, and every run of log.lic in a session (;force log, a second
    # logxml shim run) evaluates `module GameLogger` again in the same
    # namespace, so a run starting later could hand its options to a run
    # already going.
    context 'when another run evaluates the module' do
      let(:marker) { '<!-- Above contents from reget; full logging now active -->' }

      # The script's arguments as lich-5 gives them: vars[0] the whole line,
      # then one word each.
      def start_script_with(*args)
        allow(Script.current).to receive(:vars).and_return([args.join(' '), *args])
      end

      it 'reads no arguments and keeps no options on the module' do
        start_script_with('--rnum', '--exclude=u7199')

        LogSpecHarness.evaluate_game_logger

        expect(Script.current).not_to have_received(:vars)
        expect(GameLogger.instance_variables).to be_empty
      end

      # Lich runs each script on its own thread, so another run can evaluate
      # the module at any point of this one, here while it reads its settings.
      it "keeps this run's arguments when another run evaluates the module while this one starts" do
        start_script_with('--exclude=u1234', '--timestamp=%H:%M')
        LogSpecHarness.evaluate_game_logger
        another_run = lambda do
          start_script_with('--lines=5')
          LogSpecHarness.evaluate_game_logger
        end
        GameLogger.define_singleton_method(:get_settings) do
          another_run.call
          OpenStruct.new
        end
        LogSpecHarness.feed('a line in room 1234')

        begin
          run_main
        ensure
          GameLogger.singleton_class.send(:remove_method, :get_settings)
        end

        expect(log_lines).to eq(['10:00', marker, '10:00'])
      end

      # The second run is started on the example's thread, with its own log
      # folder, and reads no line; the first keeps logging on its thread.
      it "keeps this run's --exclude when another run starts after this one started" do
        example_thread = Thread.current
        room_uid = 1234
        reads = 0
        allow(XMLData).to receive(:room_id) { room_uid }
        allow(GameLogger).to receive(:get) do
          raise StopIteration if Thread.current == example_thread

          reads += 1
          item = LogSpecHarness.get
          while item.is_a?(Hash)
            room_uid = item[:uid]
            item = LogSpecHarness.get
          end
          item
        end
        start_script_with('--exclude=u7199')
        LogSpecHarness.evaluate_game_logger
        LogSpecHarness.idle_timeout = 5
        LogSpecHarness.feed('line 1')
        logger = Thread.new { start_main }
        begin
          Timeout.timeout(2) { sleep 0.01 until find_log_file && File.read(find_log_file).include?("line 1\n") }
          first_file = find_log_file

          stub_const('LOG_DIR', File.join(log_dir, 'second run'))
          start_script_with('--exclude=u1234')
          LogSpecHarness.evaluate_game_logger
          run_main
          LogSpecHarness.feed({ uid: 7199 }, 'a line in room 7199', { uid: 1234 }, 'line 3')
          # The fourth read waits for a line, so "line 3" is done with.
          Timeout.timeout(2) { sleep 0.01 until reads == 4 }
        ensure
          logger.kill
          logger.join(2)
        end

        expect(File.read(first_file).lines(chomp: true)).to eq([default_stamp, marker, 'line 1', 'line 3', default_stamp])
      end
    end

    describe '.log_file_path' do
      let(:time) { Time.new(2026, 4, 23, 10, 0, 5) }

      it 'names the first file of a run by the time, even when that file exists' do
        File.write(File.join(log_dir, '2026-04-23_10-00-05.log'), '')

        expect(GameLogger.log_file_path(log_dir, time, '.log', rotated: false))
          .to eq(File.join(log_dir, '2026-04-23_10-00-05.log'))
      end

      it 'names a rotated file by the time when no file has that name' do
        expect(GameLogger.log_file_path(log_dir, time, '.xml', rotated: true))
          .to eq(File.join(log_dir, '2026-04-23_10-00-05.xml'))
      end

      it 'adds _01 to a rotated file whose name exists, and _02 when that exists too' do
        File.write(File.join(log_dir, '2026-04-23_10-00-05.log'), '')
        expect(GameLogger.log_file_path(log_dir, time, '.log', rotated: true))
          .to eq(File.join(log_dir, '2026-04-23_10-00-05_01.log'))

        File.write(File.join(log_dir, '2026-04-23_10-00-05_01.log'), '')
        expect(GameLogger.log_file_path(log_dir, time, '.log', rotated: true))
          .to eq(File.join(log_dir, '2026-04-23_10-00-05_02.log'))
      end

      it 'gives rotated names that sort by name in the order written, after the first file and before the next second' do
        names = ['2026-04-23_10-00-05.log']
        11.times do
          FileUtils.touch(File.join(log_dir, names.last))
          names << File.basename(GameLogger.log_file_path(log_dir, time, '.log', rotated: true))
        end
        names << '2026-04-23_10-00-06.log'

        expect(names.sort).to eq(names)
      end
    end

    describe '.write_footer' do
      let(:closed_file) { File.open(File.join(log_dir, 'closed.log'), 'a').tap(&:close) }

      it 'logs and ignores a write error while the logger stops' do
        allow(Lich).to receive(:log)

        expect(GameLogger.write_footer(closed_file, nil, stopping: true)).to be_nil
        expect(Lich).to have_received(:log).with(
          "log: the footer of #{closed_file.path} was not written while the logger stopped (IOError: closed stream)"
        )
      end

      it 'raises a write error when the logger is not stopping' do
        expect { GameLogger.write_footer(closed_file, nil, stopping: false) }.to raise_error(IOError)
      end
    end

    context 'log file header/footer format' do
      it 'uses --timestamp format for header when enabled' do
        $reget_lines = []
        use_options(OpenStruct.new(timestamp: '%F %T %Z'))
        run_main
        header_line = log_content.lines.first.chomp
        expect(header_line).to eq(frozen_time.strftime('%F %T %Z'))
      end

      it 'uses default format for header when timestamps disabled' do
        $reget_lines = []
        use_options(OpenStruct.new)
        run_main
        header_line = log_content.lines.first.chomp
        expect(header_line).to eq(frozen_time.strftime("%Y-%m-%d %H:%M:%S.%L %:z"))
      end
    end
  end
end
