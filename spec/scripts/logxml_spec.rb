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
    pending_lines = lines.map(&:dup) # fresh Strings, as get returns; logxml edits lines in place
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

  # R-05, R-19, R-34 (logxml copy): the Lich id comes only from the map's
  # UID table, never from Map.current, which matches the room from the
  # logger's thread (LOCATION/PEER, a cleared buffer) and echoes
  # "no map database found" with no map.
  context 'with --rnum' do
    let(:game) { 'GSIV' }
    let(:uid) { 4_216_015 }
    let(:uid_table) { {} }
    # Strict double: any call other than Map.ids_from_uid fails the example.
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
    end

    def logged_lines(vars: ['--rnum'])
      run_logxml(vars: vars, lines: [title_line, '<output>You see a door.</output>'])
      log_lines.drop(1)
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

  it 'keeps a comma in a quoted --timestamp format' do
    run_logxml(vars: ['--timestamp="%b %d, %H:%M"'])

    expect(log_lines).to eq(['Apr 23, 10:00', 'Apr 23, 10:00: <output>You see a door.</output>'])
  end
end
