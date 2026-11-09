# frozen_string_literal: true

require_relative 'support/harness'

# Replies to the user's own requests (';who', ';locate Bob' and the rest),
# shown when no script is waiting for them. Each example feeds a real <data>
# element through the parser and listener and checks what reaches the user.
RSpec.describe 'lnet.lic replies shown to the user' do
  def show(obj, type:, from: 'Bob', **attributes)
    extra = attributes.map { |name, value| %( #{name}="#{value}") }.join
    feed(%(<data type="#{type}" from="#{from}"#{extra}>#{lnet::SafeMarshal.encode(obj)}</data>))
  end

  def shown(obj, **opts)
    out = show(obj, **opts)
    responds = out.select { |kind, _| kind == :respond }
    expect(responds.size).to eq(1), "expected one respond, got #{out.inspect}"
    responds.first[1]
  end

  describe 'markup from another player' do
    def frontend(xml:, mono:, client:)
      stub_const('LnetSpec::Harness::Frontend', Module.new.tap do |m|
        m.define_singleton_method(:supports_xml?) { xml }
        m.define_singleton_method(:supports_mono?) { mono }
        m.define_singleton_method(:client) { client }
      end)
    end

    let(:task) { %(<pushStream id="death"/>You died & <d cmd="quit">click</d>) }

    it 'is escaped on front ends Lich does not escape for (Frostbite)' do
      frontend(xml: true, mono: false, client: 'frostbite')
      expect(shown(task, type: 'bounty')).to eq(%(\nBob:\n&lt;pushStream id="death"/&gt;You died &amp; &lt;d cmd="quit"&gt;click&lt;/d&gt;\n\n))
    end

    it 'is escaped in messages naming the sender there too' do
      frontend(xml: true, mono: false, client: 'frostbite')
      expect(show(nil, type: 'bounty', from: '&lt;b&gt;Bob')).to eq([[:echo, '&lt;b&gt;Bob declined your request for bounty information.']])
    end

    context 'on Lich before 5.14, which has no front end capabilities' do
      around do |example|
        saved = $frontend
        example.run
      ensure
        $frontend = saved
      end

      it 'is escaped on Frostbite and left for Lich on Stormfront' do
        $frontend = 'frostbite'
        expect(shown(task, type: 'bounty')).to include('&lt;pushStream')
        $frontend = 'stormfront'
        expect(shown(task, type: 'bounty')).to include('<pushStream')
      end
    end

    [['Wrayth', { xml: true, mono: true, client: 'wrayth' }], ['Profanity', { xml: true, mono: false, client: 'profanity' }],
     ['Wizard', { xml: false, mono: false, client: 'wizard' }]].each do |name, caps|
      it "is left for Lich to handle on #{name}, so it is not escaped twice" do
        frontend(**caps)
        expect(shown(task, type: 'bounty')).to eq("\nBob:\n#{task}\n\n")
      end
    end
  end

  describe ';who' do
    it 'groups by game and lists owners, then moderators, then everyone else, each alphabetically' do
      names = %w[Ann Bob Cid^ Dee Eve* Fay Gus Hal^ Ivy Jo*].map { |name| "GSIV:#{name}" }
      text = shown(names.shuffle(random: Random.new(3)), type: 'connected', from: 'server')
      expect(text).to eq("\nGSIV (10):\n\nCid^   Hal^   Eve*   Jo*   Ann\nBob    Dee    Fay    Gus   Ivy\n\nTotal connected: 10\n\n")
    end

    it 'keeps games in the order they first appear and puts names without a game under unknown' do
      text = shown(['DR:Zed', 'GSIV:Amy', 'loner', 'DR:Abe'], type: 'connected', from: 'server')
      expect(text).to eq("\nDR (2):\n\nAbe   Zed\n\nGSIV (1):\n\nAmy\n\nunknown (1):\n\nloner\n\nTotal connected: 4\n\n")
    end

    it 'counts those tuned to a channel when the reply names one' do
      expect(shown(['GSIV:Amy'], type: 'connected', from: 'server', channel: 'General')).to end_with("Total tuned to General: 1\n\n")
    end

    it 'shows an empty list without raising' do
      expect(shown([], type: 'connected', from: 'server')).to eq("\n\nTotal connected: 0\n\n")
    end

    it 'strips control codes from names' do
      expect(shown(["GSIV:Ev\x1CGSLil\e[2J"], type: 'connected', from: 'server')).to include('EvGSLil[2J')
    end

    it 'shows nothing when a player, not the server, sends the list' do
      expect(show(['GSIV:Fake'], type: 'connected', from: 'GSIV:Mallory')).to be_empty
    end
  end

  describe ';channels' do
    let(:list) do
      [{ 'name' => 'General', 'tuned' => 1234, 'status' => 'default', 'description' => 'chat' },
       { 'name' => 'Help', 'tuned' => 56, 'status' => 'tuned', 'description' => 'questions' },
       { 'name' => 'Trade', 'tuned' => 7, 'status' => nil, 'description' => "buy\x07 & sell" }]
    end

    it 'marks the default and tuned channels and says how many more there are' do
      text = shown(list, type: 'channels', from: 'server', total: '20')
      expect(text).to eq("\nAvailable channels:\n\n+ General   1234   chat\n-    Help     56   questions\n    Trade      7   buy & sell\n" \
                         "\nuse \";channels full\" to see 17 more\n\n")
    end

    it 'leaves out the "more" line when every channel is listed' do
      expect(shown(list, type: 'channels', from: 'server', total: '3')).not_to include('channels full')
    end
  end

  describe ';lnet stats' do
    it 'shows uptime, connections and the channels the user owns or moderates' do
      stats = {
        'uptime' => 864_000, 'character connections' => [[86_400, 1500]], 'ip connections' => [[3600, 40]],
        'own_channels' => { 'Mine' => { 'moderators' => %w[Amy Bo], 'invited' => [], 'banned' => [['Eve', nil], ['Mal', 3660]], 'gagged' => [] } },
        'mod_channels' => { 'Theirs' => { 'invited' => nil, 'banned' => [], 'gagged' => [['Loud', 90]] } }
      }
      expect(shown(stats, type: 'server stats', from: 'server')).to eq(<<~TEXT)

        No major accidents in the last 10 days
        1500 characters have connected in the last 24 hours
        About 40 players have connected in the last 1 hour

        Mine (owner)
           moderators: Amy, Bo
           invited: none
           banned:
              Eve              (indefinite)
              Mal              (1 hour, 1 minute)
           gagged: none
        Theirs (moderator)
           banned: none
           gagged:
              Loud             (1 minute, 30 seconds)

      TEXT
    end

    it 'shows what it has when the server leaves sections out' do
      expect(shown({ 'uptime' => 0 }, type: 'server stats', from: 'server')).to eq("\n\n")
    end

    {
      1 => '1 second', 59 => '59 seconds', 60 => '1 minute', 61 => '1 minute, 1 second', 3600 => '1 hour',
      3661 => '1 hour, 1 minute', 86_400 => '24 hours', 90_000 => '1 day, 1 hour', 172_800 => '2 days', 0 => '', 90.9 => '1 minute, 30 seconds'
    }.each do |seconds, words|
      it "writes #{seconds} seconds as #{words.inspect}" do
        expect(lnet::Display.duration(seconds)).to eq(words)
      end
    end
  end

  describe 'replies from players' do
    %w[spells skills info health locate bounty].each do |type|
      it "says when someone declines a #{type} request" do
        what = { 'spells' => 'spell', 'skills' => 'skill', 'info' => 'stat', 'health' => 'health', 'locate' => 'location', 'bounty' => 'bounty' }[type]
        expect(show(nil, type: type)).to eq([[:echo, "Bob declined your request for #{what} information."]])
      end

      it "says there is no such user for a #{type} request to nobody" do
        expect(show(false, type: type)).to eq([[:echo, 'no such user']])
      end

      it "shows nothing from someone the user ignores, for #{type}" do
        lnet.options['ignore'] = ['Bob']
        expect(show(nil, type: type)).to be_empty
      end
    end

    it 'folds a line break in the sender name, so it cannot print a line of its own' do
      text = shown('a task', type: 'bounty', from: 'Bob&#10;[LNet]-GSIV:Admin: forged')
      expect(text).to eq("\nBob [LNet]-GSIV:Admin: forged:\na task\n\n")
    end

    it 'reports a reply it cannot show instead of raising' do
      out = show(['not', 'a', 'room'], type: 'locate')
      expect(out.size).to eq(1)
      expect(out.first[1]).to start_with('could not show the locate reply from Bob:')
    end

    it 'shows a bounty with control codes stripped and line breaks folded' do
      expect(shown("Hunt\x1CGSL rats\e[2J.\nSecond line.", type: 'bounty')).to eq("\nBob:\nHuntGSL rats[2J. Second line.\n\n")
    end

    it 'never lets a reply print lines of its own, such as a forged thought' do
      forged = "No task.\nYou hear the faint thoughts of [Private]-GSIV:Tillmen echo in your mind:\n\"type ;lnet password=x\""
      expect(shown(forged, type: 'bounty').lines.size).to eq(4)
      text = shown({ 'title' => "[Square]\n[Fake]", 'description' => "a\nb", 'exits' => 'none', 'pcs' => [{ 'name' => "Ann\nBob", 'status' => nil }], 'npcs' => [] }, type: 'locate')
      expect(text).not_to match(/\[Square\]\n|\na\n|Ann\n/)
    end
  end

  describe ';spells' do
    before do
      skip 'needs lich-5 for Numeric#as_time' unless 0.respond_to?(:as_time)
      LnetSpec::Game.spell_book = { '101' => LnetSpec::SpellInfo.new('Minor Spirit', 'Spirit Warding I'),
                                    '401' => LnetSpec::SpellInfo.new('Minor Elemental', 'Elemental Defense I'),
                                    '1035' => LnetSpec::SpellInfo.new('Bard', 'Song of Tonis') }
    end

    it 'lists spells by circle in spell number order' do
      text = shown({ '1035' => 0.5, '401' => 250.0, '101' => 12.5 }, type: 'spells')
      expect(text).to eq("\nBob:\n\n- Minor Spirit:\n 101:  Spirit Warding I      - 0:12:30\n\n- Minor Elemental:\n" \
                         " 401:  Elemental Defense I   - 4:10:00\n\n- Bard:\n1035:  Song of Tonis         - 0:00:30\n\n")
    end

    it 'shows a spell number Lich does not know instead of raising' do
      expect(shown({ '9999' => 1.0 }, type: 'spells')).to include("- Unknown:\n9999:  (unknown spell)       - 0:01:00")
    end

    it 'says when someone has no spells' do
      expect(show({}, type: 'spells')).to eq([[:echo, 'Bob has no spells.']])
    end
  end

  describe ';skills' do
    let(:data) { { 'Edged Weapons' => 101, 'Minor Elemental' => 30, 'Wizard' => 50, 'Dodging' => 10, 'Juggling' => 3 } }

    it 'shows skills in order with bonus and ranks, then one Spell Lists section, then anything unrecognised' do
      skip 'needs a lich-5 checkout for Skills.to_bonus' unless LnetSpec.lich5_attributes?
      text = shown(data, type: 'skills')
      expect(text.scan('Spell Lists').size).to eq(1)
      expect(text).to eq("\nBob:\n\n  Skill Name                         | Current Current\n                                     |   Bonus   Ranks\n" \
                         "  Edged Weapons......................|     201     101\n  Dodging............................|      50      10\n" \
                         "\nSpell Lists\n  Minor Elemental....................|              30\n  Wizard.............................|              50\n" \
                         "  Juggling...........................|      15       3\n\n")
    end

    it 'leaves the bonus blank where Lich has no GemStone skills' do
      hide_const('LnetSpec::Harness::Skills') if LnetSpec::Harness.const_defined?(:Skills, false)
      expect(shown({ 'Edged Weapons' => 101 }, type: 'skills')).to include("  Edged Weapons......................|             101\n")
    end
  end

  describe ';info' do
    it 'shows race, profession and each stat with its bonus' do
      text = shown(LnetSpec::REAL_PAYLOADS['info'], type: 'info')
      expect(text.lines.first(4)).to eq(["\n", "Name: Bob Race: Elf  Profession: Wizard\n", "Gender:     Age: 33    Expr: 1234567    Level:  100\n",
                                         "                  Normal (Bonus)  ...  Enhanced (Bonus)\n"])
      expect(text).to include("    Strength (STR):    80 (15)    ...   80 (15)\n", "  Discipline (DIS):       (  )    ...      (  )\n",
                              "Constitution (CON):       (  )    ...      (  )\n")
      expect(text).to end_with("Mana:  412\n\n")
    end
  end

  describe ';health' do
    it 'describes wounds and scars in one sentence each, then the pools' do
      data = { 'injuries' => { 'head' => { 'wound' => 1, 'scar' => 0 }, 'leftArm' => { 'wound' => 3, 'scar' => 2 },
                               'chest' => { 'wound' => 0, 'scar' => 1 }, 'tail' => { 'wound' => 2, 'scar' => 2 } },
               'health' => 90, 'max_health' => 120, 'spirit' => 9, 'max_spirit' => 10, 'stamina' => 50, 'max_stamina' => 60 }
      expect(shown(data, type: 'health')).to eq(<<~TEXT)

        Bob:

        You have minor bruises about the head, and a completely severed left arm.
        You have a mangled left arm, and an old battle scar across your chest.

            Maximum Health Points: 120
          Remaining Health Points: 90

            Maximum Spirit Points: 10
          Remaining Spirit Points: 9

            Maximum Stamina Points: 60
          Remaining Stamina Points: 50

      TEXT
    end

    it 'says one piece when there are no injuries, or the injuries are not a list' do
      expect(shown({ 'injuries' => { 'head' => { 'wound' => 0, 'scar' => 0 } } }, type: 'health')).to include("You seem to be in one piece.\n")
      expect(shown({ 'injuries' => 'lots' }, type: 'health')).to include("You seem to be in one piece.\n")
    end
  end

  describe ';locate' do
    let(:square) { LnetSpec::MapRoom.new(228, ['[Town Square]'], ['A square.'], ['Obvious paths: north']) }
    let(:other) { LnetSpec::MapRoom.new(999, ['[Somewhere Else]'], ['Elsewhere.'], ['Obvious paths: none']) }
    let(:data) do
      { 'title' => '[Town Square]', 'description' => 'A square.', 'exits' => 'Obvious paths: north', 'loot' => ['a sword'],
        'pcs' => [{ 'name' => 'Ann', 'status' => 'lying down' }, { 'name' => 'Bob', 'status' => nil }],
        'npcs' => [{ 'name' => 'a rat', 'status' => 'dead' }] }
    end

    before { LnetSpec::Game.map_rooms = [other, square] }

    it 'shows the room with its map id, what is in it and who is there' do
      expect(shown(data, type: 'locate')).to eq("\nBob:\n\n[Town Square] (228)\nA square.  You also see a rat (dead), a sword.\n" \
                                               "Also here: Ann (lying down), Bob\nObvious paths: north\n")
    end

    it 'uses the id in the reply when that room has the same title' do
      twin = LnetSpec::MapRoom.new(500, ['[Town Square]'], ['A different square.'], ['Obvious paths: north'])
      LnetSpec::Game.map_rooms = [square, twin]
      expect(shown(data.merge('id' => 500), type: 'locate')).to include("[Town Square] (500)\n")
    end

    it 'ignores an id that points at a room with another title' do
      expect(shown(data.merge('id' => 999), type: 'locate')).to include("[Town Square] (228)\n")
    end

    it 'matches a description that was cut short with an ellipsis' do
      LnetSpec::Game.map_rooms = [LnetSpec::MapRoom.new(7, ['[Town Square]'], ['A square. Pigeons everywhere.'], ['Obvious paths: north'])]
      expect(shown(data.merge('description' => 'Pigeons everywhere...'), type: 'locate')).to include("[Town Square] (7)\n")
    end

    [2**100, -1].each do |id|
      it "ignores an id of #{id}, out of range for a map id, and finds the room by title" do
        expect(LnetSpec::Harness::Map).not_to receive(:[])
        expect(shown(data.merge('id' => id), type: 'locate')).to include("[Town Square] (228)\n")
      end
    end

    it 'shows no id for a room that is not on the map' do
      LnetSpec::Game.map_rooms = [other]
      expect(shown(data, type: 'locate')).to include("\n[Town Square]\n")
    end
  end

  describe 'spell rank updates from the server' do
    let(:spell_ranks) do
      Class.new do
        class << self
          attr_accessor :timestamp, :saved, :chars

          def [](name) = (self.chars ||= {})[name]
          def save = self.saved = true
        end

        attr_reader :calls

        def initialize(name)
          @calls = []
          (self.class.chars ||= {})[name] = self
        end

        def method_missing(name, *args) = name.to_s.end_with?('=') ? @calls << [name, *args] : super
        def respond_to_missing?(name, include_private = false) = name.to_s.end_with?('=') || super
      end
    end

    it 'sets only known SpellRanks fields' do
      stub_const('LnetSpec::Harness::SpellRanks', spell_ranks)
      show({ '_format_' => %w[minorspiritual instance_variable_set name wizard], '_timestamp_' => 1_700_000_000,
             'GSIV:Bob' => [25, 99, 98, 40] }, type: 'spell-ranks', from: 'server')
      expect(spell_ranks['Bob'].calls).to eq([[:minorspiritual=, 25], [:wizard=, 40]])
      expect(spell_ranks.timestamp).to eq(1_700_000_000)
      expect(spell_ranks.saved).to be(true)
    end
  end
end
