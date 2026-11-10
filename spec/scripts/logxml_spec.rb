require 'tmpdir'
require 'fileutils'
require 'ostruct'
require 'timeout'

# logxml.lic is a top-level script, not a module, so these examples run its
# real body (everything after the =end header) on a fresh object whose
# singleton methods stand in for the Lich script helpers. Nothing is defined
# at the top level, so other spec files keep their own helpers.
RSpec.describe 'logxml.lic' do
  let(:script_path) { File.expand_path('../../scripts/logxml.lic', __dir__) }
  let(:script_lines) { File.readlines(script_path) }
  # First line after the =end header, 1-based, so backtraces point at logxml.lic.
  let(:body_line) { script_lines.index { |l| l.start_with?('=end') } + 2 }
  let(:body) { script_lines.drop(body_line - 1).join }

  let(:log_dir) { Dir.mktmpdir }
  let(:frozen_time) { Time.new(2026, 4, 23, 10, 0, 5) }
  # Time.now; a Time among run_logxml's lines moves it.
  let(:clock) { [frozen_time] }
  let(:echoes) { [] }
  let(:default_header) { '2026-04-23 10:00am' }
  let(:fallback_stamp) { frozen_time.strftime('%F %T %Z') }
  # The footer when timestamps are off: 24-hour with milliseconds, unlike
  # the 12-hour header.
  let(:default_footer) { frozen_time.strftime('%Y-%m-%d %H:%M:%S.%L %:z') }
  let(:started_echo) { "XML Logging started, currently logging to #{log_file}" }

  before do
    stub_const('LICH_DIR', log_dir)
    hide_const('LOG_DIR') # unless an example sets it, as Lich's --logs= does
    stub_const('XMLData', Module.new do
      def self.game = 'GSIV'
      def self.name = 'TestChar'
    end)
    allow(Time).to receive(:now) { clock.first }
    $login_time = frozen_time - 3600
  end

  after do
    FileUtils.rm_rf(log_dir)
  end

  # Runs logxml.lic once with +vars+ as typed and the given DR settings
  # (+nil+ for none, as in GS). Ends when the fed lines run out; a Time
  # among +lines+ moves the clock before the next line is read.
  # +reget+ is what lich-5's reget answers: nil for an empty buffer. A
  # block runs once the fed lines run out, just before the logger stops.
  def run_logxml(vars: [], settings: nil, lines: ['<output>You see a door.</output>'], reget: nil)
    script = OpenStruct.new(want_script_output: nil, vars: [vars.join(' '), *vars], downstream_buffer: [], name: 'logxml')
    stub_const('Script', Class.new { define_singleton_method(:current) { script } })
    pending_lines = lines.map(&:dup) # fresh Strings, as get returns; logxml edits lines in place
    sink = echoes
    runner = Object.new
    runner.define_singleton_method(:hide_me) { nil }
    runner.define_singleton_method(:echo) { |msg| sink << msg.to_s }
    runner.define_singleton_method(:reget) { reget }
    on_stop = block_given? ? proc { yield } : proc {}
    time_now = clock
    runner.define_singleton_method(:get) do
      time_now[0] = pending_lines.shift while pending_lines.first.is_a?(Time)
      next pending_lines.shift unless pending_lines.empty?

      on_stop.call
      raise StopIteration
    end
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

        expect(log_lines).to eq([fallback_stamp, "#{fallback_stamp}: <output>You see a door.</output>", fallback_stamp])
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

      expect(log_lines).to eq(['10:00', '10:00: <output>You see a door.</output>', '10:00'])
      expect(echoes).to eq([started_echo])
    end
  end

  it 'uses the yaml format when it is a format' do
    run_logxml(settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))

    expect(log_lines).to eq(['10:00', '10:00: <output>You see a door.</output>', '10:00'])
    expect(echoes).to eq([started_echo])
  end

  it 'stays off when the yaml turns timestamps off, whatever the format' do
    run_logxml(settings: OpenStruct.new(log_timestamp: false, log_timestamp_format: nil))

    expect(log_lines).to eq([default_header, '<output>You see a door.</output>', default_footer])
    expect(echoes).to eq([started_echo])
  end

  context 'with an empty --timestamp=' do
    it 'logs without timestamps and says the option was ignored' do
      run_logxml(vars: ['--timestamp='])

      expect(log_lines).to eq([default_header, '<output>You see a door.</output>', default_footer])
      expect(echoes).to eq(
        [
          'timestamp was given without a format, so it is ignored; to add timestamps use --timestamp="%F %T %Z".',
          started_echo
        ]
      )
    end

    it 'treats --timestamp="" in vars[0] the same way' do
      run_logxml(vars: ['--timestamp=""'])

      expect(log_lines).to eq([default_header, '<output>You see a door.</output>', default_footer])
      expect(echoes.first).to start_with('timestamp was given without a format')
    end

    it 'keeps the yaml format when the yaml enables timestamps' do
      run_logxml(vars: ['--timestamp='], settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))

      expect(log_lines).to eq(['10:00', '10:00: <output>You see a door.</output>', '10:00'])
    end
  end

  # R-05, R-19, R-34 (logxml copy): the Lich id comes only from the map's
  # UID table, never from Map.current, which matches the room from the
  # logger's thread (LOCATION/PEER, a cleared buffer) and echoes
  # "no map database found" with no map.
  context 'with --rnum' do
    let(:game) { 'GSIV' }
    let(:uid) { 4_216_015 }
    let(:uid_table) { {} }
    # Strict double: any call other than Map.ids_from_uid and Map.loaded?
    # (the map is loaded unless an example says otherwise) fails the example.
    let(:map) { double('Map') }
    let(:title_line) { '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns]' }

    before do
      room_game = game
      room_uid = uid
      stub_const('XMLData', Module.new do
        define_singleton_method(:game) { room_game }
        define_singleton_method(:name) { 'TestChar' }
        define_singleton_method(:room_id) { room_uid }
      end)
      stub_const('Map', map)
      allow(map).to receive(:ids_from_uid) { |n| uid_table.fetch(n, []) }
      allow(map).to receive(:loaded?).and_return(true)
    end

    def logged_lines(vars: ['--rnum'])
      run_logxml(vars: vars, lines: [title_line, '<output>You see a door.</output>'])
      expect(log_lines.last).to eq(default_footer)
      log_lines[1..-2]
    end

    it 'adds the Lich id from the UID table and the u-id to the GS room title' do
      uid_table[uid] = [228]

      expect(logged_lines).to eq(
        [
          '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns - 228] (u4216015)',
          '<output>You see a door.</output>'
        ]
      )
      expect(map).to have_received(:ids_from_uid).once
    end

    it "writes no ' - ]' in GS when the UID is not in the map, only the u-id" do
      expect(logged_lines(vars: ['--roomnum']).first).to eq(
        '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns] (u4216015)'
      )
    end

    it 'adds no Lich id when the UID maps to more than one room' do
      uid_table[uid] = [228, 229]

      expect(logged_lines.first).to eq(
        '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns] (u4216015)'
      )
    end

    it 'does not look the room up without --rnum' do
      expect(logged_lines(vars: []).first).to eq(title_line)
      expect(map).not_to have_received(:ids_from_uid)
    end

    # A-1: Lich loads the map only when something asks for it (in DR its
    # own room display does not by default), so --rnum loads it once, in a
    # thread of its own, off the get loop.
    context 'when nothing has loaded the map' do
      let(:load_results) { Thread::Queue.new }
      let(:load_result) { true }

      before do
        allow(map).to receive(:loaded?).and_return(false)
        allow(map).to receive(:load) do
          load_results << load_result
          load_result
        end
      end

      it 'loads the map once and still logs every line' do
        expect(logged_lines.size).to eq(2)
        expect(load_results.pop(timeout: 2)).to be(true)
        expect(map).to have_received(:load).once
      end

      context 'when no map database can be loaded' do
        let(:load_result) { false }

        it 'says so' do
          logged_lines
          expect(load_results.pop(timeout: 2)).to be(false)
          Timeout.timeout(2) { sleep 0.01 until echoes.any? { |e| e.start_with?('no map database') } }
          expect(echoes).to include('no map database could be loaded, so --rnum adds no Lich room numbers.')
        end
      end

      it 'does not load the map without --rnum' do
        logged_lines(vars: [])
        expect(map).not_to have_received(:loaded?)
        expect(map).not_to have_received(:load)
      end
    end

    it 'does not load the map when it is already loaded' do
      allow(map).to receive(:load)
      logged_lines
      expect(map).to have_received(:loaded?).once
      expect(map).not_to have_received(:load)
    end

    context 'in DragonRealms' do
      let(:game) { 'DR' }
      let(:uid) { 230_008 }

      it 'adds the Lich id and no u-id' do
        uid_table[uid] = [12_345]

        expect(logged_lines.first).to eq(
          '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns - 12345]'
        )
      end

      it 'leaves the title alone when the UID is not in the map' do
        expect(logged_lines.first).to eq(title_line)
      end
    end
  end

  context 'when started within 30 seconds of login' do
    let(:marker) { '<!-- Above contents from reget; full logging now active -->' }

    before { $login_time = frozen_time - 5 }

    # R-14: lich-5's reget returns nil for an empty buffer; puts(nil)
    # wrote a blank line before the marker.
    it 'writes no blank line when reget returns nil' do
      run_logxml(reget: nil)

      expect(log_lines.first(3)).to eq([default_header, marker, '<output>You see a door.</output>'])
    end

    # R-15: reget lines keep the server's "\r" (CRLF line ends).
    it 'writes the raw reget lines without their trailing carriage return' do
      run_logxml(reget: ["<pushStream id=\"room\"/>Room text\r", "<prompt time=\"1\">&gt;</prompt>\r"])

      expect(File.binread(log_file)).not_to include("\r")
      expect(log_lines.first(4)).to eq(
        [default_header, '<pushStream id="room"/>Room text', '<prompt time="1">&gt;</prompt>', marker]
      )
    end
  end

  # R-24: Lich's --logs= sets LOG_DIR; pilepull.lic reads the logs there.
  context 'with Lich started with --logs=' do
    let(:logs_dir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(logs_dir) }

    it 'writes the log under LOG_DIR in the <game>-<name>/<year>/<month> layout' do
      stub_const('LOG_DIR', logs_dir)

      run_logxml

      expect(Dir.glob(File.join(logs_dir, '**', '*.xml'))).to eq(
        [File.join(logs_dir, 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.xml')]
      )
      expect(log_file).to be_nil
    end
  end

  it 'writes under LICH_DIR/logs when LOG_DIR is not defined or empty' do
    run_logxml
    expect(log_file).to eq(File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.xml'))

    FileUtils.rm_rf(File.join(log_dir, 'logs'))
    stub_const('LOG_DIR', '')
    run_logxml
    expect(log_file).to eq(File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.xml'))
  end

  # R-13: the line was written before the date check, so the first line
  # after midnight went into yesterday's file; skipped lines used up the
  # 30000-line budget.
  context 'when starting a new file' do
    let(:next_day) { Time.new(2026, 4, 24, 0, 0, 1) }

    it "logs the first line after midnight in the new day's file" do
      run_logxml(lines: ['<output>line 1</output>', next_day, '<output>line 2</output>'])

      root = File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04')
      next_day_footer = next_day.strftime('%Y-%m-%d %H:%M:%S.%L %:z')
      expect(File.read(File.join(root, '2026-04-23_10-00-05.xml')).lines(chomp: true)).to eq(
        [default_header, '<output>line 1</output>', next_day_footer]
      )
      expect(File.read(File.join(root, '2026-04-24_00-00-01.xml')).lines(chomp: true)).to eq(
        ['2026-04-24 12:00am', '<output>line 2</output>', next_day_footer]
      )
    end

    it 'counts only written lines toward the 30000, not skipped stream lines' do
      run_logxml(lines: ['<pushStream id="inv"/>', '<popStream/>', *Array.new(30_001) { |n| "<output>#{n + 1}</output>" }])

      expect(log_lines[30_000, 4]).to eq(['<output>30000</output>', default_footer, default_header, '<output>30001</output>'])
      expect(log_lines.size).to eq(30_005)
    end
  end

  # R-23: the footer was written only when a new file started.
  context 'when the logger stops' do
    it 'ends the file with the footer once, after the last line' do
      run_logxml(lines: ['<output>line 1</output>'])

      expect(log_lines).to eq([default_header, '<output>line 1</output>', default_footer])
    end

    it 'closes the file and lets the reason through when the footer cannot be written' do
      opened = []
      allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { |file| opened << file if file.is_a?(File) }
      end

      run_logxml(lines: []) do
        allow(opened.first).to receive(:puts).and_raise(Errno::ENOSPC)
      end

      expect(opened.size).to eq(1)
      expect(opened.first).to be_closed
      expect(log_lines).to eq([default_header])
    end
  end

  # R-22: the header was written before the begin/ensure that closes the file.
  context 'when the header cannot be written' do
    it 'closes the file without a footer and raises the error' do
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

      expect { run_logxml }.to raise_error(Errno::ENOSPC)

      expect(opened.size).to eq(1)
      expect(opened.first).to be_closed
      expect(File.read(log_file)).to eq('')
    end
  end

  it 'keeps a comma in a quoted --timestamp format' do
    run_logxml(vars: ['--timestamp="%b %d, %H:%M"'])

    expect(log_lines).to eq(['Apr 23, 10:00', 'Apr 23, 10:00: <output>You see a door.</output>', 'Apr 23, 10:00'])
  end
end
