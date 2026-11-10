require 'tmpdir'
require 'fileutils'
require 'ostruct'
require 'timeout'
require_relative '../support/log_spec_harness'

# XML mode, as ;log --xml runs it: these examples run log.lic's body
# (everything after its =end header, see LogSpecHarness.run_whole_script)
# in the harness's Env, as Lich runs a script, with Script.current named
# log and --xml first among the arguments, against the harness's stand-ins
# for Lich (see spec/support/log_spec_harness.rb). The file was
# logxml_spec.rb, which ran the same examples through the logxml.lic shim;
# logxml.lic left the repository in log.lic 1.3.4 (USER-1), and a run
# named logxml (an install's local copy of the shim loads log.lic under
# that name) still picks XML mode, see the examples that say so.
#
# Nested in Env so XMLData, Script and Lich below are the ones the scripts see.
module LogSpecHarness::Env
  # Raised by an exit from the script in these examples (see the exit stub
  # below). Kernel#exit raises SystemExit, which RSpec does not rescue: an
  # exit would end the whole run there, with status 0 and "0 failures",
  # skipping every later example.
  class ScriptExited < StandardError; end

  RSpec.describe 'log.lic in XML mode (;log --xml)' do
    let(:scripts_dir) { File.expand_path('../../scripts', __dir__) }

    let(:log_dir) { Dir.mktmpdir }
    let(:frozen_time) { Time.new(2026, 4, 23, 10, 0, 5) }
    # Time.now; a Time among run_xml's lines moves it.
    let(:clock) { [frozen_time] }
    let(:echoes) { LogSpecHarness.echoes }
    let(:default_header) { '2026-04-23 10:00am' }
    let(:fallback_stamp) { frozen_time.strftime('%F %T %Z') }
    # The footer when timestamps are off: 24-hour with milliseconds, unlike
    # the 12-hour header.
    let(:default_footer) { frozen_time.strftime('%Y-%m-%d %H:%M:%S.%L %:z') }
    let(:started_echo) { "XML Logging started, currently logging to #{log_file}" }

    around do |example|
      login_time = $login_time
      example.run
    ensure
      $login_time = login_time
    end

    before do
      LogSpecHarness.reset!
      stub_const('LICH_DIR', log_dir)
      hide_const('LOG_DIR') # unless an example sets it, as Lich's --logs= does
      stub_const('SCRIPT_DIR', scripts_dir)
      allow(Time).to receive(:now) { clock.first }
      $login_time = frozen_time - 3600
      # log.lic never exits; if it did, the example fails (ScriptExited)
      # instead of the run ending.
      allow(LogSpecHarness::Env).to receive(:exit) { raise ScriptExited, 'log.lic exited' }
    end

    after do
      FileUtils.rm_rf(log_dir)
    end

    # The Script.current of the last run.
    def xml_script
      LogSpecHarness.script
    end

    # The arguments ;log --xml +args+ starts log.lic with: --xml before
    # +args+ (a String as typed, kept as it is after "--xml ", trailing
    # spaces too; an Array as autostart passes its saved arguments).
    def xml_args(args)
      case args
      when nil then '--xml'
      when Array then ['--xml', *args]
      else "--xml #{args}"
      end
    end

    # Runs log.lic once, as ;log --xml +args+ (see xml_args; vars are built
    # as lich-5 builds them, see LichScriptVars), under the script name
    # +name+, and the given DR settings (+nil+ for none: get_settings then
    # answers an empty OpenStruct, as lich-5's does for a GemStone character
    # with no yaml). With +name+ 'logxml', +args+ are passed as they are,
    # with no --xml, as an install's local logxml.lic starts log.lic. Ends
    # when the fed lines run out; a Time among +lines+ moves the clock
    # before the next line is read. +reget+ is what lich-5's reget answers:
    # nil for an empty buffer. With +server_buffer+ (the raw lines the
    # server sent), reget answers as lich-5's does instead, from the
    # want_downstream_xml the script has set by then (see
    # LogSpecHarness.reget). A block runs once the fed lines run out; then
    # get hands out what the upstream thread pushed onto the downstream
    # buffer, and the logger stops. +upstream+ stands in for upstream_get;
    # the default ends the upstream thread before it reads a command. The
    # script starts with lich-5's Script#initialize want_* defaults
    # (lib/common/script.rb).
    def run_xml(args: nil, name: 'log', settings: nil, lines: ['<output>You see a door.</output>'], reget: nil, server_buffer: nil, upstream: -> { Thread.current.kill }, &on_stop)
      LogSpecHarness.start_script(name == 'log' ? xml_args(args) : args, name: name)
      LogSpecHarness.settings = settings || OpenStruct.new
      if server_buffer
        LogSpecHarness.server_buffer = server_buffer
      else
        allow(LogSpecHarness).to receive(:reget).and_return(reget)
      end
      feed_lines(lines, &on_stop)
      allow(LogSpecHarness).to receive(:upstream_get) { upstream.call }
      Timeout.timeout(5) { LogSpecHarness.run_whole_script }
    end

    # Makes get hand out +lines+ (a Time among them moves the clock), then
    # run +on_stop+ once, then hand out what the upstream thread pushed, then
    # end the run.
    def feed_lines(lines, &on_stop)
      pending = lines.map { |line| line.is_a?(String) ? line.dup : line } # fresh Strings, as get returns
      time_now = clock
      stopping = false
      allow(LogSpecHarness).to receive(:get) do
        time_now[0] = pending.shift while pending.first.is_a?(Time)
        next pending.shift unless pending.empty?

        on_stop&.call unless stopping
        stopping = true
        next LogSpecHarness::DOWNSTREAM.pop unless LogSpecHarness::DOWNSTREAM.empty?

        raise StopIteration
      end
    end

    def log_file
      Dir.glob(File.join(log_dir, '**', '*.xml')).first
    end

    # Stands in for Lich.log; returns the Array its messages are added to.
    def stub_lich_log
      [].tap do |logged|
        allow(Lich).to receive(:log) { |msg| logged << msg }
      end
    end

    def log_lines
      File.read(log_file).lines(chomp: true)
    end

    context 'when the yaml enables timestamps without a usable format' do
      { 'no format' => nil, 'an empty format' => '', 'a non-String format' => 5 }.each do |label, format|
        it "stamps with %F %T %Z and says so for #{label} (#{format.inspect})" do
          run_xml(settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: format))

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
        run_xml(args: '--timestamp=%H:%M', settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: nil))

        expect(log_lines).to eq(['10:00', '10:00: <output>You see a door.</output>', '10:00'])
        expect(echoes).to eq([started_echo])
      end
    end

    it 'uses the yaml format when it is a format' do
      run_xml(settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))

      expect(log_lines).to eq(['10:00', '10:00: <output>You see a door.</output>', '10:00'])
      expect(echoes).to eq([started_echo])
    end

    it 'stays off when the yaml turns timestamps off, whatever the format' do
      run_xml(settings: OpenStruct.new(log_timestamp: false, log_timestamp_format: nil))

      expect(log_lines).to eq([default_header, '<output>You see a door.</output>', default_footer])
      expect(echoes).to eq([started_echo])
    end

    context 'with an empty --timestamp=' do
      it 'logs without timestamps and says the option was ignored' do
        run_xml(args: '--timestamp=')

        expect(log_lines).to eq([default_header, '<output>You see a door.</output>', default_footer])
        expect(echoes).to eq(
          [
            'timestamp was given without a format, so it is ignored; to add timestamps use --timestamp="%F %T %Z".',
            started_echo
          ]
        )
      end

      it 'treats --timestamp="" in vars[0] the same way' do
        run_xml(args: '--timestamp=""')

        expect(log_lines).to eq([default_header, '<output>You see a door.</output>', default_footer])
        expect(echoes.first).to start_with('timestamp was given without a format')
      end

      it 'keeps the yaml format when the yaml enables timestamps' do
        run_xml(args: '--timestamp=', settings: OpenStruct.new(log_timestamp: true, log_timestamp_format: '%H:%M'))

        expect(log_lines).to eq(['10:00', '10:00: <output>You see a door.</output>', '10:00'])
      end
    end

    # R-05, R-19, R-34 (in XML mode): the Lich id comes only from the map's
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
        allow(XMLData).to receive(:game) { room_game }
        allow(XMLData).to receive(:room_id) { room_uid }
        stub_const('Map', map)
        allow(map).to receive(:ids_from_uid) { |n| uid_table.fetch(n, []) }
        allow(map).to receive(:loaded?).and_return(true)
      end

      def logged_lines(args: '--rnum', line: title_line)
        run_xml(args: args, lines: [line, '<output>You see a door.</output>'])
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
        expect(logged_lines(args: '--roomnum').first).to eq(
          '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns] (u4216015)'
        )
      end

      # As in ;log, a bare word is an option too; 0.6.6 needed the "--".
      %w[rnum roomnum].each do |word|
        it "turns room numbers on for the word #{word}, without --" do
          uid_table[uid] = [228]

          expect(logged_lines(args: word).first).to eq(
            '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns - 228] (u4216015)'
          )
        end
      end

      it 'adds no Lich id when the UID maps to more than one room' do
        uid_table[uid] = [228, 229]

        expect(logged_lines.first).to eq(
          '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns] (u4216015)'
        )
      end

      it 'does not look the room up without --rnum' do
        expect(logged_lines(args: nil).first).to eq(title_line)
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
            expect(echoes).to include('no map database could be loaded, so Lich room numbers in --exclude and --rnum match no room; u<uid> entries still work.')
          end
        end

        it 'does not load the map without --rnum' do
          logged_lines(args: nil)
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

      # The title line as the server sends it, verbatim from lich-5
      # spec/fixtures/streams/gs_saga_hunt.xml:23, ends in the game's own
      # "(uid)". R-12, Q-05: as in text mode, no u-id is added when the line
      # already shows the room's UID (0.6.6 wrote "(u4216015) (4216015)").
      it "adds the Lich id inside the first ] of a real GS title line and keeps the game's (uid) as the only one" do
        uid_table[uid] = [228]

        expect(logged_lines(line: '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns] (4216015)').first).to eq(
          '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns - 228] (4216015)'
        )
      end

      it 'puts the numbers at the first ] only' do
        uid_table[uid] = [228]

        expect(logged_lines(line: "#{title_line} [lit]").first).to eq(
          '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns - 228] (u4216015) [lit]'
        )
      end

      it 'reads --rnum after another option' do
        uid_table[uid] = [228]

        run_xml(args: '--timestamp=%T --rnum', lines: [title_line])

        expect(log_lines).to eq(
          ['10:00:05', '10:00:05: <resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns - 228] (u4216015)', '10:00:05']
        )
      end

      # ;autostart add --global log --xml --timestamp=\"%F %T %Z\" --rnum (the
      # header's autostart example, with --xml) is saved as these words;
      # lich-5 joins them into vars[0].
      it "reads the header's autostart example on the autostart Array path" do
        uid_table[uid] = [228]

        run_xml(args: ['--timestamp="%F', '%T', '%Z"', '--rnum'], lines: [title_line])

        expect(log_lines).to eq(
          [
            fallback_stamp,
            "#{fallback_stamp}: <resource picture=\"0\"/><style id=\"roomName\" />[Sanctum of Scales, Columns - 228] (u4216015)",
            fallback_stamp
          ]
        )
      end

      # Only a line that starts with the room-name resource is a title; this
      # line (made up, not from a fixture) names the style later on.
      it 'leaves a line alone that mentions roomName after its start' do
        uid_table[uid] = [228]
        line = '<output>The roomName style marks [the title].</output>'

        expect(logged_lines(line: line).first).to eq(line)
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

        # Verbatim from lich-5 spec/fixtures/streams/dr_legacy_stow_movement.xml.
        context 'in the room of a real DR title line' do
          let(:uid) { 230_009 }

          it "adds the Lich id inside the first ] and keeps the game's (uid)" do
            uid_table[uid] = [12_345]

            expect(logged_lines(line: '<resource picture="0"/><style id="roomName" />[Bosque Deriel, Dense Woods] (230009)').first).to eq(
              '<resource picture="0"/><style id="roomName" />[Bosque Deriel, Dense Woods - 12345] (230009)'
            )
          end
        end

        it 'puts the Lich id inside the first ] only' do
          uid_table[uid] = [12_345]

          expect(logged_lines(line: "#{title_line} [lit]").first).to eq(
            '<resource picture="0"/><style id="roomName" />[Sanctum of Scales, Columns - 12345] [lit]'
          )
        end

        # R-17, Q-06: the Saga-identity <room> block, verbatim from lich-5
        # spec/fixtures/streams/dr_saga_containers_speech.xml:257, cut after
        # </description>. 0.6.6 numbered only the roomName style.
        it 'adds the Lich id inside the first ] of a real Saga-identity <room><name> title' do
          uid_table[uid] = [12_345]
          saga_title = '<resource picture="0"/><room><name>[Bosque Deriel, Hermit\'s Shacks] (230008)</name><description>Here on the ' \
                       'route between the sacred sites of the Observatory and the Faery Ring is a semi-circular clearing.  At its center ' \
                       'stands a hut made of lashed branches, roofed with broad leaves.  A certain sect of Elven clerics, who are renowned ' \
                       'for their devotion to contemplation, are wont to retire into the solitudes of the woods and groves hereabouts.  ' \
                       'They are not, however, renowned for their hospitality.</description>'

          numbered = logged_lines(line: saga_title).first

          expect(numbered).to start_with('<resource picture="0"/><room><name>[Bosque Deriel, Hermit\'s Shacks - 12345] (230008)</name><description>Here on the ')
          expect(numbered).to eq(saga_title.sub("Shacks]", "Shacks - 12345]"))
        end
      end
    end

    # The contract ;log --xml must keep. lich-5 hands the XML lines
    # to a script that wants the XML downstream, and adds the text lines to
    # the same buffer when it wants the text downstream too, or another
    # script's output when it wants that; typed commands reach upstream_get
    # only with want_upstream.
    it 'asks for the XML downstream and typed commands, and not the text downstream or script output' do
      run_xml

      expect(xml_script.to_h.slice(:want_downstream, :want_downstream_xml, :want_script_output, :want_upstream)).to eq(
        want_downstream: false, want_downstream_xml: true, want_script_output: false, want_upstream: true
      )
    end

    it 'keeps pushStream and popStream lines when started with streams' do
      stream_lines = ['<pushStream id="inv"/>', '<output>In the pack: a torch.</output>', '<popStream/>']

      run_xml(args: 'streams', lines: stream_lines)

      expect(log_lines).to eq([default_header, *stream_lines, default_footer])
    end

    # streams is a word of its own among the arguments, not a part of one.
    # R-06: without streams, an inventory stream is left out whole, the
    # lines inside it too (log.lic 1.3.2).
    it 'leaves out stream content when no argument is the word streams' do
      run_xml(args: 'nostreams', lines: ['<pushStream id="inv"/>', '<output>In the pack: a torch.</output>', '<popStream/>', '<output>after</output>'])

      expect(log_lines).to eq([default_header, '<output>after</output>', default_footer])
    end

    # The dialog and progress bar lines log.lic drops in text mode stay in
    # the XML log. The minivitals line is verbatim from lich-5
    # spec/fixtures/streams/dr_saga_login.xml; the others are the tag lines
    # log_spec.rb's filter rows use (from lich-5 spec/fixtures/streams, the
    # closing tag added).
    describe 'lines that start with a dialog or progress bar tag' do
      {
        'dialog data'              => "<dialogData id='minivitals'><progressBar id='spirit' value='100' text='spirit 100%' left='60%' customText='t' top='0%' width='20%' height='100%'/></dialogData>",
        'a progress bar'           => %(<progressBar id='1253901988' value='89' text="Mana Tap" left='22%' top='0' width='76%' height='15' time='00:13:28'/>),
        'an open dialog'           => '<openDialog type="dynamic" id="injuries" title="Injuries" target="injuries" location="right" height="180" width="190" resident="true">',
        'a close dialog'           => "<closeDialog id='AimTimerDialog'/>",
        'a closing dialogData tag' => '</dialogData>'
      }.each do |label, tag_line|
        it "logs #{label} with the lines around it" do
          run_xml(lines: ['<output>before</output>', tag_line, '<output>after</output>'])

          expect(log_lines).to eq([default_header, '<output>before</output>', tag_line, '<output>after</output>', default_footer])
        end
      end
    end

    # Verbatim from lich-5 spec/fixtures/streams/gs_saga_hunt.xml: the
    # pushStream comes after other tags. R-06: the inventory stream is left
    # out from its pushStream on (logxml 0.6.6 kept the whole line, as it
    # did not start with the tag) and the tags before it are kept.
    it 'keeps the tags before an inventory pushStream later in the line, without streams' do
      run_xml(lines: ["<clearStream id='inv' ifClosed=''/><pushStream id='inv'/>Your worn items are:"])

      expect(log_lines).to eq([default_header, "<clearStream id='inv' ifClosed=''/>", default_footer])
    end

    # logxml 0.6.6's /^<(?:push|pop)Stream/ matched after each line break in
    # the line too, so it dropped this line whole. R-06: with no span open,
    # a popStream ends nothing and the whole line is kept. (Made-up line;
    # lich-5 chomps only the end.)
    it 'keeps a line with a popStream after a line break in it when no stream span is open, without streams' do
      run_xml(lines: ['<output>before</output>', "<output>a torch</output>\n<popStream/>", '<output>after</output>'])

      expect(log_lines).to eq([default_header, '<output>before</output>', '<output>a torch</output>', '<popStream/>', '<output>after</output>', default_footer])
    end

    # Lines verbatim from lich-5 spec/fixtures/streams/gs_saga_hunt.xml,
    # leading spaces included.
    it 'writes game lines as they come, leading spaces included' do
      lines = ['  1d100: 20 + Modifiers: 372 == 392', '   ... 60 points of damage!']

      run_xml(lines: lines)

      expect(log_lines).to eq([default_header, *lines, default_footer])
    end

    # lich-5 chomps each server line before a script reads it
    # (Script.new_downstream_xml), so the blank lines in a real stream (4 in
    # spec/fixtures/streams/gs_saga_hunt.xml, 41 in dr_saga_hunt.xml) arrive
    # as "", and stay in the log.
    it 'writes a blank game line as a blank line' do
      run_xml(lines: ['<output>line 1</output>', '', '<output>line 2</output>'])

      expect(log_lines).to eq([default_header, '<output>line 1</output>', '', '<output>line 2</output>', default_footer])
    end

    it 'stamps a typed command like a game line when timestamps are on' do
      typed = ['<c>look']
      upstream = -> { typed.empty? ? Thread.current.kill : typed.shift }

      run_xml(args: '--timestamp=%T', upstream: upstream) do
        Timeout.timeout(2) { sleep 0.01 while xml_script.downstream_buffer.empty? }
      end

      expect(log_lines).to eq(
        ['10:00:05', '10:00:05: <output>You see a door.</output>', '10:00:05: <!-- CLIENT --><c>look<!-- ENDCLIENT -->', '10:00:05']
      )
    end

    it 'has each line in the file while the logger waits for the next one' do
      on_disk = nil

      run_xml(lines: ['<output>line 1</output>']) { on_disk = File.read(log_file) }

      expect(on_disk.lines(chomp: true)).to eq([default_header, '<output>line 1</output>'])
    end

    it 'hides itself once' do
      run_xml

      expect(LogSpecHarness.hide_me_calls).to eq(1)
    end

    # USER-1: logxml.lic left the repository in log.lic 1.3.4, but neither
    # lich5-update nor the repository deletes a local file, so an install
    # keeps its logxml.lic; 0.7.x loads log.lic under the name logxml, with
    # the arguments ;logxml was started with. lich-5 gives a script started
    # without arguments an empty vars, so vars[1..] is nil (N35 in
    # log_spec.rb).
    it 'logs XML with no options when run under the name logxml without arguments (vars is empty), as a local logxml.lic runs it' do
      run_xml(args: '', name: 'logxml')

      expect(xml_script.vars).to eq([])
      expect(Dir.glob(File.join(log_dir, '**', '*.log'))).to eq([])
      expect(log_lines).to eq([default_header, '<output>You see a door.</output>', default_footer])
      expect(echoes).to eq([started_echo])
    end

    # The header is 12-hour with the hour's leading zero dropped.
    it 'writes the header hour before 10 without a leading zero' do
      clock[0] = Time.new(2026, 4, 23, 9, 5, 0)

      run_xml

      expect(log_lines).to eq(['2026-04-23 9:05am', '<output>You see a door.</output>', clock[0].strftime('%Y-%m-%d %H:%M:%S.%L %:z')])
    end

    context 'when started within 30 seconds of login' do
      let(:marker) { '<!-- Above contents from reget; full logging now active -->' }

      before { $login_time = frozen_time - 5 }

      # lich-5's reget gives the raw XML only to a script that already wants
      # the XML downstream, so the flag is set before reget is called. Server
      # lines verbatim from lich-5 spec/fixtures/streams/gs_saga_hunt.xml.
      it 'writes the reget as the raw XML the server sent' do
        server_lines = [
          "<style id=\"\"/><style id=\"roomDesc\"/>The tiled ground is chipped, resembling run down cobblestones.<style id=\"\"/>\r",
          "Obvious exits: <a exist=\"-10700001\" coord=\"2524,1864\" noun=\"north\">north</a>, <a exist=\"-10700001\" coord=\"2524,1864\" noun=\"east\">east</a>\r",
          "<compass><dir value=\"n\"/><dir value=\"e\"/></compass><prompt time=\"1792091316\">&gt;</prompt>\r",
          "<component id='room objs'>  You also see the <a exist=\"781927405\" noun=\"disk\">purple Aldric disk</a>.</component>\r",
          "Your <a exist=\"781927405\" noun=\"disk\">disk</a> arrives, following you dutifully.\r"
        ]

        run_xml(server_buffer: server_lines)

        expect(log_lines.first(7)).to eq([default_header, *server_lines.map(&:chomp), marker])
      end

      # R-14: lich-5's reget returns nil for an empty buffer; puts(nil)
      # wrote a blank line before the marker.
      it 'writes no blank line when reget returns nil' do
        run_xml(reget: nil)

        expect(log_lines.first(3)).to eq([default_header, marker, '<output>You see a door.</output>'])
      end

      # The reget is written as the server sent it: the per-line stamp is for
      # lines read while logging, not for lines from before the logger started.
      it 'writes the reget without timestamps when timestamps are on' do
        run_xml(args: '--timestamp=%T', reget: ["<output>Before the logger.</output>\r"])

        expect(log_lines).to eq(
          ['10:00:05', '<output>Before the logger.</output>', marker, '10:00:05: <output>You see a door.</output>', '10:00:05']
        )
      end

      # R-15: reget lines keep the server's "\r" (CRLF line ends).
      it 'writes the raw reget lines without their trailing carriage return' do
        run_xml(reget: ["<pushStream id=\"room\"/>Room text\r", "<prompt time=\"1\">&gt;</prompt>\r"])

        expect(File.binread(log_file)).not_to include("\r")
        expect(log_lines.first(4)).to eq(
          [default_header, '<pushStream id="room"/>Room text', '<prompt time="1">&gt;</prompt>', marker]
        )
      end
    end

    # The reget window is under 30 seconds after login.
    context 'at the edge of the reget window' do
      let(:marker) { '<!-- Above contents from reget; full logging now active -->' }

      it 'writes the reget and the marker when the logger starts 29.9 seconds after login' do
        $login_time = frozen_time - 29.9

        run_xml(reget: ["<output>Before the logger.</output>\r"])

        expect(log_lines).to eq(
          [default_header, '<output>Before the logger.</output>', marker, '<output>You see a door.</output>', default_footer]
        )
      end

      it 'writes neither the reget nor the marker when the logger starts 30 seconds after login' do
        $login_time = frozen_time - 30

        run_xml(reget: ["<output>Before the logger.</output>\r"])

        expect(log_lines).to eq([default_header, '<output>You see a door.</output>', default_footer])
      end
    end

    # R-24: Lich's --logs= sets LOG_DIR; pilepull.lic reads the logs there.
    context 'with Lich started with --logs=' do
      let(:logs_dir) { Dir.mktmpdir }

      after { FileUtils.rm_rf(logs_dir) }

      it 'writes the log under LOG_DIR in the <game>-<name>/<year>/<month> layout' do
        stub_const('LOG_DIR', logs_dir)

        run_xml

        expect(Dir.glob(File.join(logs_dir, '**', '*.xml'))).to eq(
          [File.join(logs_dir, 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.xml')]
        )
        expect(log_file).to be_nil
      end
    end

    it 'writes under LICH_DIR/logs when LOG_DIR is not defined or empty' do
      run_xml
      expect(log_file).to eq(File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.xml'))

      FileUtils.rm_rf(File.join(log_dir, 'logs'))
      stub_const('LOG_DIR', '')
      run_xml
      expect(log_file).to eq(File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04', '2026-04-23_10-00-05.xml'))
    end

    # R-13: the line was written before the date check, so the first line
    # after midnight went into yesterday's file; skipped lines used up the
    # 30000-line budget.
    context 'when starting a new file' do
      let(:next_day) { Time.new(2026, 4, 24, 0, 0, 1) }

      it "logs the first line after midnight in the new day's file" do
        run_xml(lines: ['<output>line 1</output>', next_day, '<output>line 2</output>'])

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
        run_xml(lines: ['<pushStream id="inv"/>', '<popStream/>', *Array.new(30_001) { |n| "<output>#{n + 1}</output>" }])

        # R-25: the clock is frozen, so the second file gets an _01 suffix.
        month = File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04')
        first = File.read(File.join(month, '2026-04-23_10-00-05.xml')).lines(chomp: true)
        expect(first.size).to eq(30_002)
        expect(first.last(2)).to eq(['<output>30000</output>', default_footer])
        expect(File.read(File.join(month, '2026-04-23_10-00-05_01.xml')).lines(chomp: true)).to eq(
          [default_header, '<output>30001</output>', default_footer]
        )
      end

      # A file opened at once after a full one waited for a line; when the
      # first one came after midnight it went to the new day's file and the
      # waiting file kept only its header and footer, under the old day.
      it 'opens the file after a full one only when its first line comes, also past midnight' do
        run_xml(lines: [*Array.new(30_000) { |n| "<output>#{n + 1}</output>" }, next_day, '<output>next day</output>'])

        month = File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04')
        expect(Dir.children(month).sort).to eq(['2026-04-23_10-00-05.xml', '2026-04-24_00-00-01.xml'])
        expect(File.read(File.join(month, '2026-04-23_10-00-05.xml')).lines(chomp: true).last).to eq(default_footer)
        expect(File.read(File.join(month, '2026-04-24_00-00-01.xml')).lines(chomp: true)).to eq(
          ['2026-04-24 12:00am', '<output>next day</output>', next_day.strftime('%Y-%m-%d %H:%M:%S.%L %:z')]
        )
      end

      it 'gives a new file _02 when the time-stamped name and its _01 both exist' do
        month = File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04')
        FileUtils.mkdir_p(month)
        File.write(File.join(month, '2026-04-24_00-00-01.xml'), "other logger\n")
        File.write(File.join(month, '2026-04-24_00-00-01_01.xml'), "other logger\n")

        run_xml(lines: ['<output>line 1</output>', next_day, '<output>line 2</output>'])

        expect(File.read(File.join(month, '2026-04-24_00-00-01_02.xml')).lines(chomp: true)).to eq(
          ['2026-04-24 12:00am', '<output>line 2</output>', next_day.strftime('%Y-%m-%d %H:%M:%S.%L %:z')]
        )
        expect(File.read(File.join(month, '2026-04-24_00-00-01_01.xml'))).to eq("other logger\n")
      end

      it 'appends to an existing file of the same name when it starts' do
        month = File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04')
        FileUtils.mkdir_p(month)
        File.write(File.join(month, '2026-04-23_10-00-05.xml'), "earlier run\n")

        run_xml

        expect(Dir.children(month)).to eq(['2026-04-23_10-00-05.xml'])
        expect(log_lines).to eq(['earlier run', default_header, '<output>You see a door.</output>', default_footer])
      end
    end

    # R-23: the footer was written only when a new file started.
    context 'when the logger stops' do
      it 'ends the file with the footer once, after the last line' do
        run_xml(lines: ['<output>line 1</output>'])

        expect(log_lines).to eq([default_header, '<output>line 1</output>', default_footer])
      end

      it 'closes the file, logs the failed footer and lets the reason through when the footer cannot be written' do
        lich_log = stub_lich_log
        opened = []
        allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
          original.call(*args, &block).tap { |file| opened << file if file.is_a?(File) }
        end

        run_xml(lines: []) do
          allow(opened.first).to receive(:puts).and_raise(Errno::ENOSPC)
        end

        expect(opened.size).to eq(1)
        expect(opened.first).to have_received(:puts).once # the footer was tried
        expect(opened.first).to be_closed
        expect(log_lines).to eq([default_header])
        expect(lich_log).to eq(
          ["log: the footer of #{log_file} was not written while the logger stopped (Errno::ENOSPC: No space left on device)"]
        )
      end

      # lich-5 stops a script by Thread#kill on its threads (script.rb kill).
      it 'writes the footer when the thread is killed, as ;kill log does' do
        waiting = Thread::Queue.new
        logger = Thread.new do
          run_xml(lines: ['<output>line 1</output>']) do
            waiting << true
            sleep # get waits for the next line until ;kill
          end
        end
        Timeout.timeout(2) { waiting.pop }

        logger.kill
        logger.join(2)

        expect(logger).not_to be_alive
        expect(log_lines).to eq([default_header, '<output>line 1</output>', default_footer])
      end

      # A footer that fails when a file is closed for the next one is not part
      # of stopping: it raises, as the plain puts before 0.6.4 did.
      it "closes the file and raises when the footer cannot be written as the new day's file starts" do
        lich_log = stub_lich_log
        next_day = Time.new(2026, 4, 24, 0, 0, 1)
        next_day_footer = next_day.strftime('%Y-%m-%d %H:%M:%S.%L %:z')
        opened = []
        allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
          original.call(*args, &block).tap do |file|
            next unless file.is_a?(File)

            # Only the first file's footer, stamped at the new day, fails.
            allow(file).to receive(:puts).and_wrap_original do |puts, *lines|
              raise Errno::EIO if opened.first.equal?(file) && lines.first.to_s.chomp == next_day_footer

              puts.call(*lines)
            end
            opened << file
          end
        end

        expect { run_xml(lines: ['<output>line 1</output>', next_day, '<output>line 2</output>']) }
          .to raise_error(Errno::EIO)

        expect(opened.size).to eq(1)
        expect(opened.first).to be_closed
        expect(log_lines).to eq([default_header, '<output>line 1</output>'])
        expect(lich_log).to eq([])
      end
    end

    # R-22: a close that failed logged a bare "Can't close file!", with
    # neither the file nor the error.
    context 'when the file cannot be closed' do
      it 'logs the file and the error to the Lich log and stops as it would have' do
        lich_log = stub_lich_log
        allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
          original.call(*args, &block).tap do |file|
            next unless file.is_a?(File)

            allow(file).to receive(:close).and_wrap_original do |close|
              close.call
              raise IOError, 'device gone'
            end
          end
        end

        expect { run_xml(lines: ['<output>line 1</output>']) }.not_to raise_error

        expect(log_lines).to eq([default_header, '<output>line 1</output>', default_footer])
        expect(lich_log).to eq(["log: closing the log file #{log_file} failed (IOError: device gone); lines are written as they come, with sync on, but the file may be missing its footer or a last write"])
      end
    end

    # R-21: the upstream thread's rescue echoed only the bare message and
    # wrote nothing to the file, so a pasted log just lost its commands.
    context 'when the upstream thread stops on an error' do
      # The first typed command is read; the next upstream_get raises +error+.
      def type_then_fail(error)
        calls = 0
        lambda do
          calls += 1
          raise error if calls > 1

          '<c>look'
        end
      end

      # Waits until the upstream thread has pushed the command and its notice.
      def wait_for_upstream_stop
        Timeout.timeout(2) { sleep 0.01 until xml_script.downstream_buffer.size >= 2 }
      end

      # "file:line" of where +error+ was raised, without the directory.
      def raised_at(error)
        location = error.backtrace_locations.first
        "#{File.basename(location.path)}:#{location.lineno}"
      end

      # The notice line as written for an error that reads +reason+.
      def notice_for(reason)
        "<!-- log: typed commands are not logged after this line; the upstream thread stopped (#{reason}) -->"
      end

      it 'echoes the error, where it was raised and how to log typed commands again' do
        error = RuntimeError.new('boom')

        run_xml(lines: [], upstream: type_then_fail(error)) { wait_for_upstream_stop }

        expect(echoes.grep(/\Atyped commands/)).to eq(
          [
            "typed commands are no longer logged: the upstream thread stopped on RuntimeError: boom at #{raised_at(error)}. " \
            'Game lines are still logged; restart the logger (;kill log, then ;log --xml) to log typed commands again.'
          ]
        )
        expect(raised_at(error)).to match(/\Alog_xml_mode_spec\.rb:\d+\z/)
      end

      # The directory (C:/Users/<name>/...) only makes the echo longer.
      it 'gives the file and line it was raised at without the directory' do
        error = RuntimeError.new('boom')
        error.set_backtrace(["C:/Users/someone/Lich5/scripts/log.lic:142:in 'block in <main>'"])
        raise_it = lambda do
          xml_script.downstream_buffer << 'first'
          raise error
        end

        run_xml(lines: [], upstream: raise_it) { wait_for_upstream_stop }

        expect(echoes.grep(/\Atyped commands/).first)
          .to start_with('typed commands are no longer logged: the upstream thread stopped on RuntimeError: boom at log.lic:142. ')
        expect(echoes.join).not_to include('someone')
      end

      # Restarting without them would drop --timestamp, --rnum or streams.
      it 'gives the restart with the arguments the logger was started with' do
        run_xml(args: 'streams --timestamp=%H:%M', lines: [], upstream: type_then_fail(RuntimeError.new('boom'))) { wait_for_upstream_stop }

        expect(echoes.grep(/\Atyped commands/).first)
          .to end_with('restart the logger (;kill log, then ;log --xml streams --timestamp=%H:%M) to log typed commands again.')
      end

      # Without the strip, the hint would read ";log --xml   " with trailing spaces.
      it 'gives the restart without the spaces vars[0] ends in' do
        run_xml(args: '  ', lines: [], upstream: type_then_fail(RuntimeError.new('boom'))) { wait_for_upstream_stop }

        expect(echoes.grep(/\Atyped commands/).first).to end_with('(;kill log, then ;log --xml) to log typed commands again.')
      end

      # TEXT AND XML TOGETHER: ;log, then ;force log --xml. Both run as log,
      # so ;kill log stops the first log Lich finds, and ;log --xml without
      # ;force is refused while the other one runs.
      it 'restarts with ;force, and says ;kill log can stop the other one, when the text log runs too' do
        LogSpecHarness.other_scripts = [OpenStruct.new(name: 'log', hidden: true)]

        run_xml(args: 'streams', lines: [], upstream: type_then_fail(RuntimeError.new('boom'))) { wait_for_upstream_stop }

        expect(echoes.grep(/\Atyped commands/).first).to end_with(
          'restart the logger (;kill log, then ;force log --xml streams; another log is running too, and ;kill log stops the first log Lich finds, ' \
          'which can be the other one) to log typed commands again.'
        )
      end

      it 'gives the frame as is when it has no "path:line" start' do
        error = RuntimeError.new('boom')
        error.set_backtrace(['<internal:kernel>'])

        run_xml(lines: [], upstream: type_then_fail(error)) { wait_for_upstream_stop }

        expect(echoes.grep(/\Atyped commands/).first)
          .to start_with('typed commands are no longer logged: the upstream thread stopped on RuntimeError: boom at <internal:kernel>. ')
      end

      it 'writes a notice line into the log file saying typed commands are not logged after it, and keeps logging game lines' do
        run_xml(lines: ['<output>line 1</output>'], upstream: type_then_fail(RuntimeError.new('boom'))) { wait_for_upstream_stop }

        expect(log_lines).to eq(
          [
            default_header,
            '<output>line 1</output>',
            '<!-- CLIENT --><c>look<!-- ENDCLIENT -->',
            '<!-- log: typed commands are not logged after this line; the upstream thread stopped (RuntimeError: boom) -->',
            default_footer
          ]
        )
      end

      it 'puts a message over several lines on one line, and breaks up "--" so the comment is not closed early' do
        run_xml(lines: [], upstream: type_then_fail(IOError.new("closed stream\n--> see above"))) { wait_for_upstream_stop }

        expect(log_lines[-2]).to eq('<!-- log: typed commands are not logged after this line; the upstream thread stopped (IOError: closed stream - -> see above) -->')
        expect(echoes.grep(/\Atyped commands/).first)
          .to start_with('typed commands are no longer logged: the upstream thread stopped on IOError: closed stream --> see above at ')
      end

      # gsub('--', '- -') left "a - --> b" and "x- --y": the first closed the
      # comment early, both left a "--" XML does not allow in a comment.
      {
        'a ---> b'          => 'a - - -> b',
        '--- Lich: x---y'   => '- - - Lich: x- - -y',
        'ends in dashes --' => 'ends in dashes - -'
      }.each do |message, spaced|
        it "spaces out every dash run in #{message.inspect} so the comment holds no \"--\"" do
          run_xml(lines: [], upstream: type_then_fail(IOError.new(message))) { wait_for_upstream_stop }

          expect(log_lines[-2]).to eq(notice_for("IOError: #{spaced}"))
          body = log_lines[-2].delete_prefix('<!--').delete_suffix('-->')
          expect(body).not_to include('--')
          expect(body).not_to end_with('-')
        end
      end

      it 'drops the whitespace around the message' do
        run_xml(lines: [], upstream: type_then_fail(RuntimeError.new(" \tboom\n"))) { wait_for_upstream_stop }

        expect(log_lines[-2]).to eq(notice_for('RuntimeError: boom'))
      end

      # lich-5 stops a script by Thread#kill on its threads (script.rb kill);
      # the default upstream stand-in ends the thread that way.
      it 'says nothing and leaves no line when the thread is killed, as ;kill log does' do
        run_xml(lines: ['<output>line 1</output>']) { sleep 0.05 }

        expect(echoes).to eq([started_echo])
        expect(log_lines).to eq([default_header, '<output>line 1</output>', default_footer])
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

        expect { run_xml }.to raise_error(Errno::ENOSPC)

        expect(opened.size).to eq(1)
        expect(opened.first).to be_closed
        expect(File.read(log_file)).to eq('')
      end
    end

    it 'keeps a comma in a quoted --timestamp format' do
      run_xml(args: '--timestamp="%b %d, %H:%M"')

      expect(log_lines).to eq(['Apr 23, 10:00', 'Apr 23, 10:00: <output>You see a door.</output>', 'Apr 23, 10:00'])
    end

    # Q-08: the options text mode has and logxml 0.6.6 lacked.
    context 'with the options it shares with text mode' do
      it 'starts a new file after --lines written lines' do
        run_xml(args: '--lines=1', lines: ['<output>line 1</output>', '<output>line 2</output>'])

        month = File.join(log_dir, 'logs', 'GSIV-TestChar', '2026', '04')
        expect(Dir.children(month).sort).to eq(['2026-04-23_10-00-05.xml', '2026-04-23_10-00-05_01.xml'])
        expect(File.read(File.join(month, '2026-04-23_10-00-05_01.xml')).lines(chomp: true))
          .to eq([default_header, '<output>line 2</output>', default_footer])
      end

      it 'skips the lines read in an --exclude room, by its u-id' do
        allow(XMLData).to receive(:room_id).and_return(7199)

        run_xml(args: '--exclude=u7199')

        expect(log_lines).to eq([default_header, default_footer])
      end

      it 'keeps pushStream and popStream lines with --streams' do
        stream_lines = ['<pushStream id="inv"/>', '<output>In the pack: a torch.</output>', '<popStream/>']

        run_xml(args: '--streams', lines: stream_lines)

        expect(log_lines).to eq([default_header, *stream_lines, default_footer])
      end

      it 'turns --rnum on only for the whole option, not for --rnumber' do
        map = double('Map', loaded?: true, ids_from_uid: [228])
        stub_const('Map', map)
        title_line = '<resource picture="0"/><style id="roomName" />[Town Square]'

        run_xml(args: '--rnumber', lines: [title_line])

        expect(log_lines).to eq([default_header, title_line, default_footer])
        expect(map).not_to have_received(:ids_from_uid)
      end
    end

    # R-02: the files ;log --xml writes (and log.lic run under the name
    # logxml, as an install's local logxml.lic 0.7.x runs it), against the files
    # logxml.lic 0.6.1 (the release this merge started from, kept verbatim in
    # spec/fixtures/scripts/logxml-0.6.1.lic) writes, from the same input in
    # the same harness. Every difference is a fix the ledger lists: the
    # footer when the logger stops (R-23), no "\r" at the end of reget lines
    # (R-15), no blank line for an empty reget (R-14), the first line after
    # midnight in the new day's file (R-13), LOG_DIR (R-24), and, without
    # streams, the line inside the inventory stream left out (R-06).
    # There is no fixture for logxml.lic 0.6.6, the last version before
    # ;logxml ran log.lic. The layer-09 review replayed the lich-5 stream
    # fixtures through 0.6.6, the 0.7.0 shim and ;log --xml out of tree (472 runs
    # over options, the reget window and timestamp settings): files, echoes
    # and script flags matched except where logxml.lic 0.7.0's changelog said they
    # change (the word rnum turns room numbers on; a bare --timestamp
    # echoes that it is ignored).
    describe 'against logxml.lic 0.6.1 on the same input' do
      let(:base_path) { File.expand_path('../fixtures/scripts/logxml-0.6.1.lic', __dir__) }
      let(:base_lines) { File.readlines(base_path) }
      let(:base_body_line) { base_lines.index { |l| l.start_with?('=end') } + 2 }
      let(:logs_dir) { Dir.mktmpdir }
      let(:marker) { '<!-- Above contents from reget; full logging now active -->' }
      let(:footer) { "#{default_footer}\n" }
      # Server lines verbatim from lich-5 spec/fixtures/streams/gs_saga_hunt.xml,
      # with the "\r" line ends lich-5 keeps in $_SERVERBUFFER_.
      let(:server_lines) do
        [
          "<style id=\"\"/><style id=\"roomDesc\"/>The tiled ground is chipped, resembling run down cobblestones.<style id=\"\"/>\r",
          "<compass><dir value=\"n\"/><dir value=\"e\"/></compass><prompt time=\"1792091316\">&gt;</prompt>\r",
          "<pushStream id=\"inv\"/>a torch<popStream/>\r"
        ]
      end
      let(:game_lines) do
        [
          '<pushStream id="inv"/>',
          '<output>In the pack: a torch.</output>',
          '<popStream/>',
          "<dialogData id='minivitals'>",
          '<resource picture="0"/><style id="roomName" />[Town Square] (1234)',
          '  1d100: 20 + Modifiers: 372 == 392'
        ]
      end

      after { FileUtils.rm_rf(logs_dir) }

      # Every file written under LICH_DIR or LOG_DIR: "LICH_DIR/<path>" or
      # "LOG_DIR/<path>" => its bytes.
      def files_written
        { 'LICH_DIR' => log_dir, 'LOG_DIR' => logs_dir }.flat_map do |label, root|
          Dir.glob(File.join(root, '**', '*')).select { |path| File.file?(path) }.map do |path|
            ["#{label}#{path.delete_prefix(root)}", File.binread(path)]
          end
        end.to_h
      end

      # Runs one logger on the same input and returns files_written: :base
      # is logxml.lic 0.6.1, :log_xml log.lic started with --xml, and
      # :logxml_name log.lic run under the name logxml without --xml, as an
      # install's local logxml.lic 0.7.x runs it. The typed commands are
      # read first (get waits for the upstream thread to push each one),
      # then +lines+; a Time among them moves the clock.
      def run_one(which, args:, lines:, typed:, server_buffer:)
        FileUtils.rm_rf(Dir.glob(File.join(log_dir, '*')) + Dir.glob(File.join(logs_dir, '*')))
        LogSpecHarness.reset!
        clock[0] = frozen_time
        name, run_args = which == :log_xml ? ['log', "--xml #{args}".strip] : ['logxml', args]
        LogSpecHarness.start_script(run_args, name: name)
        LogSpecHarness.server_buffer = server_buffer
        LogSpecHarness.type(typed)
        pending = lines.dup
        typed_left = typed.size
        allow(LogSpecHarness).to receive(:get) do
          if typed_left.positive?
            typed_left -= 1
            next LogSpecHarness::DOWNSTREAM.pop(timeout: 2) || raise('the upstream thread pushed no typed command')
          end
          clock[0] = pending.shift while pending.first.is_a?(Time)
          next pending.shift.dup unless pending.empty?

          raise StopIteration
        end
        threads = Thread.list
        Timeout.timeout(5) do
          case which
          when :base then LogSpecHarness::Env.module_eval(base_lines.drop(base_body_line - 1).join, base_path, base_body_line)
          else LogSpecHarness.run_whole_script
          end
        end
        # The upstream thread ends on the empty buffer; wait for it, so it
        # cannot read the next run's typed commands.
        (Thread.list - threads).each { |thread| thread.join(2) }
        files_written
      end

      # The three runs on the same input.
      def run_all(args: '', lines: game_lines, typed: ['<c>look'], server_buffer: server_lines)
        %i[base log_xml logxml_name].to_h { |which| [which, run_one(which, args: args, lines: lines, typed: typed, server_buffer: server_buffer)] }
      end

      # R-15: lich-5's reget leaves the server's "\r" at the end of each line;
      # only the lines before the reget marker are reget lines.
      def without_reget_cr(bytes)
        reget, live = bytes.split(marker, 2)
        reget.delete("\r") + marker + live
      end

      let(:xml_file) { 'LICH_DIR/logs/GSIV-TestChar/2026/04/2026-04-23_10-00-05.xml' }

      # R-06: 0.6.1 dropped the pushStream and popStream lines of
      # game_lines and kept the line between them, which is inventory stream
      # content; log.lic 1.3.2 leaves out all three without streams.
      # The line, with its timestamp when it has one.
      let(:inv_span_line) { %r{^[^\n]*<output>In the pack: a torch\.</output>\n} }

      def without_inv_span_line(bytes)
        expect(bytes).to match(inv_span_line)
        bytes.sub(inv_span_line, '')
      end

      context 'when started within the reget window' do
        before { $login_time = frozen_time - 5 }

        it 'differs only by the reget lines without "\r" (R-15), the inventory stream line (R-06) and the footer when it stops (R-23)' do
          runs = run_all

          expect(runs[:base].keys).to eq([xml_file])
          expect(runs[:base][xml_file]).to include("\r\n")
          expect(runs[:log_xml]).to eq(xml_file => without_inv_span_line(without_reget_cr(runs[:base][xml_file])) + footer)
          expect(runs[:logxml_name]).to eq(runs[:log_xml])
        end

        it 'differs the same way with a quoted --timestamp, the reget unstamped in both' do
          runs = run_all(args: '--timestamp="%F %T"')

          expect(runs[:base][xml_file]).to start_with("2026-04-23 10:00:05\n<style")
          expect(runs[:log_xml]).to eq(xml_file => "#{without_inv_span_line(without_reget_cr(runs[:base][xml_file]))}2026-04-23 10:00:05\n")
          expect(runs[:logxml_name]).to eq(runs[:log_xml])
        end

        # R-14: lich-5's reget answers nil for an empty buffer, and puts(nil)
        # wrote a blank line.
        it 'differs by no blank line for an empty reget (R-14), the inventory stream line (R-06) and the footer (R-23)' do
          runs = run_all(server_buffer: [])

          expect(runs[:base][xml_file]).to start_with("#{default_header}\n\n#{marker}\n")
          expect(runs[:log_xml]).to eq(xml_file => without_inv_span_line(runs[:base][xml_file].sub("#{default_header}\n\n", "#{default_header}\n")) + footer)
          expect(runs[:logxml_name]).to eq(runs[:log_xml])
        end
      end

      context 'when started more than 30 seconds after login' do
        it 'differs only by the inventory stream line (R-06) and the footer (R-23)' do
          runs = run_all

          expect(runs[:base][xml_file]).not_to include(marker)
          expect(runs[:log_xml]).to eq(xml_file => without_inv_span_line(runs[:base][xml_file]) + footer)
          expect(runs[:logxml_name]).to eq(runs[:log_xml])
        end

        it 'differs only by the footer (R-23) with streams' do
          runs = run_all(args: 'streams')

          expect(runs[:base][xml_file]).to include('<pushStream id="inv"/>')
          expect(runs[:log_xml]).to eq(xml_file => runs[:base][xml_file] + footer)
          expect(runs[:logxml_name]).to eq(runs[:log_xml])
        end

        # 0.6.1 took the Lich number from Map.current; log.lic takes it from
        # the map's UID table (R-05). For a room both place, the Lich number
        # matches; the title already shows the room's UID (1234), so the
        # second u-id 0.6.1 added is gone (R-12).
        it 'differs only by the inventory stream line (R-06), the footer (R-23) and the u-id kept off a title showing (1234) (R-12) with --rnum' do
          stub_const('Map', double('Map', loaded?: true, current: double('Room', id: 228)))
          allow(Map).to receive(:ids_from_uid).with(1234).and_return([228])

          runs = run_all(args: '--rnum')

          expect(runs[:base][xml_file]).to include('<style id="roomName" />[Town Square - 228] (u1234) (1234)')
          expect(runs[:log_xml]).to eq(
            xml_file => without_inv_span_line(runs[:base][xml_file]).sub('[Town Square - 228] (u1234) (1234)', '[Town Square - 228] (1234)') + footer
          )
          expect(runs[:log_xml][xml_file]).to include('<style id="roomName" />[Town Square - 228] (1234)')
          expect(runs[:logxml_name]).to eq(runs[:log_xml])
        end

        # R-24: Lich's --logs= sets LOG_DIR; 0.6.1 wrote under LICH_DIR/logs.
        it 'writes under LOG_DIR (R-24) the same bytes but the inventory stream line (R-06), and the footer (R-23)' do
          stub_const('LOG_DIR', logs_dir)

          runs = run_all

          expect(runs[:base].keys).to eq([xml_file])
          expect(runs[:log_xml]).to eq('LOG_DIR/GSIV-TestChar/2026/04/2026-04-23_10-00-05.xml' => without_inv_span_line(runs[:base][xml_file]) + footer)
          expect(runs[:logxml_name]).to eq(runs[:log_xml])
        end

        # R-13: 0.6.1 wrote the line before checking the date.
        it "moves the first line after midnight to the new day's file (R-13), each file with its footer (R-23)" do
          next_day = Time.new(2026, 4, 24, 0, 0, 1)
          next_day_footer = "#{next_day.strftime('%Y-%m-%d %H:%M:%S.%L %:z')}\n"
          next_file = 'LICH_DIR/logs/GSIV-TestChar/2026/04/2026-04-24_00-00-01.xml'

          runs = run_all(lines: ['<output>line 1</output>', next_day, '<output>line 2</output>'], typed: [])

          expect(runs[:base]).to eq(
            xml_file  => "#{default_header}\n<output>line 1</output>\n<output>line 2</output>\n#{next_day_footer}",
            next_file => "2026-04-24 12:00am\n"
          )
          expect(runs[:log_xml]).to eq(
            xml_file  => runs[:base][xml_file].sub("<output>line 2</output>\n", ''),
            next_file => "#{runs[:base][next_file]}<output>line 2</output>\n#{next_day_footer}"
          )
          expect(runs[:logxml_name]).to eq(runs[:log_xml])
        end
      end
    end
  end

  # USER-1 (2026-11-11): logxml.lic is no longer in the repository; ;log
  # --xml writes the XML log. bin/repo deletes a scripts/ file removed here
  # from the Lich repository server, and repository.lic must then stop
  # handing it to new installs as a default updatable script and stop
  # moving its owner to elanthia-online as a core script, as it does for
  # log.lic.
  RSpec.describe 'logxml.lic removed from the repository (USER-1)' do
    let(:scripts_dir) { File.expand_path('../../scripts', __dir__) }
    let(:repository) { File.read(File.join(scripts_dir, 'repository.lic')) }

    it 'is not in the scripts folder, while log.lic is' do
      expect(File.exist?(File.join(scripts_dir, 'logxml.lic'))).to be(false)
      expect(File.file?(File.join(scripts_dir, 'log.lic'))).to be(true)
    end

    it 'is not among the default scripts repository.lic makes updatable, while log.lic is' do
      defaults = repository.scan(/^\s*add_default_script\('([^']+)'/).flatten

      expect(defaults).to include('log.lic')
      expect(defaults).not_to include('logxml.lic')
    end

    it 'is not among the core scripts whose owner repository.lic sets to elanthia-online' do
      core = repository[/%w\[(repository\.lic [^\]]*)\]/, 1]

      expect(core.to_s.split).to include('log.lic')
      expect(core.to_s.split).not_to include('logxml.lic')
    end
  end
end
