require 'tmpdir'
require 'fileutils'
require 'ostruct'
require 'timeout'
require_relative '../support/log_spec_harness'

# Nested in Env so GameLogger, XMLData, Script and Lich below are the ones
# log.lic's code sees.
module LogSpecHarness::Env
  RSpec.describe GameLogger do
    around do |example|
      login_time = $login_time
      example.run
    ensure
      $login_time = login_time
    end

    before do
      LogSpecHarness.reset!
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

        # R-09: the quote-aware rescan of vars[0] is load-bearing. Each
        # example starts the script as lich-5 does (Script#initialize): a
        # typed String, or the Array autostart.lic saves and starts it with.
        context 'when called with no args (reads Script.current.vars)' do
          it "reads the header's autostart example whole on the autostart Array path" do
            # ;autostart add --global log --timestamp=\"%F %T %Z\" --rnum --exclude=288,2300,u7199 --lines=50000
            # is saved as these words; lich-5 joins them into vars[0] and keeps them as vars[1..].
            LogSpecHarness.start_script(['--timestamp="%F', '%T', '%Z"', '--rnum', '--exclude=288,2300,u7199', '--lines=50000'])

            result = described_class.parse

            expect(result.to_h).to eq(timestamp: '%F %T %Z', rnum: true, exclude: %w[288 2300 u7199], lines: '50000')
          end

          it 'keeps a comma in a quoted format on the autostart Array path' do
            LogSpecHarness.start_script(['--timestamp="%b', '%d,', '%Y', '%T"', '--rnum'])

            result = described_class.parse

            expect(result.to_h).to eq(timestamp: '%b %d, %Y %T', rnum: true)
          end

          it 'reads the same format when the command was typed (String path)' do
            LogSpecHarness.start_script('--timestamp="%F %T %Z" --rnum')

            result = described_class.parse

            expect(result.to_h).to eq(timestamp: '%F %T %Z', rnum: true)
          end

          # The rescan splits vars[0] as lich-5 splits a typed line: a \"
          # inside quotes is a literal quote.
          it 'keeps an escaped quote inside a quoted format as a quote' do
            LogSpecHarness.start_script('--timestamp="%H \\"h\\" %M" --rnum')

            result = described_class.parse

            expect(result.to_h).to eq(timestamp: '%H "h" %M', rnum: true)
          end

          it 'uses vars[1..] when vars[0] has no quotes' do
            LogSpecHarness.start_script(['--rnum', '--lines=500'])

            result = described_class.parse

            expect(result.to_h).to eq(rnum: true, lines: '500')
          end

          it 'gives no options when the script was started without arguments (vars is empty)' do
            LogSpecHarness.start_script('')

            result = described_class.parse

            expect(LogSpecHarness.script.vars).to eq([])
            expect(result.to_h).to eq({})
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
          LogSpecHarness.server_buffer = ['You see a door.', 'Obvious exits: north, south.']

          run_main

          expect(log_content.lines(chomp: true)).to eq(
            [
              '2026-04-23 10:00:05',
              '2026-04-23 10:00:00: You see a door.',
              '2026-04-23 10:00:00: Obvious exits: north, south.',
              '<!-- Above contents from reget; full logging now active -->',
              '2026-04-23 10:00:05'
            ]
          )
        end

        it 'uses $login_time not current time for reget timestamps' do
          $login_time = Time.new(2026, 1, 1, 12, 30, 45)
          allow(Time).to receive(:now).and_return(Time.new(2026, 1, 1, 12, 30, 50))
          LogSpecHarness.server_buffer = ['Test line']

          run_main

          expect(log_content.lines(chomp: true)).to eq(
            [
              '2026-01-01 12:30:50',
              '2026-01-01 12:30:45: Test line',
              '<!-- Above contents from reget; full logging now active -->',
              '2026-01-01 12:30:50'
            ]
          )
        end
      end

      context 'without timestamps' do
        before do
          use_options(OpenStruct.new)
        end

        it 'writes reget lines without timestamps' do
          LogSpecHarness.server_buffer = ["You see a door.\r"]

          run_main

          expect(log_content.lines(chomp: true)[1, 2]).to eq(
            ['You see a door.', '<!-- Above contents from reget; full logging now active -->']
          )
        end

        # The logger never sets want_downstream_xml, so lich-5's reget has
        # already stripped every tag and decoded the entities (lib/global_defs.rb,
        # def reget). A reget line can only start with "<" when the server sent
        # game text escaped: "&lt;pushStream id='x'/&gt; spoof\r" in
        # $_SERVERBUFFER_ comes back as "<pushStream id='x'/> spoof\r".
        # Text mode's reget_line filters no line, so it is written unchanged,
        # less the "\r".
        it 'writes a reget line that starts with "<" unchanged' do
          LogSpecHarness.server_buffer = ["&lt;pushStream id='x'/&gt; spoof\r", "You see a door.\r"]

          run_main

          expect(log_content.lines(chomp: true)[1, 2]).to eq(["<pushStream id='x'/> spoof", 'You see a door.'])
        end
      end

      context 'when login was more than 30 seconds ago' do
        before do
          $login_time = frozen_time - 60
          use_options(OpenStruct.new(timestamp: '%F %T'))
        end

        it 'writes neither the reget lines nor the marker, only the header, the lines and the footer' do
          LogSpecHarness.server_buffer = ['Should not appear']
          LogSpecHarness.feed('You see a door.')

          run_main

          expect(log_content.lines(chomp: true)).to eq(
            ['2026-04-23 10:00:05', '2026-04-23 10:00:05: You see a door.', '2026-04-23 10:00:05']
          )
        end
      end

      it 'writes the reget lines and then the marker when the logger starts within 30 seconds' do
        $login_time = frozen_time - 5
        LogSpecHarness.server_buffer = ['test']
        LogSpecHarness.feed('You see a door.')
        use_options(OpenStruct.new)

        run_main

        expect(log_content.lines(chomp: true)).to eq(
          [
            default_stamp,
            'test',
            '<!-- Above contents from reget; full logging now active -->',
            'You see a door.',
            default_stamp
          ]
        )
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

      it 'creates the <game>-<name>/<year>/<month> folders when none exist yet' do
        use_options(OpenStruct.new)
        expect(Dir.exist?(File.join(log_dir, 'logs'))).to be false

        run_main

        expect(Dir.children(File.join(log_dir, 'logs'))).to eq(['GSIV-TestChar'])
        expect(Dir.children(File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04'))).to eq(['2026-04-23_10-00-05.log'])
      end

      # The buffer holds only tags and blank lines: reget strips them all
      # and answers nil.
      it 'writes the marker and no stamped line when reget answers nil, timestamps on' do
        LogSpecHarness.server_buffer = ["<prompt time=\"1792091317\">&gt;</prompt>\r", "\r"]
        use_options(OpenStruct.new(timestamp: '%F %T'))

        run_main

        expect(log_content.lines(chomp: true)).to eq(
          ['2026-04-23 10:00:05', '<!-- Above contents from reget; full logging now active -->', '2026-04-23 10:00:05']
        )
      end

      # R-14: lich-5's reget returns nil when the buffer is empty. log.lic
      # only survived that in game through Lich's NilClass patch.
      it 'writes only the marker when reget answers nil (an empty buffer)' do
        LogSpecHarness.server_buffer = []
        use_options(OpenStruct.new)

        run_main

        expect(File.read(find_log_file).lines(chomp: true).first(2)).to eq(
          [frozen_time.strftime("%Y-%m-%d %H:%M:%S.%L %:z"), '<!-- Above contents from reget; full logging now active -->']
        )
      end

      # R-11: lich-5's reget hands back the raw XML when the script wants
      # the XML downstream, and tag-stripped text otherwise. The text logger
      # leaves want_downstream_xml off, so its reget lines are text. Server
      # lines verbatim from lich-5 spec/fixtures/streams/gs_saga_hunt.xml.
      it 'writes the text of the reget lines, as reget gives a script that does not want XML' do
        LogSpecHarness.server_buffer = [
          "<style id=\"\"/><style id=\"roomDesc\"/>The tiled ground is chipped, resembling run down cobblestones.<style id=\"\"/>\r",
          "Obvious exits: <a exist=\"-10700001\" coord=\"2524,1864\" noun=\"north\">north</a>, <a exist=\"-10700001\" coord=\"2524,1864\" noun=\"east\">east</a>\r",
          "<compass><dir value=\"n\"/><dir value=\"e\"/></compass><prompt time=\"1792091316\">&gt;</prompt>\r",
          "<component id='room objs'>  You also see the <a exist=\"781927405\" noun=\"disk\">purple Aldric disk</a>.</component>\r",
          "Your <a exist=\"781927405\" noun=\"disk\">disk</a> arrives, following you dutifully.\r"
        ]
        use_options(OpenStruct.new)

        run_main

        expect(LogSpecHarness.script.want_downstream_xml).to be false
        expect(log_content.lines(chomp: true)[1..-2]).to eq(
          [
            'The tiled ground is chipped, resembling run down cobblestones.',
            'Obvious exits: north, east',
            'Your disk arrives, following you dutifully.',
            '<!-- Above contents from reget; full logging now active -->'
          ]
        )
      end

      # R-15: $_SERVERBUFFER_ keeps the server's CRLF line ends and reget
      # splits on "\n", so each reget line ends in "\r".
      context 'when the reget lines end in a carriage return' do
        it 'writes them without it, timestamps off' do
          LogSpecHarness.server_buffer = ["You see a door.\r", "Obvious exits: north.\r"]
          use_options(OpenStruct.new)

          run_main

          expect(File.binread(find_log_file)).not_to include("\r")
          expect(log_content.lines(chomp: true)[1, 2]).to eq(['You see a door.', 'Obvious exits: north.'])
        end

        it 'writes them without it, timestamps on' do
          LogSpecHarness.server_buffer = ["You see a door.\r"]
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

      # The other examples call GameLogger.main; this one runs the script as
      # Lich does, so the calls outside the module are covered too.
      it 'hides the script and starts the logger once when the whole script runs' do
        LogSpecHarness.start_script('--timestamp=%H:%M')
        LogSpecHarness.feed('You see a door.')

        Timeout.timeout(5) { LogSpecHarness.run_whole_script }

        expect(LogSpecHarness.hide_me_calls).to eq(1)
        expect(Dir.glob(File.join(log_dir, '**', '*.log')).size).to eq(1)
        expect(log_lines).to eq(
          ['10:00', '<!-- Above contents from reget; full logging now active -->', '10:00: You see a door.', '10:00']
        )
        expect(LogSpecHarness.echoes).to eq(["Non-XML Logging started, currently logging to #{find_log_file}"])
      end

      # R-04
      context 'with a --timestamp format that holds a comma' do
        it 'writes the header and each line with the whole format' do
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

      # R-09 through main: with no options passed, main parses the script's
      # arguments itself, and a quoted format needs the rescan of vars[0].
      context 'when started with a quoted --timestamp and no options passed' do
        it 'stamps the header and each line with the whole format' do
          # As autostart starts it, with the Array of saved words.
          LogSpecHarness.start_script(['--timestamp="%b', '%d', '%T"'])
          LogSpecHarness.feed('You see a door.')

          run_main

          expect(log_lines).to eq(
            [
              'Apr 23 10:00:05',
              '<!-- Above contents from reget; full logging now active -->',
              'Apr 23 10:00:05: You see a door.',
              'Apr 23 10:00:05'
            ]
          )
        end
      end

      context 'with a --timestamp format that holds an equals sign' do
        it 'prefixes each line with the whole format' do
          use_options(GameLogger::Opts.parse(['--timestamp=%H=%M']))
          LogSpecHarness.feed('You see a door.')

          run_main

          expect(log_lines.last(2)).to eq(['10=00: You see a door.', '10=00'])
        end
      end

      let(:no_format_echo) do
        'timestamp was given without a format, so it is ignored; to add timestamps use --timestamp="%F %T %Z".'
      end

      # Runs main with get_settings answering +settings+ (in DR, the
      # character's yaml).
      def run_main_with_settings(settings)
        LogSpecHarness.settings = settings
        run_main
      end

      context 'with a bare --timestamp, the word timestamp, or an empty --timestamp=' do
        [['--timestamp'], ['timestamp'], ['--timestamp=']].each do |args|
          it "logs without timestamps for #{args.first} and says the option was ignored" do
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
          use_options(GameLogger::Opts.parse(['--timestamp']))
          LogSpecHarness.feed('You see a door.')

          run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))

          expect(log_lines).to eq(
            ['10:00', '<!-- Above contents from reget; full logging now active -->', '10:00: You see a door.', '10:00']
          )
          expect(LogSpecHarness.echoes.first).to eq(no_format_echo)
        end
      end

      # R-31: in DragonRealms, get_settings answers the character's yaml
      # (dr-scripts profiles/base.yaml has log_timestamp and
      # log_timestamp_format), which turns timestamps on without --timestamp.
      context 'with DragonRealms yaml settings' do
        # A characterization: main does not guard the call, so the error
        # ends the script before anything is logged.
        it 'lets an error from get_settings through before it opens a file or reads typed commands' do
          use_options(OpenStruct.new)
          allow(GameLogger).to receive(:get_settings).and_raise(RuntimeError, 'bad yaml')

          expect { run_main }.to raise_error(RuntimeError, 'bad yaml')
          expect(find_log_file).to be_nil
          expect(LogSpecHarness.upstream_thread).to be_nil
          expect(LogSpecHarness.echoes).to eq([])
        end

        it 'stamps the header, the reget lines with the login time, each line and the footer when log_timestamp is true' do
          $login_time = frozen_time - 5
          LogSpecHarness.server_buffer = ["You see a door.\r"]
          use_options(GameLogger::Opts.parse([]))
          LogSpecHarness.feed('Obvious exits: north.')

          run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: '%F %T'))

          expect(log_lines).to eq(
            [
              '2026-04-23 10:00:05',
              '2026-04-23 10:00:00: You see a door.',
              '<!-- Above contents from reget; full logging now active -->',
              '2026-04-23 10:00:05: Obvious exits: north.',
              '2026-04-23 10:00:05'
            ]
          )
          expect(LogSpecHarness.echoes.size).to eq(1)
        end

        it 'uses a --timestamp=FMT over the yaml format' do
          use_options(GameLogger::Opts.parse(['--timestamp=%H:%M']))
          LogSpecHarness.feed('You see a door.')

          run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: '%F %T'))

          expect(log_lines.last(2)).to eq(['10:00: You see a door.', '10:00'])
        end

        it 'does not stamp when log_timestamp is false, even with a format set' do
          use_options(GameLogger::Opts.parse([]))
          LogSpecHarness.feed('You see a door.')

          run_main_with_settings(OpenStruct.new(log_timestamp: false, log_timestamp_format: '%F %T'))

          expect(log_lines.last(2)).to eq(['You see a door.', default_stamp])
        end
      end

      # R-04 through the settings path: the yaml format is checked like the
      # --timestamp one before it reaches strftime.
      context 'when the yaml enables timestamps without a usable format' do
        { 'no format' => nil, 'an empty format' => '', 'a non-String format' => 5 }.each do |label, format|
          it "stamps with %F %T %Z and says so for #{label} (#{format.inspect})" do
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
          use_options(GameLogger::Opts.parse(['--timestamp=%H:%M']))
          LogSpecHarness.feed('You see a door.')

          run_main_with_settings(OpenStruct.new(log_timestamp: true, log_timestamp_format: nil))

          expect(log_lines.last(2)).to eq(['10:00: You see a door.', '10:00'])
          expect(LogSpecHarness.echoes.size).to eq(1)
        end

        it 'logs without timestamps and without a message when the yaml leaves timestamps off' do
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
          use_options(OpenStruct.new)
          LogSpecHarness.wait_for_upstream!
          LogSpecHarness.type('<c>look')

          run_main

          expect(log_lines.last(2)).to eq(['>look', default_stamp])
        end

        it 'removes a <c> only from the start, and logs a command typed without one whole' do
          use_options(OpenStruct.new)
          LogSpecHarness.wait_for_upstream!
          LogSpecHarness.type('say <c> is the tag', '<c>say <c> too')

          run_main

          expect(log_lines.drop(2)).to eq(['>say <c> is the tag', '>say <c> too', default_stamp])
        end

        it 'logs typed commands and game lines in the order the buffer holds them, stamped alike' do
          use_options(OpenStruct.new(timestamp: '%H:%M:%S'))
          LogSpecHarness.wait_for_upstream!
          LogSpecHarness.feed('You see a door.')
          LogSpecHarness.type('<c>look')

          run_main

          expect(log_lines).to eq(
            ['10:00:05', '<!-- Above contents from reget; full logging now active -->', '10:00:05: You see a door.', '10:00:05: >look', '10:00:05']
          )
        end
      end

      # R-01: what lich-5 hands the logger. Script#initialize starts with
      # the text downstream on and the rest off; the logger turns on script
      # output and typed commands and leaves the XML downstream off (so
      # reget and get give it text).
      it 'asks for script output and typed commands, and keeps the text downstream and not the XML one' do
        use_options(OpenStruct.new)

        run_main

        expect(LogSpecHarness.script.to_h.slice(:want_downstream, :want_downstream_xml, :want_script_output, :want_upstream))
          .to eq(want_downstream: true, want_downstream_xml: false, want_script_output: true, want_upstream: true)
      end

      # R-01, R-31: the reget is written when the logger starts less than
      # 30 seconds after login, never at 30 seconds or later.
      context 'at the edge of the 30-second reget window' do
        it 'writes the reget and the marker when the logger starts 29.9 seconds after login' do
          $login_time = frozen_time - 29.9
          LogSpecHarness.server_buffer = ["You see a door.\r"]
          use_options(OpenStruct.new)

          run_main

          expect(log_lines).to eq(
            [default_stamp, 'You see a door.', '<!-- Above contents from reget; full logging now active -->', default_stamp]
          )
        end

        it 'writes neither the reget nor the marker when the logger starts 30 seconds after login' do
          $login_time = frozen_time - 30
          LogSpecHarness.server_buffer = ["You see a door.\r"]
          use_options(OpenStruct.new)

          run_main

          expect(log_lines).to eq([default_stamp, default_stamp])
        end
      end

      # R-01: game lines in text mode, verbatim from the text log base
      # log.lic wrote under a real lich.rbw child replaying lich-5
      # spec/fixtures/streams/gs_saga_hunt.xml
      # (indents, "..." and "==" included), are written as they come.
      it 'writes real text-stream lines unchanged, each stamped with the time it is read' do
        use_options(OpenStruct.new(timestamp: '%T'))
        LogSpecHarness.feed(
          'Obvious exits: north, east, west',
          'You are now targeting a lithe veiled sentinel.',
          '  1d100: 20 + Modifiers: 372 == 392',
          '  CS: +618 - TD: +443 + CvA: +25 + d125: +61 + Bonus: +1 == +262',
          '   ... 60 points of damage!',
          'He had a pink rhodochrosite stone on him!'
        )

        run_main

        expect(log_lines[2..-2]).to eq(
          [
            '10:00:05: Obvious exits: north, east, west',
            '10:00:05: You are now targeting a lithe veiled sentinel.',
            '10:00:05:   1d100: 20 + Modifiers: 372 == 392',
            '10:00:05:   CS: +618 - TD: +443 + CvA: +25 + d125: +61 + Bonus: +1 == +262',
            '10:00:05:    ... 60 points of damage!',
            '10:00:05: He had a pink rhodochrosite stone on him!'
          ]
        )
      end

      # R-01: a line that starts with one of these tags (script output can
      # carry them) is dropped; the tags elsewhere in a line keep it. Tag
      # lines verbatim from lich-5 spec/fixtures/streams, except the closing
      # tag, which the filter also matches.
      describe 'lines that start with a stream, dialog or progress bar tag' do
        {
          'a stream switch'          => '<pushStream id="percWindow"/> Turtle (61 roisaen)',
          'a stream end'             => '<popStream/><pushStream id="percWindow"/> Dragon (10 roisaen)',
          'a progress bar'           => %(<progressBar id='1253901988' value='89' text="Mana Tap" left='22%' top='0' width='76%' height='15' time='00:13:28'/>),
          'dialog data'              => "<dialogData id='Cooldowns' clear='t'></dialogData>",
          'an open dialog'           => '<openDialog type="dynamic" id="injuries" title="Injuries" target="injuries" location="right" height="180" width="190" resident="true">',
          'a close dialog'           => "<closeDialog id='AimTimerDialog'/>",
          'a closing dialogData tag' => '</dialogData>'
        }.each do |label, tag_line|
          it "drops #{label} and logs the lines around it" do
            use_options(OpenStruct.new)
            LogSpecHarness.feed('before', tag_line, 'after')

            run_main

            expect(log_lines.drop(2)).to eq(['before', 'after', default_stamp])
          end
        end

        it 'logs a line whose stream tag comes after other text' do
          line = "<right>Empty</right><clearStream id='inv' ifClosed=''/><pushStream id='inv'/>Your worn items are:"
          use_options(OpenStruct.new)
          LogSpecHarness.feed(line)

          run_main

          expect(log_lines.drop(2)).to eq([line, default_stamp])
        end

        it 'logs a line that starts with another tag' do
          use_options(OpenStruct.new)
          LogSpecHarness.feed("<prompt time=\"1792091317\">&gt;</prompt>")

          run_main

          expect(log_lines.drop(2)).to eq(["<prompt time=\"1792091317\">&gt;</prompt>", default_stamp])
        end
      end

      # R-21: the upstream thread's rescue echoed only the bare message, so a
      # pasted log just lost its commands with nothing saying where or why
      # (in lich-5 that echo reached the file only as script output, see
      # want_script_output; this harness does not feed echoes back to get).
      context 'when the upstream thread stops on an error' do
        let(:notice) { '<!-- log: typed commands are not logged after this line; the upstream thread stopped (RuntimeError: boom) -->' }

        # "file:line" of where +error+ was raised, without the directory.
        def raised_at(error)
          location = error.backtrace_locations.first
          "#{File.basename(location.path)}:#{location.lineno}"
        end

        # The notice line as written for an error that reads +reason+.
        def notice_for(reason)
          "<!-- log: typed commands are not logged after this line; the upstream thread stopped (#{reason}) -->"
        end

        # The first typed command is logged; the next upstream_get raises
        # +error+.
        def type_then_fail(error)
          calls = 0
          allow(GameLogger::Logger).to receive(:upstream_get) do
            calls += 1
            raise error if calls > 1

            '<c>look'
          end
        end

        it 'echoes the error, where it was raised and how to log typed commands again' do
          use_options(OpenStruct.new)
          LogSpecHarness.wait_for_upstream!
          error = RuntimeError.new('boom')
          type_then_fail(error)

          run_main

          expect(LogSpecHarness.echoes.grep(/\Atyped commands/)).to eq(
            [
              "typed commands are no longer logged: the upstream thread stopped on RuntimeError: boom at #{raised_at(error)}. " \
              'Game lines are still logged; restart the logger (;kill log, then ;log) to log typed commands again.'
            ]
          )
          expect(raised_at(error)).to match(/\Alog_spec\.rb:\d+\z/)
        end

        # The directory (C:/Users/<name>/...) only makes the echo longer.
        it 'gives the file and line it was raised at without the directory' do
          use_options(OpenStruct.new)
          LogSpecHarness.wait_for_upstream!
          error = RuntimeError.new('boom')
          error.set_backtrace(["C:/Users/someone/Lich5/scripts/log.lic:487:in 'block in GameLogger.start_upstream_logger'"])
          allow(GameLogger::Logger).to receive(:upstream_get).and_raise(error)

          run_main

          expect(LogSpecHarness.echoes.grep(/\Atyped commands/).first)
            .to start_with('typed commands are no longer logged: the upstream thread stopped on RuntimeError: boom at log.lic:487. ')
          expect(LogSpecHarness.echoes.join).not_to include('someone')
        end

        it 'leaves out "at" when the error has no backtrace' do
          GameLogger::Logger.upstream_stopped(RuntimeError.new('boom'))

          expect(LogSpecHarness.echoes).to eq(
            ['typed commands are no longer logged: the upstream thread stopped on RuntimeError: boom. ' \
             'Game lines are still logged; restart the logger (;kill log, then ;log) to log typed commands again.']
          )
        end

        it 'gives the frame as is when it has no "path:line" start' do
          error = RuntimeError.new('boom')
          error.set_backtrace(['<internal:kernel>'])

          expect(GameLogger::Logger.upstream_frame(error)).to eq('<internal:kernel>')

          GameLogger::Logger.upstream_stopped(error)

          expect(LogSpecHarness.echoes.first)
            .to start_with('typed commands are no longer logged: the upstream thread stopped on RuntimeError: boom at <internal:kernel>. ')
        end

        # Without the strip, the hint would read ";log " with a trailing space.
        it 'gives the restart without arguments when vars[0] is only whitespace' do
          allow(Script.current).to receive(:vars).and_return(['  '])

          GameLogger::Logger.upstream_stopped(RuntimeError.new('boom'))

          expect(LogSpecHarness.echoes.first).to end_with('(;kill log, then ;log) to log typed commands again.')
        end

        # ;log plus ;force log --xml: both run as log. ;kill log stops the
        # first log Lich finds, and ;log without ;force is refused while the
        # other one runs (lich-5 v5.21.0 lib/global_defs.rb:2500,
        # lib/common/script.rb:744).
        it 'restarts with ;force, and says ;kill log can stop the other one, when another log is running (hidden, as log hides itself)' do
          LogSpecHarness.other_scripts = [OpenStruct.new(name: 'log', hidden: true)]

          GameLogger::Logger.upstream_stopped(RuntimeError.new('boom'))

          expect(LogSpecHarness.echoes.first).to end_with(
            'restart the logger (;kill log, then ;force log; another log is running too, and ;kill log stops the first log Lich finds, ' \
            'which can be the other one) to log typed commands again.'
          )
        end

        it 'restarts with ;force when the other log is not hidden, and when its name differs only in case' do
          LogSpecHarness.other_scripts = [OpenStruct.new(name: 'LOG', hidden: false)]
          allow(Script.current).to receive(:vars).and_return(['--rnum', '--rnum'])

          GameLogger::Logger.upstream_stopped(RuntimeError.new('boom'))

          expect(LogSpecHarness.echoes.first).to include('(;kill log, then ;force log --rnum; another log is running too, ')
        end

        # A run named logxml (an install's local logxml.lic) does not block
        # ;log, and ;kill log picks the exact name first.
        it 'restarts without ;force when only scripts of other names run' do
          LogSpecHarness.other_scripts = [OpenStruct.new(name: 'logxml', hidden: true), OpenStruct.new(name: 'mylog', hidden: false)]

          GameLogger::Logger.upstream_stopped(RuntimeError.new('boom'))

          expect(LogSpecHarness.echoes.first).to end_with('(;kill log, then ;log) to log typed commands again.')
        end

        # Restarting without them would log rooms the user excluded.
        it 'gives the restart with the arguments the logger was started with, under its own name' do
          use_options(OpenStruct.new)
          LogSpecHarness.wait_for_upstream!
          allow(Script.current).to receive_messages(
            name: 'mylog',
            vars: ['--exclude=u1234 --timestamp="%H:%M"', '--exclude=u1234', '--timestamp="%H:%M"']
          )
          type_then_fail(RuntimeError.new('boom'))

          run_main

          expect(LogSpecHarness.echoes.grep(/\Atyped commands/).first)
            .to end_with('restart the logger (;kill mylog, then ;mylog --exclude=u1234 --timestamp="%H:%M") to log typed commands again.')
        end

        it 'writes a notice line into the log file saying typed commands are not logged after it, and keeps logging game lines' do
          use_options(OpenStruct.new)
          LogSpecHarness.wait_for_upstream!
          LogSpecHarness.feed('line 1')
          type_then_fail(RuntimeError.new('boom'))

          run_main

          expect(log_lines.drop(2)).to eq(['line 1', '>look', notice, default_stamp])
        end

        it 'stamps that line like a game line when timestamps are on' do
          use_options(OpenStruct.new(timestamp: '%H:%M'))
          LogSpecHarness.wait_for_upstream!
          type_then_fail(RuntimeError.new('boom'))

          run_main

          expect(log_lines.last(3)).to eq(['10:00: >look', "10:00: #{notice}", '10:00'])
        end

        it 'puts a message over several lines on one line, and breaks up "--" so the comment is not closed early' do
          use_options(OpenStruct.new)
          LogSpecHarness.wait_for_upstream!
          type_then_fail(IOError.new("closed stream\n--> see above"))

          run_main

          expect(log_lines[-2]).to eq('<!-- log: typed commands are not logged after this line; the upstream thread stopped (IOError: closed stream - -> see above) -->')
          expect(LogSpecHarness.echoes.grep(/\Atyped commands/).first)
            .to start_with('typed commands are no longer logged: the upstream thread stopped on IOError: closed stream --> see above at ')
        end

        # gsub('--', '- -') left "a - --> b" and "x- --y": the first closed the
        # comment early, both left a "--" XML does not allow in a comment.
        {
          'a ---> b'          => 'a - - -> b',
          '--- Lich: x---y'   => '- - - Lich: x- - -y',
          'ends in a dash -'  => 'ends in a dash -',
          'ends in dashes --' => 'ends in dashes - -'
        }.each do |message, spaced|
          it "spaces out every dash run in #{message.inspect} so the comment holds no \"--\"" do
            use_options(OpenStruct.new)
            LogSpecHarness.wait_for_upstream!
            type_then_fail(IOError.new(message))

            run_main

            expect(log_lines[-2]).to eq(notice_for("IOError: #{spaced}"))
            body = log_lines[-2].delete_prefix('<!--').delete_suffix('-->')
            expect(body).not_to include('--')
            expect(body).not_to end_with('-')
          end
        end

        it 'drops the whitespace around the message' do
          use_options(OpenStruct.new)
          LogSpecHarness.wait_for_upstream!
          type_then_fail(RuntimeError.new(" \tboom\n"))

          run_main

          expect(log_lines[-2]).to eq(notice)
          expect(LogSpecHarness.echoes.grep(/\Atyped commands/).first)
            .to start_with('typed commands are no longer logged: the upstream thread stopped on RuntimeError: boom at ')
        end

        it 'does not write the line in an --exclude room' do
          use_options(GameLogger::Opts.parse(['--exclude=u1234']))
          LogSpecHarness.wait_for_upstream!
          type_then_fail(RuntimeError.new('boom'))

          run_main

          expect(log_lines.drop(2)).to eq([default_stamp])
          expect(LogSpecHarness.echoes.grep(/\Atyped commands are no longer logged: /).size).to eq(1)
        end
      end

      describe '.start_upstream_logger' do
        # lich-5 stops a script by Thread#kill on its threads (script.rb kill).
        it 'says nothing and leaves no line when the thread is killed, as ;kill log does' do
          waiting = Thread::Queue.new
          allow(GameLogger::Logger).to receive(:upstream_get) do
            waiting << true
            sleep # waits for the next typed command until ;kill
          end
          thread = GameLogger::Logger.start_upstream_logger
          Timeout.timeout(2) { waiting.pop }

          thread.kill
          thread.join(2)

          expect(thread).not_to be_alive
          expect(LogSpecHarness.echoes).to eq([])
          expect(LogSpecHarness::DOWNSTREAM).to be_empty
        end
      end

      # R-05, R-07, R-18, R-19, R-34: --rnum and --exclude take the room from
      # XMLData and the map's UID table only (Q-13 A), never from
      # Room.current or Map.current, which can send LOCATION/PEER from the
      # logger and rescan the whole map on every line.
      describe 'room lookups for --rnum and --exclude' do
        # The parser's room as the logger sees it when it reads a line. A Hash
        # fed between lines moves the parser to another room, and a Proc fed
        # between lines runs there (see the get stub).
        let(:room) { { game: 'GSIV', count: 1, uid: 4_216_015, title: '[Sanctum of Scales, Columns]' } }
        # UID => Lich ids, as Map.ids_from_uid answers from the map's UID table.
        let(:uid_table) { {} }
        # Strict doubles: any call other than Map.ids_from_uid and Map.loaded?
        # (the map is loaded unless an example says otherwise) fails the example.
        let(:map) { double('Map') }
        let(:room_class) { double('Room') }

        before do
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
            until item.is_a?(String)
              item.is_a?(Hash) ? room.merge!(item) : item.call
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

          it 'puts the Lich id inside the first ] only' do
            uid_table[4_216_015] = [228]
            LogSpecHarness.feed('[Sanctum of Scales, Columns] [lit]')

            expect(log_with('--rnum')).to eq(['[Sanctum of Scales, Columns - 228] [lit] (u4216015)'])
          end

          # Another script reloading the map can give the UID another Lich
          # id. The logger keeps the id it found while the parser stays in
          # the room, and asks again when the parser shows the room again
          # (a new room count, as LOOK gives), even with the same UID and title.
          it 'keeps a found Lich id for the room until the room count changes' do
            uid_table[4_216_015] = [228]
            LogSpecHarness.feed(
              '[Sanctum of Scales, Columns]',
              -> { uid_table[4_216_015] = [229] },
              '[Sanctum of Scales, Columns]',
              { count: 2 },
              '[Sanctum of Scales, Columns]'
            )

            expect(log_with('--rnum')).to eq(
              [
                '[Sanctum of Scales, Columns - 228] (u4216015)',
                '[Sanctum of Scales, Columns - 228] (u4216015)',
                '[Sanctum of Scales, Columns - 229] (u4216015)'
              ]
            )
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

          # Rooms next to each other often share a title. With the parser a
          # room ahead of the line, the title still matches, but the UID it
          # shows is the last room's, so the line is left as sent.
          it "numbers no title that shows another room's UID, the parser being a room ahead" do
            uid_table.merge!(4_216_015 => [228], 4_216_016 => [229])
            LogSpecHarness.feed(
              { count: 2, uid: 4_216_016 },
              '[Sanctum of Scales, Columns] (4216015)',
              '[Sanctum of Scales, Columns] (4216016)'
            )

            expect(log_with('--rnum')).to eq(['[Sanctum of Scales, Columns] (4216015)', '[Sanctum of Scales, Columns - 229] (4216016)'])
          end

          it 'builds the title matcher once per room, not once per line' do
            allow(GameLogger::Logger).to receive(:room_title_pattern).and_call_original
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
            expect(GameLogger::Logger).to have_received(:room_title_pattern).twice
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
            expect(GameLogger::Logger.lich_room_id(4_216_015)).to eq(288)
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
            LogSpecHarness.wait_for_upstream!
            LogSpecHarness.type('look')

            expect(log_with('--exclude=u4216015')).to eq([])
          end

          # --exclude looks the room up, but only --rnum numbers its title.
          it 'leaves the room title alone with --exclude of u-ids and no --rnum' do
            uid_table[4_216_015] = [228]
            LogSpecHarness.feed('[Sanctum of Scales, Columns]', 'x')

            expect(log_with('--exclude=u7199')).to eq(['[Sanctum of Scales, Columns]', 'x'])
          end

          it 'leaves the room title alone with --exclude of a Lich id and no --rnum, in a room it looked up' do
            uid_table[4_216_015] = [300]
            LogSpecHarness.feed('[Sanctum of Scales, Columns]', 'x')

            expect(log_with('--exclude=u7199,288')).to eq(['[Sanctum of Scales, Columns]', 'x'])
            expect(map).to have_received(:ids_from_uid).with(4_216_015)
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
        def log_files(extension = 'log')
          root = File.join(log_dir, 'logs', 'GSIV-TestChar')
          Dir.glob(File.join(root, '**', "*.#{extension}")).to_h do |path|
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

        # The date is checked before the filter, as before the --exclude skip.
        it 'starts the new file on the first line after midnight even when the filter drops it' do
          use_options(OpenStruct.new)
          LogSpecHarness.feed('line 1', next_day, '<pushStream id="percWindow"/> Turtle (61 roisaen)')

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

        # R-06: XML mode follows a stream span across lines, so every line
        # read goes through the filter, in a room excluded or not and on
        # either side of a new file; a span left open on a line it never
        # read would hide the main-window lines after the popStream.
        context 'when an XML stream span is open' do
          let(:xml_header) { '2026-04-23 10:00am' }
          let(:span_start) { "<pushStream id='inv'/>Your worn items are:" }

          it 'closes the span on a popStream read in an excluded room' do
            use_options(GameLogger::Opts.parse(['--xml', '--exclude=u7199']))
            LogSpecHarness.feed(span_start, { count: 2, uid: 7199 }, '<popStream/>', { count: 3, uid: 1234 }, 'You see a door.')

            run_main

            expect(log_files('xml')).to eq('2026/04/2026-04-23_10-00-05.xml' => [xml_header, marker, 'You see a door.', default_stamp])
          end

          it 'opens the span on a pushStream read in an excluded room' do
            use_options(GameLogger::Opts.parse(['--xml', '--exclude=u7199']))
            LogSpecHarness.feed({ count: 2, uid: 7199 }, span_start, { count: 3, uid: 1234 }, '  a gilded locus', '<popStream/>You see a door.')

            run_main

            expect(log_files('xml')).to eq('2026/04/2026-04-23_10-00-05.xml' => [xml_header, marker, 'You see a door.', default_stamp])
          end

          it "keeps the span open into the new day's file" do
            use_options(GameLogger::Opts.parse(['--xml']))
            LogSpecHarness.feed('line 1', span_start, next_day, '  a gilded locus', '<popStream/>', 'line 2')

            run_main

            expect(log_files('xml')).to eq(
              '2026/04/2026-04-23_10-00-05.xml' => [xml_header, marker, 'line 1', next_day_stamp],
              '2026/04/2026-04-24_00-00-01.xml' => ['2026-04-24 12:00am', 'line 2', next_day_stamp]
            )
          end

          it 'keeps the span open into the next file after a full one' do
            use_options(GameLogger::Opts.parse(['--xml', '--lines=2']))
            LogSpecHarness.feed('line 1', "a#{span_start}", '  a gilded locus', '<popStream/>', 'line 2')

            run_main

            expect(log_files('xml')).to eq(
              '2026/04/2026-04-23_10-00-05.xml'    => [xml_header, marker, 'line 1', 'a', default_stamp],
              '2026/04/2026-04-23_10-00-05_01.xml' => [xml_header, 'line 2', default_stamp]
            )
          end
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

        # R-31: each file goes in the year and month folders of its own
        # start, so a new day that is a new month or year opens new folders.
        it 'puts the file of a new month and of a new year under their own year/month folders' do
          december_last = Time.new(2026, 12, 31, 23, 59, 59)
          new_year = Time.new(2027, 1, 1, 0, 0, 1)
          use_options(OpenStruct.new)
          LogSpecHarness.feed('april line', december_last, 'december line', new_year, 'january line')

          run_main

          expect(log_files.transform_values { |lines| lines[-2] }).to eq(
            '2026/04/2026-04-23_10-00-05.log' => 'april line',
            '2026/12/2026-12-31_23-59-59.log' => 'december line',
            '2027/01/2027-01-01_00-00-01.log' => 'january line'
          )
        end

        # An error from get (not the StopIteration that ends the loop) is
        # not swallowed: the file gets its footer, is closed, and the error
        # stops the logger.
        it 'ends the file with its footer and lets an error raised while reading a line through' do
          use_options(OpenStruct.new)
          LogSpecHarness.feed('line 1', 'line 2')
          reads = 0
          allow(GameLogger).to receive(:get).and_wrap_original do |original|
            reads += 1
            raise IOError, 'stream closed' if reads == 2

            original.call
          end

          expect { run_main }.to raise_error(IOError, 'stream closed')

          expect(log_files).to eq('2026/04/2026-04-23_10-00-05.log' => [default_stamp, marker, 'line 1', default_stamp])
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

        # R-31: sync is on, so a line is on disk while the logger still runs
        # (a crash or a reader such as pilepull.lic sees it at once).
        it 'has each line in the file while the logger is still waiting for the next one' do
          use_options(OpenStruct.new)
          LogSpecHarness.idle_timeout = 5
          LogSpecHarness.feed('line 1')
          logger = Thread.new { start_main }
          begin
            Timeout.timeout(2) { sleep 0.01 until logger.status == 'sleep' && find_log_file && File.size(find_log_file) > 0 && LogSpecHarness::DOWNSTREAM.num_waiting == 1 }

            on_disk = File.read(find_log_file).lines(chomp: true)
          ensure
            logger.kill
            logger.join(2)
          end

          expect(on_disk).to eq([default_stamp, marker, 'line 1'])
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

      # R-22: a close that failed logged a bare "Can't close file!", with
      # neither the file nor the error.
      context 'when the file cannot be closed' do
        it 'logs the file and the error to the Lich log and stops as it would have' do
          use_options(OpenStruct.new)
          allow(Lich).to receive(:log)
          LogSpecHarness.feed('line 1')
          allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
            original.call(*args, &block).tap do |file|
              next unless file.is_a?(File)

              allow(file).to receive(:close).and_wrap_original do |close|
                close.call
                raise IOError, 'device gone'
              end
            end
          end

          expect { run_main }.not_to raise_error

          expect(log_lines.drop(2)).to eq(['line 1', default_stamp])
          expect(Lich).to have_received(:log).with("log: closing the log file #{find_log_file} failed (IOError: device gone); lines are written as they come, with sync on, but the file may be missing its footer or a last write")
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
      # variable, and every run of log.lic in a session (;force log, or a
      # second run of a local logxml.lic shim) evaluates `module GameLogger`
      # again in the same namespace, so a run starting later could hand its
      # options to a run already going.
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
        # Script.current is per thread in lich-5, so the other run's arguments
        # are visible only while it evaluates the module; this run's are put
        # back after, and only state on the shared module can leak across.
        it "keeps this run's arguments when another run evaluates the module while this one starts" do
          start_script_with('--exclude=u1234', '--timestamp=%H:%M')
          LogSpecHarness.evaluate_game_logger
          another_run = lambda do
            start_script_with('--lines=5')
            LogSpecHarness.evaluate_game_logger
            start_script_with('--exclude=u1234', '--timestamp=%H:%M')
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

        # A regression guard, not an R-08 reproduction: it passes on 1.2.4 too,
        # because main has copied --exclude into a local when it starts since
        # 1.2.3. It goes red if main reads the module's options again for each
        # line, as 1.2.2 and earlier did. The second run is started on the
        # example's thread, with its own log folder, and reads no line; the
        # first keeps logging on its thread.
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

          expect(GameLogger::Logger.log_file_path(log_dir, time, '.log', rotated: false))
            .to eq(File.join(log_dir, '2026-04-23_10-00-05.log'))
        end

        it 'names a rotated file by the time when no file has that name' do
          expect(GameLogger::Logger.log_file_path(log_dir, time, '.xml', rotated: true))
            .to eq(File.join(log_dir, '2026-04-23_10-00-05.xml'))
        end

        it 'adds _01 to a rotated file whose name exists, and _02 when that exists too' do
          File.write(File.join(log_dir, '2026-04-23_10-00-05.log'), '')
          expect(GameLogger::Logger.log_file_path(log_dir, time, '.log', rotated: true))
            .to eq(File.join(log_dir, '2026-04-23_10-00-05_01.log'))

          File.write(File.join(log_dir, '2026-04-23_10-00-05_01.log'), '')
          expect(GameLogger::Logger.log_file_path(log_dir, time, '.log', rotated: true))
            .to eq(File.join(log_dir, '2026-04-23_10-00-05_02.log'))
        end

        it 'gives rotated names that sort by name in the order written, after the first file and before the next second' do
          names = ['2026-04-23_10-00-05.log']
          11.times do
            FileUtils.touch(File.join(log_dir, names.last))
            names << File.basename(GameLogger::Logger.log_file_path(log_dir, time, '.log', rotated: true))
          end
          names << '2026-04-23_10-00-06.log'

          expect(names.sort).to eq(names)
        end
      end

      describe '.write_footer' do
        let(:closed_file) { File.open(File.join(log_dir, 'closed.log'), 'a').tap(&:close) }

        it 'logs and ignores a write error while the logger stops' do
          allow(Lich).to receive(:log)

          expect(GameLogger::Logger.write_footer(closed_file, nil, stopping: true)).to be_nil
          expect(Lich).to have_received(:log).with(
            "log: the footer of #{closed_file.path} was not written while the logger stopped (IOError: closed stream)"
          )
        end

        it 'raises a write error when the logger is not stopping' do
          expect { GameLogger::Logger.write_footer(closed_file, nil, stopping: false) }.to raise_error(IOError)
        end
      end

      # R-28, Q-01, Q-08: XML mode is logxml.lic's format (the 0.6.6 file
      # bytes) inside log.lic, picked by --xml or by the script running as
      # logxml (an install's local logxml.lic, USER-1); the options and the
      # file handling are the ones text mode has.
      describe 'XML mode' do
        let(:marker) { '<!-- Above contents from reget; full logging now active -->' }
        # The first line of an XML file with timestamps off: 12-hour, no
        # seconds. The last line is the footer, the same as text mode's.
        let(:xml_header) { '2026-04-23 10:00am' }

        def xml_files
          Dir.glob(File.join(log_dir, '**', '*.xml'))
        end

        def xml_lines
          expect(xml_files.size).to eq(1)
          File.read(xml_files.first).lines(chomp: true)
        end

        it 'writes a .xml file with the 12-hour header and says XML logging started, with --xml' do
          use_options(GameLogger::Opts.parse(['--xml']))
          LogSpecHarness.feed('<output>You see a door.</output>')

          run_main

          expect(Dir.glob(File.join(log_dir, '**', '*.log'))).to eq([])
          expect(xml_files).to eq([File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.xml')])
          expect(xml_lines).to eq([xml_header, marker, '<output>You see a door.</output>', default_stamp])
          expect(LogSpecHarness.echoes).to eq(["XML Logging started, currently logging to #{xml_files.first}"])
        end

        it 'runs in XML mode without --xml when the script runs as logxml' do
          LogSpecHarness.start_script('', name: 'logxml')
          use_options(OpenStruct.new)
          LogSpecHarness.feed('<output>You see a door.</output>')

          run_main

          expect(xml_lines).to eq([xml_header, marker, '<output>You see a door.</output>', default_stamp])
        end

        it 'stays in text mode, and still drops stream lines, as log with the word streams but no --xml' do
          LogSpecHarness.start_script('streams', name: 'log')
          LogSpecHarness.feed('<pushStream id="inv"/>', 'You see a door.')

          run_main

          expect(xml_files).to eq([])
          expect(log_lines).to eq([default_stamp, marker, 'You see a door.', default_stamp])
        end

        it 'drops the hour\'s leading zero from the header, and keeps the footer\'s' do
          allow(Time).to receive(:now).and_return(Time.new(2026, 4, 23, 9, 5, 0))
          $login_time = Time.new(2026, 4, 23, 8, 0, 0)
          use_options(GameLogger::Opts.parse(['--xml']))

          run_main

          expect(xml_lines).to eq(['2026-04-23 9:05am', Time.new(2026, 4, 23, 9, 5, 0).strftime('%Y-%m-%d %H:%M:%S.%L %:z')])
        end

        it 'writes the header, footer and each line in the --timestamp format when one is given' do
          use_options(GameLogger::Opts.parse(['--xml', '--timestamp=%H:%M']))
          LogSpecHarness.feed('<output>You see a door.</output>')

          run_main

          expect(xml_lines).to eq(['10:00', marker, '10:00: <output>You see a door.</output>', '10:00'])
        end

        # lich-5 hands a script the XML lines with want_downstream_xml, adds
        # the text lines with want_downstream and other scripts' echoes with
        # want_script_output, and gives reget's raw XML only to a script that
        # already wants the XML downstream.
        it 'wants the XML downstream and typed commands only, set before reget is called' do
          flags_at_reget = nil
          allow(LogSpecHarness).to receive(:reget).and_wrap_original do |original|
            flags_at_reget = LogSpecHarness.script.to_h.slice(:want_downstream, :want_downstream_xml, :want_script_output, :want_upstream)
            original.call
          end
          use_options(GameLogger::Opts.parse(['--xml']))

          run_main

          expect(flags_at_reget).to eq(want_downstream: false, want_downstream_xml: true, want_script_output: false, want_upstream: true)
        end

        # Server lines verbatim from lich-5 spec/fixtures/streams/gs_saga_hunt.xml.
        it 'writes the reget as the raw XML the server sent, less the "\r", unstamped and unfiltered' do
          LogSpecHarness.server_buffer = [
            "<pushStream id=\"room\"/>Room text<popStream/>\r",
            "<compass><dir value=\"n\"/><dir value=\"e\"/></compass><prompt time=\"1792091316\">&gt;</prompt>\r",
            "<component id='room objs'>  You also see the <a exist=\"781927405\" noun=\"disk\">purple Aldric disk</a>.</component>\r"
          ]
          use_options(GameLogger::Opts.parse(['--xml', '--timestamp=%H:%M']))

          run_main

          expect(File.binread(xml_files.first)).not_to include("\r")
          expect(xml_lines).to eq(
            [
              '10:00',
              '<pushStream id="room"/>Room text<popStream/>',
              '<compass><dir value="n"/><dir value="e"/></compass><prompt time="1792091316">&gt;</prompt>',
              "<component id='room objs'>  You also see the <a exist=\"781927405\" noun=\"disk\">purple Aldric disk</a>.</component>",
              marker,
              '10:00'
            ]
          )
        end

        it 'logs a typed command whole, its <c> kept, between CLIENT comments' do
          use_options(GameLogger::Opts.parse(['--xml']))
          LogSpecHarness.wait_for_upstream!
          LogSpecHarness.type('<c>look')

          run_main

          expect(xml_lines).to eq([xml_header, marker, '<!-- CLIENT --><c>look<!-- ENDCLIENT -->', default_stamp])
        end

        # R-06, Q-10: without streams, XML mode leaves out the stream content
        # lich-5 keeps out of the main-window text it hands scripts
        # (lib/common/markup.rb SUPPRESSED_STREAMS and SPELLS_STREAM on
        # lich-5 main; lib/global_defs.rb strip_xml_simple at v5.21.0): a span
        # from a pushStream of the inv, talk, speech, spellfront, bounty,
        # society or reserve stream to the next popStream, followed across
        # lines, and a <stream id="Spells"> element. Every other byte of a
        # line is kept; a line left empty is not written. The base filter
        # dropped every line that started with pushStream or popStream (DR
        # prompts, speech and group lines after a popStream) and kept the
        # inner lines of a stream. Lines verbatim from lich-5
        # spec/fixtures/streams (file:line), less their line ends.
        describe 'stream content Lich keeps out of the main window' do
          def xml_body(*args)
            use_options(GameLogger::Opts.parse(['--xml', *args]))

            run_main

            xml_lines[2..-2]
          end

          it 'keeps the speech after a talk stream and leaves out the talk copy (dr_saga_containers_speech.xml:727-729)' do
            LogSpecHarness.feed(
              %(<pushStream id="talk"/><preset id='speech'>You politely say</preset>, "Hello."),
              %(<popStream/><preset id='speech'>You politely say</preset>, "Hello."),
              '<prompt time="1792040468">&gt;</prompt>'
            )

            expect(xml_body).to eq([%(<preset id='speech'>You politely say</preset>, "Hello."), '<prompt time="1792040468">&gt;</prompt>'])
          end

          it 'keeps a whisper stream, which Lich shows, and the prompt after its popStream (dr_saga_inventory.xml:281-283)' do
            whisper = [
              '<pushStream id="whispers"/><preset id="whisper">Delphine whispers,</preset> "Done!"',
              '<popStream/><preset id="whisper">Delphine whispers,</preset> "Done!"',
              '<prompt time="1792034225">&gt;</prompt>'
            ]
            LogSpecHarness.feed(whisper)

            expect(xml_body).to eq(whisper)
          end

          it 'keeps the group list and the prompt on its last popStream line (dr_saga_group_bank.xml:24-29)' do
            group = [
              "<clearStream id='group'/>",
              '<pushStream id="group"/>Members of your group:',
              '<popStream/><pushStream id="group"/>  You: Healthy.',
              '<popStream/><pushStream id="group"/>  Corwin (Leader): Healthy.',
              '<popStream/><pushStream id="group"/>There are 2 members in your group.',
              '<popStream/><prompt time="1792035856">J&gt;</prompt>'
            ]
            LogSpecHarness.feed(group)

            expect(xml_body).to eq(group)
          end

          it 'keeps a combat stream and the prompt after it (dr_saga_hunt.xml:8-10)' do
            combat = [
              '<pushStream id="combat" />* A jeol moradu slices an ice-edged sword at you.  You dodge.  ',
              "[You're winded (100%), mighty (100%), incredibly balanced and in dominating position.]",
              '<popStream id="combat" /><prompt time="1792034126">&gt;</prompt>'
            ]
            LogSpecHarness.feed(combat)

            expect(xml_body).to eq(combat)
          end

          it 'keeps a percWindow line and the prompt after its popStream (dr_legacy_group.xml:13-15)' do
            spells = ['<clearStream id="percWindow"/>', '<pushStream id="percWindow"/>Regenerate  (Indefinite)', '<popStream/><prompt time="1791327426">&gt;</prompt>']
            LogSpecHarness.feed(spells)

            expect(xml_body).to eq(spells)
          end

          it 'leaves out an inventory stream across lines and keeps the text around it (dr_saga_inventory.xml:87-88, 122-125)' do
            LogSpecHarness.feed(
              %(<right exist="195648338" noun="lootsack">cloth lootsack</right><clearStream id='inv' ifClosed=''/><pushStream id='inv'/>Your worn items are:),
              '  a <a exist="195648608" noun="helm">diacan lamellar helm sculpted with the visage of a Saendalen shark</a>',
              '  a <a exist="195648312" noun="harness">leaf-green leather harness with a smooth brass clasp</a>',
              '<popStream/>',
              'You remove a <a exist="195648338" noun="lootsack">heavy Imperial weave cloth lootsack</a> from your belt.',
              '<prompt time="1792034212">&gt;</prompt>'
            )

            expect(xml_body).to eq(
              [
                %(<right exist="195648338" noun="lootsack">cloth lootsack</right><clearStream id='inv' ifClosed=''/>),
                'You remove a <a exist="195648338" noun="lootsack">heavy Imperial weave cloth lootsack</a> from your belt.',
                '<prompt time="1792034212">&gt;</prompt>'
              ]
            )
          end

          it 'leaves out a GemStone inventory stream and keeps the room stream before it (gs_saga_login.xml:14-16, 37-38, 40)' do
            LogSpecHarness.feed(
              "<compDef id='sprite'></compDef><popStream id='room'/>",
              "<streamWindow id='inv' title='My Inventory' target='wear' ifClosed='' resident='true'/><clearStream id='inv' ifClosed=''/><pushStream id='inv'/>Your worn items are:",
              '  a <a exist="781962601" noun="bag">tooled leather drawstring coin bag</a>',
              '  a <a exist="781962517" noun="cloak">voluminous mist tartan cloak</a> lined in silver-tipped aquerne',
              '<popStream/>',
              "<dialogData id='combat'><progressBar id='pbarStance' value='100' text='defensive (100%)' top='51' width='130' height='16' left='0' align='n' tooltip='Percent of stance contributing to defense'/></dialogData>"
            )

            expect(xml_body).to eq(
              [
                "<compDef id='sprite'></compDef><popStream id='room'/>",
                "<streamWindow id='inv' title='My Inventory' target='wear' ifClosed='' resident='true'/><clearStream id='inv' ifClosed=''/>",
                "<dialogData id='combat'><progressBar id='pbarStance' value='100' text='defensive (100%)' top='51' width='130' height='16' left='0' align='n' tooltip='Percent of stance contributing to defense'/></dialogData>"
              ]
            )
          end

          it 'keeps the GemStone room stream (gs_saga_hunt.xml:17-20)' do
            room = [
              "<nav rm='4216015'/><streamWindow id='main' title='Story' subtitle=\" - Sanctum of Scales, Columns - 4216015\" location='center' target='drop'/>" \
              "<streamWindow id='room' title='Room' subtitle=\" - Sanctum of Scales, Columns - 4216015\" location='center' target='drop' ifClosed='' resident='true'/>" \
              "<clearStream id='room'/><pushStream id='room'/><compDef id='room desc'>Stark white columns stretch up toward curved glass domes in the ceiling, " \
              'each slender pillar adorned with rows of pale peridots and accents of bronze and copper leaf.  The floor is a mosaic of blue and green hues, ' \
              "the stones chiseled into the shape of a thick, shimmering scale.</compDef><compDef id='room objs'>  You also see" \
              '<crtrStatus exist="784142402" health="300" maxhealth="300" hostile="1"/><b> <pushBold/>a <a exist="784142402" noun="sentinel">lithe veiled sentinel</a>' \
              '<popBold/></b>.</compDef>',
              "<compDef id='room players'></compDef>",
              "<compDef id='room exits'>Obvious exits: <d>north</d>, <d>east</d>, <d>west</d></compDef>",
              "<compDef id='sprite'></compDef><popStream id='room'/>"
            ]
            LogSpecHarness.feed(room)

            expect(xml_body).to eq(room)
          end

          it 'leaves out the spell list lines and keeps the spell window set-up (gs_saga_login.xml:57-60)' do
            LogSpecHarness.feed(
              '<streamWindow id="Spells" title="Spells" ifClosed="" resident="true" scroll="manual"/>',
              '<clearStream id="Spells"/>',
              '<stream id="Spells"><a exist="-10700001" coord="2524,1871" noun="">Minor Elemental</a></stream>',
              '<stream id="Spells"><a exist="-10700001" coord="2524,1870" noun="">Major Elemental</a></stream>'
            )

            expect(xml_body).to eq(['<streamWindow id="Spells" title="Spells" ifClosed="" resident="true" scroll="manual"/>', '<clearStream id="Spells"/>'])
          end

          # Lines made up from the fixture forms, for the edges.
          it 'keeps the text between two spans on one line and after the second' do
            LogSpecHarness.feed(%(a<pushStream id="talk"/>x<popStream/>b<pushStream id='speech'/>y<popStream/>c))

            expect(xml_body).to eq(['abc'])
          end

          it 'ends a span at the first popStream, whatever stream it names, as Lich does' do
            LogSpecHarness.feed(%(<pushStream id="talk"/><pushStream id="combat" />x<popStream id="combat" />kept<popStream/>also kept))

            expect(xml_body).to eq(['kept<popStream/>also kept'])
          end

          it 'keeps a line that was empty as sent, and leaves out an empty line inside a span' do
            LogSpecHarness.feed('', "<pushStream id='inv'/>Your worn items are:", '', '<popStream/>', '')

            expect(xml_body).to eq(['', ''])
          end

          # Lich's strip drops a line it leaves blank (markup.rb strip_simple:
          # nil for /\A\s*\z/), so a line that loses stream content and has
          # only whitespace left is not written either.
          it 'leaves out a line left with only spaces' do
            LogSpecHarness.feed(%(  <pushStream id="talk"/>x<popStream/>), 'You see a door.')

            expect(xml_body).to eq(['You see a door.'])
          end

          # gs_saga_login.xml:38, 59 with whitespace after them (made up:
          # Lich hands get each line chomped, so no "\r" line end is left).
          it 'leaves out the popStream line that closes a span and a Spells line when only whitespace follows them' do
            LogSpecHarness.feed(
              "<pushStream id='inv'/>Your worn items are:",
              '  a <a exist="781962601" noun="bag">tooled leather drawstring coin bag</a>',
              '<popStream/>  ',
              %(<stream id="Spells"><a exist="-10700001" coord="2524,1871" noun="">Minor Elemental</a></stream>\t),
              'You see a door.'
            )

            expect(xml_body).to eq(['You see a door.'])
          end

          it 'leaves out each Spells element on a line and keeps the text between them' do
            LogSpecHarness.feed('<stream id="Spells">a</stream>MAIN<stream id="Spells">b</stream>')

            expect(xml_body).to eq(['MAIN'])
          end

          it 'leaves out a Spells element on a line that also opens a span' do
            LogSpecHarness.feed(%(<stream id="Spells">a</stream>kept<pushStream id='inv'/>x<popStream/>after))

            expect(xml_body).to eq(['keptafter'])
          end

          it 'keeps a line with only whitespace as sent, which loses no stream content' do
            LogSpecHarness.feed("  \r", "\t", 'You see a door.')
            xml_body

            expect(File.read(xml_files.first).lines[2..-2]).to eq(["  \r\n", "\t\n", "You see a door.\n"])
          end

          it 'keeps game text that shows a stream tag escaped' do
            spoof = %(You say, "&lt;pushStream id='inv'/&gt;")
            LogSpecHarness.feed(spoof, 'You see a door.')

            expect(xml_body).to eq([spoof, 'You see a door.'])
          end

          # The upstream thread pushes the typed command's line onto the same
          # buffer get reads, so it can come in the middle of a span.
          it 'logs a typed command that comes inside an inventory stream' do
            LogSpecHarness.feed("<pushStream id='inv'/>Your worn items are:", '<!-- CLIENT --><c>look<!-- ENDCLIENT -->', '  a gilded locus', '<popStream/>')

            expect(xml_body).to eq(['<!-- CLIENT --><c>look<!-- ENDCLIENT -->'])
          end

          it 'does not open a span for a typed command that holds a pushStream tag' do
            LogSpecHarness.feed(%(<!-- CLIENT -->say <pushStream id='inv'/><!-- ENDCLIENT -->), 'You see a door.')

            expect(xml_body).to eq([%(<!-- CLIENT -->say <pushStream id='inv'/><!-- ENDCLIENT -->), 'You see a door.'])
          end

          it 'does not close a span for a typed command that holds a popStream tag' do
            LogSpecHarness.feed("<pushStream id='inv'/>Your worn items are:", '<!-- CLIENT -->say <popStream/><!-- ENDCLIENT -->', '  a gilded locus', '<popStream/>after')

            expect(xml_body).to eq(['<!-- CLIENT -->say <popStream/><!-- ENDCLIENT -->', 'after'])
          end

          it "logs the upstream thread's notice inside a span, whatever name the logger runs as" do
            notice = '<!-- logxml: typed commands are not logged after this line; the upstream thread stopped (RuntimeError: <popStream/>) -->'
            LogSpecHarness.feed("<pushStream id='inv'/>Your worn items are:", notice, '  a gilded locus', '<popStream/>after')

            expect(xml_body).to eq([notice, 'after'])
          end

          # Only the logger's own two line forms are let through: a game line
          # that starts with a comment is filtered, so its popStream ends the
          # span and the lines after it are kept, as Lich keeps them; the
          # comment is inside the span, so it is left out. (Made up.)
          it 'ends a span at the popStream of a game line that starts with a comment' do
            LogSpecHarness.feed("<pushStream id='inv'/>Your worn items are:", '<!-- server note --><popStream/>main text', 'next main')

            expect(xml_body).to eq(['main text', 'next main'])
          end

          it 'counts only written lines toward --lines' do
            LogSpecHarness.feed("<pushStream id='inv'/>Your worn items are:", '  a gilded locus', '<popStream/>', '<output>line 1</output>')

            expect(xml_body('--lines=1')).to eq(['<output>line 1</output>'])
          end

          { 'the word streams' => 'streams', '--streams' => '--streams' }.each do |label, argument|
            it "keeps every line as sent with #{label}" do
              lines = ["<pushStream id='inv'/>Your worn items are:", '  a gilded locus', '<popStream/>', '<stream id="Spells">Minor Elemental</stream>']
              LogSpecHarness.feed(lines)

              expect(xml_body(argument)).to eq(lines)
            end
          end

          # The dialog and progress bar lines text mode drops stay in the XML log.
          it 'keeps a line that starts with a dialog tag, which text mode drops' do
            LogSpecHarness.feed("<dialogData id='minivitals'>", '</dialogData>')

            expect(xml_body).to eq(["<dialogData id='minivitals'>", '</dialogData>'])
          end
        end

        context 'with --rnum or --exclude' do
          let(:map) { double('Map', loaded?: true) }
          let(:title_line) { '<resource picture="0"/><style id="roomName" />[Town Square]' }

          before do
            stub_const('Map', map)
            allow(map).to receive(:ids_from_uid) { |uid| uid == 1234 ? [228] : [] }
          end

          it 'numbers the line that starts with the room name resource, the u-id right after the first ]' do
            use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
            LogSpecHarness.feed("#{title_line}</name><description>A fountain.</description>", '[Town Square]')

            run_main

            expect(xml_lines[2..-2]).to eq(
              ['<resource picture="0"/><style id="roomName" />[Town Square - 228] (u1234)</name><description>A fountain.</description>', '[Town Square]']
            )
          end

          # R-12, Q-05: one title decorator for both modes, so a GemStone title
          # that already shows the room's UID gets no second one in XML mode
          # either (logxml 0.6.6 wrote "(u1234) (1234)").
          it 'keeps the game-shown (1234) instead of adding a second u-id' do
            use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
            LogSpecHarness.feed("#{title_line} (1234)")

            run_main

            expect(xml_lines[2..-2]).to eq(['<resource picture="0"/><style id="roomName" />[Town Square - 228] (1234)'])
          end

          # R-17, Q-06: the room title line forms lich-5 numbers itself
          # (lib/games.rb process_room_information, lich-5 5de48c46 :1333):
          # an optional picture resource or popBold, then the roomName style
          # or the Saga-identity <room> block. Lines made up from that pattern.
          {
            'the roomName style with no picture resource'   => '<style id="roomName" />[Town Square]',
            'a popBold before the roomName style'           => '<popBold/><style id="roomName" />[Town Square]',
            'a Saga-identity <room> block'                  => '<resource picture="0"/><room><name>[Town Square]</name><description>A fountain.</description></room>',
            'a picture resource with a number other than 0' => '<resource picture="12"/><style id="roomName" />[Town Square]',
            'a tab before the roomName style\'s />'         => %(<resource picture="0"/><style id="roomName"\t/>[Town Square]),
            'two spaces before the roomName style\'s />'    => '<resource picture="0"/><style id="roomName"  />[Town Square]'
          }.each do |label, line|
            it "numbers #{label}, the u-id right after the first ]" do
              use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
              LogSpecHarness.feed(line)

              run_main

              expect(xml_lines[2..-2]).to eq([line.sub('[Town Square]', '[Town Square - 228] (u1234)')])
            end
          end

          # Lich's pattern takes the picture resource or popBold, not both,
          # so this form (which logxml 0.6.6 numbered) is left alone too.
          # Lich's pattern needs whitespace before the roomName style's "/>"
          # and a whole <room> tag, so neither of these lines is a title.
          {
            'the roomName style with no space before />' => '<resource picture="0"/><style id="roomName"/>[Town Square]',
            'a tag that only starts with <room'          => '<resource picture="0"/><roomDesc>[Town Square] lies here.</roomDesc>'
          }.each do |label, line|
            it "numbers no line with #{label}" do
              use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
              LogSpecHarness.feed(line)

              run_main

              expect(xml_lines[2..-2]).to eq([line])
            end
          end

          it 'numbers no title with both a picture resource and popBold before it' do
            use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
            both_line = '<resource picture="0"/><popBold/><style id="roomName" />[Town Square]'
            LogSpecHarness.feed(both_line)

            run_main

            expect(xml_lines[2..-2]).to eq([both_line])
          end

          # A familiar's view of its own room (Lich matches it too, with an
          # optional familiar pushStream first) is not the character's room,
          # so it is left alone, as logxml 0.6.6 left it. With streams on it
          # is written.
          it "numbers no familiar's room title line" do
            use_options(GameLogger::Opts.parse(['--xml', '--rnum', '--streams']))
            familiar_line = %(<pushStream id="familiar" ifClosedStyle="watching"/>#{title_line})
            LogSpecHarness.feed(familiar_line)

            run_main

            expect(xml_lines[2..-2]).to eq([familiar_line])
          end

          # R-06: the title test reads the line as sent, as Lich's own does,
          # before stream content is left out, so a title that a left-out
          # span comes before is not numbered, as Lich does not number it.
          # (Made-up line.)
          it 'numbers no title that comes after a left-out stream span on its line' do
            use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
            LogSpecHarness.feed(%(<pushStream id='inv'/>a torch<popStream/>#{title_line}))

            run_main

            expect(xml_lines[2..-2]).to eq([title_line])
          end

          # The title must start the line: a "]" before it would take the
          # numbers.
          it 'numbers no line where the room name comes after a line break' do
            use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
            broken_line = "<output>[ok]</output>\n#{title_line}"
            LogSpecHarness.feed(broken_line)

            run_main

            expect(xml_lines[2..-2]).to eq(["<output>[ok]</output>", title_line])
          end

          # Server lines verbatim from lich-5 spec/fixtures/streams.
          context 'with the title lines the game sends' do
            let(:room_uid) { 4_216_015 }

            before do
              allow(XMLData).to receive(:room_id) { room_uid }
              allow(map).to receive(:ids_from_uid) { |uid| { 4_216_015 => [228], 4_217_403 => [5050], 4_217_404 => [5051] }.fetch(uid, []) }
            end

            # gs_saga_hunt.xml:23
            let(:gs_title) { '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns] (4216015)' }

            it 'keeps the game-shown (4216015) in GemStone (gs_saga_hunt.xml:23)' do
              use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
              LogSpecHarness.feed(gs_title)

              run_main

              expect(xml_lines[2..-2]).to eq(['<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns - 228] (4216015)'])
            end

            it 'leaves the GemStone title as sent when the room has no Lich number' do
              allow(map).to receive(:ids_from_uid).and_return([])
              use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
              LogSpecHarness.feed(gs_title)

              run_main

              expect(xml_lines[2..-2]).to eq([gs_title])
            end

            # The logger reads XMLData when it handles a line, not when the
            # line came in, so after quick moves the parser can be on the
            # next room while the line is still this one's title. A title
            # that shows a UID other than the parser's is left as sent, as
            # text mode leaves a title that does not match the parser's.
            it "numbers no title that shows another room's UID, the parser being a room ahead" do
              allow(XMLData).to receive(:room_id).and_return(4_217_403)
              use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
              LogSpecHarness.feed(gs_title)

              run_main

              expect(xml_lines[2..-2]).to eq([gs_title])
            end

            # The UID must be this room's whole number: one digit more is
            # another room.
            it "numbers no title that shows this room's UID with one digit more" do
              use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
              LogSpecHarness.feed(gs_title.sub('(4216015)', '(42160151)'))

              run_main

              expect(xml_lines[2..-2]).to eq([gs_title.sub('(4216015)', '(42160151)')])
            end

            context 'in DragonRealms' do
              let(:room_uid) { 4_217_403 }
              # dr_saga_hunt.xml:944, cut after </description> (the rest of
              # the 3,315-byte line is the room's objects and exits).
              let(:saga_title) do
                '<resource picture="0"/><room><name>[Jeol\'gelvmoraen, Ice Grottos] (4217403)</name><description>Curiously mummified ' \
                  'creatures, contorted into odd postures by the slow movement of the ice, rest beneath the surface of the walls and floor.  ' \
                  'Their baleful eyes gaze blankly from behind the faceted flow, almost pleading for release from their frigid tombs.  A ' \
                  'tracery of faint cracks emanates from beneath a twisted stone that has fallen from the ceiling; an oval of tortuous white ' \
                  'imperfections marks the collision, stark upon a sea of blue ice.</description>'
              end

              before { allow(XMLData).to receive(:game).and_return('DR') }

              it 'numbers the Saga-identity <room><name> title, with no u-id (dr_saga_hunt.xml:944)' do
                use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
                LogSpecHarness.feed(saga_title)

                run_main

                expect(xml_lines[2..-2]).to eq([saga_title.sub('Ice Grottos]', 'Ice Grottos - 5050]')])
                expect(xml_lines[2]).to start_with('<resource picture="0"/><room><name>[Jeol\'gelvmoraen, Ice Grottos - 5050] (4217403)</name>')
              end

              # dr_legacy_hunt.xml:1435
              it 'still numbers the legacy roomName title (dr_legacy_hunt.xml:1435)' do
                allow(XMLData).to receive(:room_id).and_return(4_217_404)
                use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
                LogSpecHarness.feed('<resource picture="0"/><style id="roomName" />[Jeol\'gelvmoraen, Ice Grottos] (4217404)')

                run_main

                expect(xml_lines[2..-2]).to eq(['<resource picture="0"/><style id="roomName" />[Jeol\'gelvmoraen, Ice Grottos - 5051] (4217404)'])
              end

              it 'numbers no <room> block that comes after other text' do
                use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
                LogSpecHarness.feed("<output>See </output>#{saga_title}")

                run_main

                expect(xml_lines[2..-2]).to eq(["<output>See </output>#{saga_title}"])
              end
            end
          end

          it 'numbers no line where the room name resource comes after other text' do
            use_options(GameLogger::Opts.parse(['--xml', '--rnum']))
            mid_line = "<output>See </output>#{title_line} (1234)"
            LogSpecHarness.feed(mid_line)

            run_main

            expect(xml_lines[2..-2]).to eq([mid_line])
          end

          it 'numbers no line with --exclude and without --rnum' do
            use_options(GameLogger::Opts.parse(['--xml', '--exclude=u7199']))
            LogSpecHarness.feed(title_line)

            run_main

            expect(xml_lines[2..-2]).to eq([title_line])
          end

          it 'turns --rnum on only for the whole option, not for --rnumber' do
            use_options(GameLogger::Opts.parse(['--xml', '--rnumber']))
            LogSpecHarness.feed(title_line)

            run_main

            expect(xml_lines[2..-2]).to eq([title_line])
            expect(map).not_to have_received(:ids_from_uid)
          end

          it 'skips the lines read in an --exclude room' do
            use_options(GameLogger::Opts.parse(['--xml', '--exclude=u1234']))
            LogSpecHarness.feed('<output>in room 1234</output>')

            run_main

            expect(xml_lines).to eq([xml_header, marker, default_stamp])
          end

          it 'skips the lines read in a room excluded by its Lich number' do
            use_options(GameLogger::Opts.parse(['--xml', '--exclude=228']))
            LogSpecHarness.feed('<output>in room 228</output>')

            run_main

            expect(xml_lines).to eq([xml_header, marker, default_stamp])
          end
        end

        it 'starts a new .xml file after --lines written lines, with the XML header' do
          use_options(GameLogger::Opts.parse(['--xml', '--lines=1']))
          LogSpecHarness.feed('<output>line 1</output>', '<output>line 2</output>')

          run_main

          month = File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04')
          expect(Dir.children(month).sort).to eq(['2026-04-23_10-00-05.xml', '2026-04-23_10-00-05_01.xml'])
          expect(File.read(File.join(month, '2026-04-23_10-00-05_01.xml')).lines(chomp: true))
            .to eq([xml_header, '<output>line 2</output>', default_stamp])
        end

        context 'when the upstream thread stops on an error, run as logxml' do
          it 'starts the notice line and the restart hint with logxml' do
            LogSpecHarness.start_script('streams', name: 'logxml')
            calls = 0
            allow(LogSpecHarness).to receive(:upstream_get) do
              calls += 1
              raise RuntimeError, 'boom' if calls > 1

              '<c>look'
            end
            LogSpecHarness.wait_for_upstream!
            use_options(GameLogger::Opts.parse)

            run_main

            expect(xml_lines.last(3)).to eq(
              [
                '<!-- CLIENT --><c>look<!-- ENDCLIENT -->',
                '<!-- logxml: typed commands are not logged after this line; the upstream thread stopped (RuntimeError: boom) -->',
                default_stamp
              ]
            )
            expect(LogSpecHarness.echoes.grep(/\Atyped commands/).first).to end_with('(;kill logxml, then ;logxml streams) to log typed commands again.')
          end
        end

        it 'names logxml in the Lich log when the file cannot be closed, run as logxml' do
          LogSpecHarness.start_script('', name: 'logxml')
          logged = []
          allow(Lich).to receive(:log) { |msg| logged << msg }
          allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
            original.call(*args, &block).tap do |file|
              next unless file.is_a?(File)

              allow(file).to receive(:close).and_wrap_original do |close|
                close.call
                raise IOError, 'device gone'
              end
            end
          end
          use_options(OpenStruct.new)

          run_main

          expect(logged).to eq(["logxml: closing the log file #{xml_files.first} failed (IOError: device gone); lines are written as they come, with sync on, but the file may be missing its footer or a last write"])
        end

        it 'runs in XML mode when the whole script runs with --xml' do
          LogSpecHarness.start_script('--xml --timestamp=%H:%M')
          LogSpecHarness.feed('<output>You see a door.</output>')

          Timeout.timeout(5) { LogSpecHarness.run_whole_script }

          expect(xml_lines).to eq(['10:00', marker, '10:00: <output>You see a door.</output>', '10:00'])
          expect(LogSpecHarness.script.want_downstream_xml).to be(true)
        end
      end

      context 'log file header/footer format' do
        it 'uses --timestamp format for header when enabled' do
          use_options(OpenStruct.new(timestamp: '%F %T %Z'))
          run_main
          header_line = log_content.lines.first.chomp
          expect(header_line).to eq(frozen_time.strftime('%F %T %Z'))
        end

        it 'uses default format for header when timestamps disabled' do
          use_options(OpenStruct.new)
          run_main
          header_line = log_content.lines.first.chomp
          expect(header_line).to eq(frozen_time.strftime("%Y-%m-%d %H:%M:%S.%L %:z"))
        end
      end
    end

    # R-29: one run is a GameLogger::Logger, whose clock and Lich helpers
    # (get, reget, echo, get_settings) can be handed in instead of stubbed.
    describe 'GameLogger::Logger' do
      let(:log_dir) { Dir.mktmpdir }
      let(:marker) { '<!-- Above contents from reget; full logging now active -->' }

      # A clock that always answers the same time.
      let(:clock) do
        time = Time.new(2026, 7, 1, 8, 30, 0)
        Object.new.tap { |fake| fake.define_singleton_method(:now) { time } }
      end

      # Lich's script helpers as public methods: get answers the given lines,
      # then raises StopIteration, which ends the run's loop.
      let(:io_class) do
        Class.new do
          attr_reader :echoes, :gets

          def initialize(lines, reget: nil, settings: OpenStruct.new)
            @lines = lines.dup
            @reget = reget
            @settings = settings
            @echoes = []
            @gets = 0
          end

          def get
            @gets += 1
            @lines.shift || raise(StopIteration)
          end

          attr_reader :reget

          def echo(msg) = @echoes << msg
          def get_settings = @settings
        end
      end

      before do
        stub_const('LICH_DIR', log_dir)
        hide_const('LOG_DIR')
      end

      after do
        FileUtils.rm_rf(log_dir)
      end

      def file_at(relative)
        File.join(log_dir, 'logs', 'GSIV-TestChar', relative)
      end

      it 'names, dates and stamps the file by the clock it is given, not Time.now' do
        $login_time = Time.new(2026, 7, 1, 8, 29, 50)
        io = io_class.new(['line 1'], reget: ["a reget line\r"],
                                      settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))
        logger = GameLogger::Logger.new(GameLogger::Opts.parse([]), clock: clock, io: io)

        Timeout.timeout(5) { logger.run }

        path = file_at('2026/07/2026-07-01_08-30-00.log')
        # The reget line has the login time ($login_time), not the clock's.
        expect(File.read(path).lines(chomp: true)).to eq(['08:30', '08:29: a reget line', marker, '08:30: line 1', '08:30'])
        expect(io.echoes).to eq(["Non-XML Logging started, currently logging to #{path}"])
        expect(io.gets).to eq(2)
      end

      it 'writes no reget when the clock is 30 seconds past login' do
        $login_time = Time.new(2026, 7, 1, 8, 29, 30)
        io = io_class.new(['line 1'], reget: ['a reget line'])

        Timeout.timeout(5) { GameLogger::Logger.new(GameLogger::Opts.parse([]), clock: clock, io: io).run }

        stamp = "2026-07-01 08:30:00.000 #{clock.now.strftime('%:z')}"
        expect(File.read(file_at('2026/07/2026-07-01_08-30-00.log')).lines(chomp: true)).to eq([stamp, 'line 1', stamp])
      end

      # Every field the run reads from its Mode, with values Mode::TEXT does
      # not have, so a run that used text mode's values instead would fail.
      it "writes the file and lines as the mode it is given makes them" do
        $login_time = Time.new(2026, 1, 1)
        mode = GameLogger::Mode::TEXT.with(
          extension: '.txt',
          header_stamp: ->(time) { "hdr #{time.strftime('%H:%M')}" },
          upstream_line: ->(command) { "!#{command}" },
          started_text: 'Test logging to',
          script_flags: { want_upstream: true }
        )
        LogSpecHarness.feed('line 1')
        LogSpecHarness.type('look')
        LogSpecHarness.wait_for_upstream!

        Timeout.timeout(5) { GameLogger::Logger.new(GameLogger::Opts.parse([]), mode: mode, clock: clock).run }

        path = file_at('2026/07/2026-07-01_08-30-00.txt')
        expect(Dir[file_at('2026/07/*')]).to eq([path])
        expect(File.read(path).lines(chomp: true))
          .to eq(['hdr 08:30', 'line 1', '!look', "2026-07-01 08:30:00.000 #{clock.now.strftime('%:z')}"])
        expect(LogSpecHarness.echoes).to eq(["Test logging to #{path}"])
        expect(Script.current.want_upstream).to be(true)
        expect(Script.current.want_script_output).to be(false)
      end

      # want_script_output decides whether Lich hands the logger its own
      # echoes, so it is set before the options are read and may echo.
      it 'sets the script flags before the --timestamp warning is echoed' do
        $login_time = Time.new(2026, 1, 1)
        flags_at_echo = []
        allow(GameLogger).to receive(:echo).and_wrap_original do |original, msg|
          flags_at_echo << Script.current.want_script_output
          original.call(msg)
        end

        Timeout.timeout(5) { GameLogger::Logger.new(GameLogger::Opts.parse(['--timestamp']), clock: clock, io: io_class.new([])).run }

        expect(LogSpecHarness.echoes.first).to start_with('timestamp was given without a format')
        expect(flags_at_echo).to eq([true])
      end

      # A mode's header_stamp (Mode::TEXT has none) makes the header line
      # when timestamps are off; the footer keeps the default stamp.
      describe '.with_log_file with a header_stamp' do
        let(:path) { File.join(log_dir, 'header.log') }
        let(:header_stamp) { ->(time) { "header at #{time.strftime('%H:%M')}" } }

        it 'writes the header_stamp line as the header when timestamps are off' do
          GameLogger::Logger.with_log_file(path, nil, clock: clock, header_stamp: header_stamp) { |file| file.puts 'line 1' }

          expect(File.read(path).lines(chomp: true))
            .to eq(['header at 08:30', 'line 1', "2026-07-01 08:30:00.000 #{clock.now.strftime('%:z')}"])
        end

        it 'writes the timestamp format as the header when timestamps are on' do
          GameLogger::Logger.with_log_file(path, '%T', clock: clock, header_stamp: header_stamp) { |file| file.puts 'line 1' }

          expect(File.read(path).lines(chomp: true)).to eq(['08:30:00', 'line 1', '08:30:00'])
        end
      end

      # R-28, Q-01: which Mode a run gets.
      describe '.log_label' do
        it 'is the name the script runs as' do
          LogSpecHarness.start_script('', name: 'logxml')

          expect(GameLogger::Logger.log_label).to eq('logxml')
        end

        it 'is log when there is no current script' do
          allow(LogSpecHarness).to receive(:script).and_return(nil)

          expect(GameLogger::Logger.log_label).to eq('log')
        end
      end

      describe '.mode_for' do
        {
          'text mode for log with no options'                 => [[], 'log', :DEFAULT_MODE],
          'XML mode for --xml'                                => [['--xml'], 'log', :XML_MODE],
          'XML mode for the word xml'                         => [['xml'], 'log', :XML_MODE],
          'XML mode for logxml with no options'               => [[], 'logxml', :XML_MODE],
          'XML mode keeping streams for logxml streams'       => [['streams'], 'logxml', :XML_STREAMS_MODE],
          'XML mode keeping streams for --xml --streams'      => [['--xml', '--streams'], 'log', :XML_STREAMS_MODE],
          'text mode for log streams (no --xml)'              => [['streams'], 'log', :DEFAULT_MODE],
          'text mode for a name that only starts with logxml' => [[], 'logxml2', :DEFAULT_MODE],
          'text mode with no script name'                     => [[], nil, :DEFAULT_MODE]
        }.each do |label, (args, name, expected)|
          it "picks #{label}" do
            mode = GameLogger::Logger.mode_for(GameLogger::Opts.parse(args), name)

            expect(mode).to equal(GameLogger::Logger.const_get(expected))
          end
        end

        it "gives the modes of this evaluation's Mode" do
          expect(GameLogger::Logger::XML_MODE).to equal(GameLogger::Mode::XML)
          expect(GameLogger::Logger::XML_STREAMS_MODE).to equal(GameLogger::Mode::XML_STREAMS)
        end
      end

      describe 'Mode::XML' do
        let(:mode) { GameLogger::Mode::XML }

        it "is a frozen value with logxml's file extension, typed command line and flags" do
          expect(mode).to be_frozen
          expect(mode.extension).to eq('.xml')
          expect(mode.started_text).to eq('XML Logging started, currently logging to')
          expect(mode.upstream_line.call('<c>look')).to eq('<!-- CLIENT --><c>look<!-- ENDCLIENT -->')
          expect(mode.script_flags).to be_frozen
          expect(mode.script_flags).to eq(want_script_output: false, want_upstream: true, want_downstream: false, want_downstream_xml: true)
        end

        # Only the hour's leading zero goes, never a zero in the date or minutes.
        {
          'a morning hour before 10' => [Time.new(2026, 4, 23, 9, 5, 0), '2026-04-23 9:05am'],
          'an evening hour'          => [Time.new(2026, 4, 23, 21, 7, 0), '2026-04-23 9:07pm'],
          'midnight'                 => [Time.new(2026, 4, 24, 0, 0, 1), '2026-04-24 12:00am'],
          'an hour of 10'            => [Time.new(2026, 10, 5, 10, 30, 0), '2026-10-05 10:30am'],
          'the first hour of a year' => [Time.new(2026, 1, 1, 1, 0, 0), '2026-01-01 1:00am']
        }.each do |label, (time, header)|
          it "writes the header for #{label} as #{header.inspect}" do
            expect(mode.header_stamp.call(time)).to eq(header)
          end
        end

        it 'writes reget lines as they come, less the "\r", without a stamp' do
          expect(mode.reget_line.call("<prompt time=\"1\">&gt;</prompt>\r", '%T', Time.new(2026, 1, 1))).to eq('<prompt time="1">&gt;</prompt>')
        end

        # R-12: the markup after the title ("</name>" in a <room> block)
        # stays after the u-id; text mode appends it to the line.
        it 'puts the u-id right after the title, where text mode appends it' do
          expect(mode.uid_after_title).to be(true)
          expect(GameLogger::Mode::TEXT.uid_after_title).to be(false)
        end

        it 'keeps every line as sent with streams' do
          filter = GameLogger::Mode::XML_STREAMS.line_filter.call

          expect(["<pushStream id='inv'/>Your worn items are:", '  a gilded locus'].map { |line| filter.call(line) })
            .to eq(["<pushStream id='inv'/>Your worn items are:", '  a gilded locus'])
        end

        # R-06: the filter follows a span across lines, so each run needs a
        # filter of its own (two XML runs, ;log --xml and ;force log --xml,
        # read the same lines).
        it 'builds a new filter for each run, so a span one run is in does not hide lines from another' do
          first = mode.line_filter.call
          second = mode.line_filter.call

          first.call("<pushStream id='inv'/>Your worn items are:")

          expect(first.call('  a gilded locus')).to be_nil
          expect(second.call('  a gilded locus')).to eq('  a gilded locus')
        end
      end

      describe '#format_line' do
        it 'returns the line as it is without a timestamp format' do
          logger = GameLogger::Logger.new(OpenStruct.new)

          expect(logger.format_line('You see a rat.', Time.new(2026, 7, 1, 8, 30, 0))).to eq('You see a rat.')
        end

        it "stamps the line with the given time in the run's --timestamp format" do
          $login_time = Time.new(2026, 1, 1)
          logger = GameLogger::Logger.new(GameLogger::Opts.parse(['--timestamp=%H:%M:%S']), clock: clock, io: io_class.new([]))
          Timeout.timeout(5) { logger.run }

          expect(logger.format_line('You see a rat.', Time.new(2026, 7, 1, 23, 59, 58))).to eq('23:59:58: You see a rat.')
        end
      end

      describe '#line_text' do
        # Text mode drops a whole line that starts with one of these tags
        # and keeps every other line as it is.
        {
          'a pushStream line'                   => ['<pushStream id="inv"/>', nil],
          'a popStream line'                    => ['<popStream/>You see a rat.', nil],
          'a closing progressBar line'          => ['</progressBar>', nil],
          'a dialogData line'                   => ['<dialogData id="minivitals">', nil],
          'an openDialog line'                  => ['<openDialog id="x">', nil],
          'a game line'                         => ['You see a rat.', 'You see a rat.'],
          'a line with the tag after its start' => ['You say, "<pushStream id=inv/>"', 'You say, "<pushStream id=inv/>"'],
          'an empty line'                       => ['', '']
        }.each do |label, (line, text)|
          it "is #{text.inspect} for #{label} in text mode" do
            expect(GameLogger::Logger.new(OpenStruct.new).line_text(line)).to eq(text)
          end
        end

        it 'returns the line itself when the filter keeps all of it' do
          line = 'You see a rat.'

          expect(GameLogger::Logger.new(OpenStruct.new, mode: GameLogger::Mode::XML).line_text(line)).to equal(line)
        end

        # R-06, XML mode: lines verbatim from lich-5
        # spec/fixtures/streams/dr_saga_inventory.xml:87-88, 123-124, read in order.
        it 'follows an inventory stream across lines in XML mode' do
          logger = GameLogger::Logger.new(OpenStruct.new, mode: GameLogger::Mode::XML)
          lines = [
            %(<right exist="195648338" noun="lootsack">cloth lootsack</right><clearStream id='inv' ifClosed=''/><pushStream id='inv'/>Your worn items are:),
            '  a <a exist="195648608" noun="helm">diacan lamellar helm sculpted with the visage of a Saendalen shark</a>',
            '<popStream/>',
            'You remove a <a exist="195648338" noun="lootsack">heavy Imperial weave cloth lootsack</a> from your belt.'
          ]

          expect(lines.map { |line| logger.line_text(line) }).to eq(
            [
              %(<right exist="195648338" noun="lootsack">cloth lootsack</right><clearStream id='inv' ifClosed=''/>),
              nil,
              nil,
              'You remove a <a exist="195648338" noun="lootsack">heavy Imperial weave cloth lootsack</a> from your belt.'
            ]
          )
        end

        # Each stream id lich-5 keeps out of the main-window text, in both
        # quote styles the game sends; a stream it shows stays.
        %w[spellfront inv bounty society reserve speech talk].each do |id|
          ["'", '"'].each do |quote|
            it "leaves out the #{id} stream with #{quote == "'" ? 'single' : 'double'} quotes in XML mode" do
              logger = GameLogger::Logger.new(OpenStruct.new, mode: GameLogger::Mode::XML)

              expect(logger.line_text("a<pushStream id=#{quote}#{id}#{quote}/>x<popStream/>b")).to eq('ab')
            end
          end
        end

        # The game also sends a space or more attributes before "/>" (DR
        # combat: <pushStream id="combat" />).
        {
          'a space before />' => %(a<pushStream id="talk" />x<popStream/>b),
          'another attribute' => %(a<pushStream id='inv' ifClosed=''/>x<popStream/>b)
        }.each do |label, line|
          it "leaves out a span whose pushStream has #{label} in XML mode" do
            logger = GameLogger::Logger.new(OpenStruct.new, mode: GameLogger::Mode::XML)

            expect(logger.line_text(line)).to eq('ab')
          end
        end

        %w[combat assess percWindow atmospherics group whispers familiar thoughts room experience loot].each do |id|
          it "keeps the #{id} stream in XML mode" do
            logger = GameLogger::Logger.new(OpenStruct.new, mode: GameLogger::Mode::XML)
            line = %(a<pushStream id="#{id}"/>x<popStream/>b)

            expect(logger.line_text(line)).to eq(line)
          end
        end

        it 'keeps a stream whose id only starts with one it leaves out (inventory) in XML mode' do
          logger = GameLogger::Logger.new(OpenStruct.new, mode: GameLogger::Mode::XML)
          line = %(a<pushStream id="inventory"/>x<popStream/>b)

          expect(logger.line_text(line)).to eq(line)
        end

        # Game lines reach a script as binary Strings, high bytes and all.
        it 'keeps the high bytes of a line and leaves out the span in it in XML mode' do
          logger = GameLogger::Logger.new(OpenStruct.new, mode: GameLogger::Mode::XML)
          e_acute = [0xc3, 0xa9].pack('C*')
          high_byte = [0xff].pack('C')

          expect(logger.line_text("caf#{e_acute} <pushStream id='talk'/>#{high_byte}<popStream/>!".b)).to eq("caf#{e_acute} !".b)
        end

        # A line Lich tagged UTF-8 with a byte that is not valid UTF-8 must
        # not raise in the regexp match.
        it 'leaves out the span in a line with an invalid UTF-8 byte in XML mode' do
          logger = GameLogger::Logger.new(OpenStruct.new, mode: GameLogger::Mode::XML)
          line = "a<pushStream id='talk'/>#{[0xff].pack('C')}<popStream/>b".b.force_encoding(Encoding::UTF_8)

          expect(logger.line_text(line)).to eq('ab')
        end
      end

      describe '#reget_lines' do
        it 'removes the "\\r" line ends and stamps nothing without a timestamp format' do
          logger = GameLogger::Logger.new(OpenStruct.new)

          expect(logger.reget_lines(["line 1\r", 'line 2'], Time.new(2026, 7, 1))).to eq(['line 1', 'line 2'])
        end

        it 'gives no lines for an empty reget (nil)' do
          expect(GameLogger::Logger.new(OpenStruct.new).reget_lines(nil, Time.new(2026, 7, 1))).to eq([])
        end
      end

      # R-12, Q-05: the one room title decorator both modes use.
      describe '.number_room_title' do
        {
          'GemStone, a Lich number, the UID shown'     => [['[Town Square] (1234)', 228, 'GSIV'], '[Town Square - 228] (1234)'],
          'GemStone, no Lich number, the UID shown'    => [['[Town Square] (1234)', nil, 'GSIV'], '[Town Square] (1234)'],
          'GemStone, a Lich number, no UID shown'      => [['[Town Square]', 228, 'GSIV'], '[Town Square - 228] (u1234)'],
          'GemStone, another room\'s UID shown'        => [['[Town Square] (12345)', 228, 'GSIV'], '[Town Square] (12345)'],
          'GemStone, the UID shown with no space'      => [['[Town Square](1234)', 228, 'GSIV'], '[Town Square - 228](1234) (u1234)'],
          'GemStone, markup after the title'           => [['[Town Square]</name>', 228, 'GSIV'], '[Town Square - 228]</name> (u1234)'],
          'GemStone, a second ] on the line'           => [['[Town Square] [lit]', nil, 'GSIV'], '[Town Square] [lit] (u1234)'],
          'DragonRealms, a Lich number, the UID shown' => [['[Town Square] (1234)', 228, 'DR'], '[Town Square - 228] (1234)'],
          'DragonRealms, another room\'s UID shown'    => [['[Town Square] (230008)', 228, 'DR'], '[Town Square] (230008)'],
          'DragonRealms, no Lich number, no UID shown' => [['[Town Square]', nil, 'DR'], '[Town Square]']
        }.each do |label, ((line, lich_id, game), numbered)|
          it "numbers the title as text mode does (any u-id at the end of the line) in #{label}" do
            expect(GameLogger::Logger.number_room_title(line, lich_id, 1234, game)).to eq(numbered)
          end
        end

        {
          'GemStone, a Lich number, no UID shown' => [['[Town Square]</name>', 228, 'GSIV'], '[Town Square - 228] (u1234)</name>'],
          'GemStone, the UID shown'               => [['[Town Square] (1234)</name>', 228, 'GSIV'], '[Town Square - 228] (1234)</name>'],
          'GemStone, a second ] on the line'      => [['[Town Square] [lit]', nil, 'GSIV'], '[Town Square] (u1234) [lit]'],
          'GemStone, another room\'s UID shown'   => [['[Town Square] (12345)</name>', 228, 'GSIV'], '[Town Square] (12345)</name>'],
          'DragonRealms'                          => [['[Town Square] (1234)</name>', 228, 'DR'], '[Town Square - 228] (1234)</name>']
        }.each do |label, ((line, lich_id, game), numbered)|
          it "numbers the title as XML mode does (any u-id right after the first ]) in #{label}" do
            expect(GameLogger::Logger.number_room_title(line, lich_id, 1234, game, uid_after_title: true)).to eq(numbered)
          end
        end

        # Lich's room display shows a UID of 0 or above 4294967296 as
        # "unknown" (lich-5 lib/games.rb); no " (u0)" is made up for it.
        {
          'an unknown UID of 0'    => [0, '[Town Square - 228]'],
          'a UID above 4294967296' => [4_294_967_297, '[Town Square - 228]'],
          'the highest known UID'  => [4_294_967_296, '[Town Square - 228] (u4294967296)'],
          'the lowest known UID'   => [1, '[Town Square - 228] (u1)'],
          'no UID at all (nil)'    => [nil, '[Town Square - 228]']
        }.each do |label, (uid, numbered)|
          it "adds a GemStone u-id only for a known UID, in both modes: #{label}" do
            expect(GameLogger::Logger.number_room_title('[Town Square]', 228, uid, 'GSIV')).to eq(numbered)
            expect(GameLogger::Logger.number_room_title('[Town Square]', 228, uid, 'GSIV', uid_after_title: true)).to eq(numbered)
          end
        end

        # With the room's UID unknown, a UID the title shows is another
        # room's as far as the logger can tell.
        [0, nil, 340_282_366_920_938_463_463_374_607_431_768_211_455].each do |uid|
          it "returns a title that shows a UID as it is when the room's UID is #{uid.inspect}" do
            line = '[Town Square] (1234)'

            expect(GameLogger::Logger.number_room_title(line, 228, uid, 'GSIV')).to equal(line)
          end
        end

        # A line tagged UTF-8 whose bytes are not valid UTF-8 would raise
        # ArgumentError on a Regexp match; the shown UID is read from its
        # bytes instead.
        it 'reads the shown UID from a line whose bytes are not valid in its encoding' do
          high_byte = [0xff].pack('C')
          line = "[Caf#{high_byte}] (1234)".b.force_encoding(Encoding::UTF_8)

          expect(GameLogger::Logger.number_room_title(line, 228, 1234, 'GSIV').b).to eq("[Caf#{high_byte} - 228] (1234)".b)
          expect(GameLogger::Logger.number_room_title(line, 228, 4321, 'GSIV')).to equal(line)
        end

        it 'never changes the line it is given' do
          line = +'[Town Square]'

          GameLogger::Logger.number_room_title(line, 228, 1234, 'GSIV', uid_after_title: true)

          expect(line).to eq('[Town Square]')
        end

        it 'returns the line itself when there is nothing to add' do
          line = '[Town Square] (1234)'

          expect(GameLogger::Logger.number_room_title(line, nil, 1234, 'GSIV', uid_after_title: true)).to equal(line)
        end
      end

      describe '#decorate_title' do
        it 'returns the line itself before any room title matcher is set' do
          line = '[Town Square]'

          expect(GameLogger::Logger.new(OpenStruct.new).decorate_title(line)).to equal(line)
        end
      end

      context 'when another run evaluates the module' do
        it 'replaces Logger, Mode and Mode::TEXT without a constant warning' do
          logger_class = GameLogger::Logger
          mode_class = GameLogger::Mode
          text_mode = GameLogger::Mode::TEXT

          expect { LogSpecHarness.evaluate_game_logger }.not_to output.to_stderr

          expect(GameLogger::Logger).not_to equal(logger_class)
          expect(GameLogger::Mode).not_to equal(mode_class)
          expect(GameLogger::Mode::TEXT).not_to equal(text_mode)
        end

        it 'names the new classes as the constants they are set to, with their own default mode' do
          LogSpecHarness.evaluate_game_logger

          expect(GameLogger::Logger.name).to eq('LogSpecHarness::Env::GameLogger::Logger')
          expect(GameLogger::Mode.name).to eq('LogSpecHarness::Env::GameLogger::Mode')
          expect(GameLogger::Logger::DEFAULT_MODE).to equal(GameLogger::Mode::TEXT)
        end

        # A run starting on another thread (;force log racing a start) can
        # read these names at any line of the evaluation.
        it 'never leaves Logger, Mode or Mode::TEXT undefined while it evaluates' do
          missing = []
          trace = TracePoint.new(:line) do |tp|
            next unless File.expand_path(tp.path) == File.expand_path('../../scripts/log.lic', __dir__)

            defined = GameLogger.const_defined?(:Logger, false) && GameLogger.const_defined?(:Mode, false) &&
                      GameLogger::Mode.const_defined?(:TEXT, false) && GameLogger::Logger.const_defined?(:DEFAULT_MODE, false)
            missing << tp.lineno unless defined
          end

          trace.enable { LogSpecHarness.evaluate_game_logger }

          expect(missing).to be_empty
        end

        it 'leaves a run built before it with the Logger class it was built with' do
          logger = GameLogger::Logger.new(OpenStruct.new)

          LogSpecHarness.evaluate_game_logger

          expect(logger).not_to be_a(GameLogger::Logger)
          expect(logger.class::REGET_MARKER).to eq("<!-- Above contents from reget; full logging now active -->\n")
        end

        # A different log.lic evaluated in the same session (an update, then
        # ;force log) redefines the module's methods. A run already logging
        # calls only its own Logger class's file and room helpers, so it keeps
        # rotating files when the new ones take other arguments (stood in for
        # here by helpers that raise).
        it "keeps rotating files with its own helpers after another version's evaluation" do
          $login_time = Time.new(2026, 1, 1)
          helpers = %i[log_root log_directory log_file_path file_stamp with_log_file write_footer lich_room_id
                       room_title_pattern number_room_title start_upstream_logger upstream_stopped upstream_frame
                       log_label mode_for]
          another_version = lambda do
            LogSpecHarness.evaluate_game_logger
            [GameLogger, GameLogger::Logger].product(helpers).each do |owner, name|
              allow(owner).to receive(name).and_raise(ArgumentError, "another version's #{name}") if owner.respond_to?(name, true)
            end
          end
          # Each line is read in a new room, so --rnum looks the room up again.
          lines = ['[Town Square]', '[Town Square]', '[Town Square]']
          room_count = 0
          stub_const('Map', double('Map', loaded?: true, ids_from_uid: [288]))
          allow(XMLData).to receive(:room_count) { room_count }
          io = io_class.new([])
          io.define_singleton_method(:get) do
            another_version.call if lines.size == 2
            room_count += 1
            lines.shift || raise(StopIteration)
          end

          Timeout.timeout(5) { GameLogger::Logger.new(GameLogger::Opts.parse(['--lines=1', '--rnum']), clock: clock, io: io).run }

          bodies = Dir[file_at('2026/07/*.log')].sort.map { |path| File.read(path).lines(chomp: true)[1..-2] }
          expect(bodies).to eq([['[Town Square - 288] (u1234)']] * 3)
        end
      end

      it 'is a frozen value with the text format' do
        mode = GameLogger::Mode::TEXT

        expect(mode).to be_frozen
        expect(mode.extension).to eq('.log')
        expect(mode.started_text).to eq('Non-XML Logging started, currently logging to')
        expect(mode.upstream_line.call('<c>look')).to eq('>look')
      end

      # log.lic's first line is "# frozen_string_literal: true" and Lich
      # evaluates the file from there, so the harness does too: a change
      # that mutates a literal fails here, not only in Lich.
      it "has log.lic's string literals frozen, as Lich evaluates the file" do
        expect(GameLogger::Mode::TEXT.started_text).to be_frozen
        expect(GameLogger::Logger::REGET_MARKER).to be_frozen
      end
    end

    describe '.start_upstream_logger with a block' do
      it 'logs each typed command as the block formats it' do
        LogSpecHarness.type('look')

        thread = GameLogger::Logger.start_upstream_logger { |command| "typed: #{command}" }
        thread.join(2)

        expect(LogSpecHarness::DOWNSTREAM.pop(true)).to eq('typed: look')
      end
    end
  end
end

# Lich refuses to start a script whose `required: Lich` floor is above the
# running Lich, and repository.lic checks the same line before it installs
# an update (CommentParser.check_lich_requirement). Data.define and
# Data#with are Ruby 3.2, while Lich 5.14.0 to 5.18.x accept Ruby 2.6
# (lib/version.rb REQUIRED_RUBY); 5.19.0 is the first Lich that requires
# Ruby 4.0. So a log.lic that uses Data must not let an older Lich load it.
RSpec.describe 'log.lic required Lich version' do
  let(:source) { File.read(File.expand_path('../../scripts/log.lic', __dir__)) }
  let(:floor) { Gem::Version.new(source[/^[ \t]+required:[ \t]*Lich[ \t]*>=?[ \t]*([\d.]+)/, 1]) }

  it 'is Lich 5.19.0 or later while the script uses Ruby 3.2 Data' do
    skip 'log.lic does not use Data' unless source.include?('Data.define')

    expect(floor).to be >= Gem::Version.new('5.19.0')
  end
end
