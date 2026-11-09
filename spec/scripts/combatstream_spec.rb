# frozen_string_literal: true

require 'tmpdir'
require_relative '../spec_helper'

# Spec for combatstream.lic. The script can't be required standalone (it
# needs the Lich runtime and starts routing on load), so its Classifier and
# Router bodies are extracted verbatim and module_eval'd into a spec-local
# Harness, the same way treim_spec.rb does.
#
# Router is tested against a stub classifier, so its stream/prompt/block
# rules need no lich-5 at all. Classifier is tested against the REAL lich-5
# Gemstone combat definitions from the local or CI-pinned checkout (see
# lich5_path in spec_helper.rb), since "does lich-5 recognize this line" is
# the whole point of it; those examples skip when no checkout is available.
module CombatStreamSpec
  SOURCE_PATH = find_lic_source('combatstream.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH)

  CLASSIFIER_SRC = extract_lic_module(SOURCE, 'Classifier', source_path: SOURCE_PATH)
  HOOK_OPTIONS_SRC = extract_lic_method(SOURCE, 'hook_options', source_path: SOURCE_PATH)
  SUMMARY_SRC = extract_lic_module(SOURCE, 'Summary', source_path: SOURCE_PATH)
  COMPRESSOR_SRC = extract_lic_module(SOURCE, 'Compressor', kind: 'class', source_path: SOURCE_PATH)
  ROUTER_SRC = extract_lic_module(SOURCE, 'Router', kind: 'class', source_path: SOURCE_PATH)

  module Harness; end
  Harness.module_eval(CLASSIFIER_SRC, SOURCE_PATH)
  Harness.module_eval(ROUTER_SRC, SOURCE_PATH)
  Harness.const_set(:HOOK_PRIORITY, SOURCE[/HOOK_PRIORITY = (-?[\d_]+)/, 1].delete('_').to_i)
  Harness.module_eval(HOOK_OPTIONS_SRC, SOURCE_PATH)
  Harness.module_eval(SUMMARY_SRC, SOURCE_PATH)
  Harness.module_eval(COMPRESSOR_SRC, SOURCE_PATH)

  # Loads the real Gemstone combat defs and crit tables from lich-5, or
  # returns false when there is no checkout. They resolve DATA_DIR/LIB_DIR
  # lexically inside `module Lich`, so defining them on Lich (not at the top
  # level) is enough and can't leak into other specs.
  def self.load_lich5_defs
    root = lich5_path
    return false unless root && File.exist?(File.join(root, 'lib/gemstone/combat/parser.rb'))

    lib = File.join(root, 'lib')
    Lich.const_set(:DATA_DIR, Dir.mktmpdir('combatstream_spec')) unless Lich.const_defined?(:DATA_DIR, false)
    Lich.const_set(:LIB_DIR, lib) unless Lich.const_defined?(:LIB_DIR, false)
    require File.join(lib, 'gemstone/combat/parser')
    messages = File.join(lib, 'gemstone/combat/defs/messages.rb')
    require messages if File.exist?(messages)
    require File.join(lib, 'gemstone/critranks')
    true
  end

  # lich-5's Processor, for the end-to-end summary check -- only builds that
  # emit whole attack events (newer than 5.21), which is what --compress
  # needs. Loaded on demand from that example.
  def self.load_processor
    return false unless LICH5_DEFS

    path = File.join(lich5_path, 'lib/gemstone/combat/processor.rb')
    return false unless File.exist?(path) && File.read(path).include?("'combat.attack'")

    require path
    true
  rescue LoadError, NameError => e
    warn "combatstream_spec: lich-5 Processor not loaded: #{e.class}: #{e.message}"
    false
  end

  module ::Lich; module Gemstone; end; end
  LICH5_DEFS = load_lich5_defs

  CONSTRUCT = '<pushBold/>a <a exist="37507821" noun="construct">greater construct</a><popBold/>'
  THE_CONSTRUCT = '<pushBold/>the <a exist="37507821" noun="construct">greater construct</a><popBold/>'
  PROMPT = "<prompt time=\"1758500000\">&gt;</prompt>\r\n"

  # One real round (lich-5 spec/fixtures/replay/attack.txt), as the game
  # sends it: one server string per line, ending at the prompt.
  ROUND = [
    "You swing a perfect mithril war-hammer at #{CONSTRUCT}!\r\n",
    "  AS: +351 vs DS: +299 with AvD: +22 + d100 roll: +88 = +162\r\n",
    "   ... and hit for 20 points of damage!\r\n",
    "   Torn muscle in #{THE_CONSTRUCT}'s left leg!\r\n",
    " ** Necrotic energy from your mithril war-hammer overflows into you! **\r\n",
    "   You feel energized!\r\n",
    "Roundtime: 4 sec.\r\n"
  ].freeze
end

RSpec.describe 'combatstream.lic' do
  let(:harness) { CombatStreamSpec::Harness }

  describe 'Router' do
    let(:combat_lines) { [] }
    let(:classifier) { ->(line) { combat_lines.include?(line) ? :attack : nil } }
    let(:mode) { :block }
    let(:router) { harness::Router.new(classifier, mode: mode) }

    def wrapped(line, id = 'CombatStream')
      "<pushStream id=\"#{id}\"/>#{line.chomp}\r\n<popStream/>\r\n"
    end

    let(:attack) { "You swing a mace at #{CombatStreamSpec::CONSTRUCT}!\r\n" }
    let(:flavor) { "The greater construct gurgles once and goes still.\r\n" }

    before { combat_lines << attack }

    it 'defaults to the CombatStream stream, not the game\'s own "combat"' do
      expect(harness::Router::DEFAULT_STREAM).to eq('CombatStream')
    end

    it 'wraps a combat line in its own push/pop pair' do
      expect(router.call(attack)).to eq(wrapped(attack))
    end

    it 'uses the configured stream id' do
      other = harness::Router.new(classifier, stream: 'fight')
      expect(other.call(attack)).to eq(wrapped(attack, 'fight'))
    end

    it 'passes non-combat lines through unchanged' do
      line = "Also here: Bob.\r\n"
      expect(router.call(line)).to equal(line)
    end

    it 'never touches the prompt' do
      router.call(attack)
      expect(router.call(CombatStreamSpec::PROMPT)).to equal(CombatStreamSpec::PROMPT)
    end

    context 'in block mode' do
      it 'routes unrecognized lines that follow a combat line, up to the prompt' do
        router.call(attack)
        expect(router.call(flavor)).to eq(wrapped(flavor))
        expect(router.call("\r\n")).to eq(wrapped("\r\n"))
        router.call(CombatStreamSpec::PROMPT)
        expect(router.call(flavor)).to eq(flavor)
      end

      it 'leaves unrecognized lines before the first combat line alone' do
        expect(router.call(flavor)).to eq(flavor)
      end

      it 'ends the block at a room change' do
        router.call(attack)
        room = "<style id=\"roomName\" />[Old Ta'Faendryl, River Bank]\r\n"
        expect(router.call(room)).to eq(room)
        expect(router.call(flavor)).to eq(flavor)
      end

      it 'keeps speech in the story window mid-fight' do
        router.call(attack)
        speech = "<preset id='speech'>Bob says,</preset> \"Nice hit!\"\r\n"
        expect(router.call(speech)).to eq(speech)
      end
    end

    context 'mirroring the line before a combat block' do
      let(:setup) { "You leap from hiding to strike!\r\n" }

      it 'copies it into the stream ahead of the combat line, leaving the original in place' do
        expect(router.call(setup)).to equal(setup)
        expect(router.call(attack)).to eq(wrapped(setup) + wrapped(attack))
      end

      it 'copies only at the start of a block, not for lines inside it' do
        router.call(setup)
        router.call(attack)
        expect(router.call(flavor)).to eq(wrapped(flavor))
      end

      it 'does not reach back past a prompt' do
        router.call(setup)
        router.call(CombatStreamSpec::PROMPT)
        expect(router.call(attack)).to eq(wrapped(attack))
      end

      it 'skips blank lines to find it' do
        router.call(setup)
        router.call("\r\n")
        expect(router.call(attack)).to eq(wrapped(setup) + wrapped(attack))
      end

      it 'never copies speech, structural tags or text in a server stream' do
        [
          "<preset id='speech'>Bob says,</preset> \"Go!\"\r\n",
          "<style id=\"roomName\" />[Castle Anwyn]\r\n",
          "<pushStream id=\"familiar\" />Your raven croaks.<popStream/>\r\n"
        ].each do |line|
          fresh = harness::Router.new(classifier)
          fresh.call(line)
          expect(fresh.call(attack)).to eq(wrapped(attack))
        end
      end

      it 'copies every story line since the last prompt, in order' do
        lunge = "A greater construct lunges forward!\r\n"
        router.call(CombatStreamSpec::PROMPT)
        router.call(setup)
        router.call(lunge)
        expect(router.call(attack)).to eq(wrapped(setup) + wrapped(lunge) + wrapped(attack))
      end

      it 'leaves speech out without losing the lines around it' do
        lunge = "A greater construct lunges forward!\r\n"
        router.call(setup)
        router.call("<preset id='speech'>Bob says,</preset> \"Look out!\"\r\n")
        router.call(lunge)
        expect(router.call(attack)).to eq(wrapped(setup) + wrapped(lunge) + wrapped(attack))
      end

      it 'starts over at a room change' do
        router.call(setup)
        router.call("<style id=\"roomName\" />[Castle Anwyn]\r\n")
        after = "A greater construct lumbers in.\r\n"
        router.call(after)
        expect(router.call(attack)).to eq(wrapped(after) + wrapped(attack))
      end

      it "holds at most #{CombatStreamSpec::Harness::Router::MIRROR_LIMIT} lines" do
        limit = harness::Router::MIRROR_LIMIT
        lines = (1..(limit + 5)).map { |i| "Line #{i}.\r\n" }
        lines.each { |line| router.call(line) }
        expected = lines.last(limit).map { |line| wrapped(line) }.join + wrapped(attack)
        expect(router.call(attack)).to eq(expected)
      end

      it 'is off with mirror: false' do
        plain = harness::Router.new(classifier, mirror: false)
        plain.call(setup)
        expect(plain.call(attack)).to eq(wrapped(attack))
      end

      it 'reports the copy to the debug callback' do
        seen = []
        debug_router = harness::Router.new(classifier, debug: ->(family, line) { seen << [family, line] })
        debug_router.call(setup)
        debug_router.call(attack)
        expect(seen).to eq([[:mirror, setup], [:attack, attack]])
      end
    end

    context 'mirroring commands sent since the last prompt' do
      let(:log) { [] }
      let(:router) { harness::Router.new(classifier, commands: -> { log.dup }) }
      let(:leap) { "You leap from hiding to attack!\r\n" }

      def send_command(entry)
        log << entry.dup
      end

      before { combat_lines << leap }

      it 'shows a script command as the story window does, ahead of the fight' do
        router.call(CombatStreamSpec::PROMPT)
        send_command("[bigshot]><c>ambush #382609757 right leg\r\n")
        expect(router.call(leap)).to eq(wrapped('[bigshot]>ambush #382609757 right leg') + wrapped(leap))
      end

      it 'shows a typed command with the prompt character' do
        router.call(CombatStreamSpec::PROMPT)
        send_command('<c>attack kobold')
        expect(router.call(leap)).to eq(wrapped('>attack kobold') + wrapped(leap))
      end

      it 'puts commands before the story lines leading into the fight' do
        router.call(CombatStreamSpec::PROMPT)
        send_command('<c>ambush kobold')
        setup = "You slip out of the shadows.\r\n"
        router.call(setup)
        expect(router.call(leap)).to eq(wrapped('>ambush kobold') + wrapped(setup) + wrapped(leap))
      end

      it 'leaves out commands sent before the last prompt' do
        send_command('<c>look')
        router.call(CombatStreamSpec::PROMPT)
        expect(router.call(leap)).to eq(wrapped(leap))
      end

      it 'counts the same command sent again as new' do
        send_command('<c>ambush kobold')
        router.call(CombatStreamSpec::PROMPT)
        send_command('<c>ambush kobold')
        expect(router.call(leap)).to eq(wrapped('>ambush kobold') + wrapped(leap))
      end

      it 'mirrors each command once' do
        router.call(CombatStreamSpec::PROMPT)
        send_command('<c>ambush kobold')
        router.call(leap)
        router.call(CombatStreamSpec::PROMPT)
        expect(router.call(leap)).to eq(wrapped(leap))
      end

      it 'escapes markup in the command' do
        router.call(CombatStreamSpec::PROMPT)
        send_command('<c>say <grin> & run')
        expect(router.call(leap)).to eq(wrapped('>say &lt;grin> &amp; run') + wrapped(leap))
      end

      it 'is off with mirror: false' do
        quiet = harness::Router.new(classifier, mirror: false, commands: -> { log.dup })
        quiet.call(CombatStreamSpec::PROMPT)
        send_command('<c>ambush kobold')
        expect(quiet.call(leap)).to eq(wrapped(leap))
      end

      it 'reports each command to the debug callback' do
        seen = []
        debug_router = harness::Router.new(classifier, commands: -> { log.dup }, debug: ->(family, line) { seen << [family, line] })
        debug_router.call(CombatStreamSpec::PROMPT)
        send_command('<c>ambush kobold')
        debug_router.call(leap)
        expect(seen).to eq([[:command, '>ambush kobold'], [:attack, leap]])
      end
    end

    context 'in line mode' do
      let(:mode) { :line }

      it 'routes only recognized lines' do
        expect(router.call(attack)).to eq(wrapped(attack))
        expect(router.call(flavor)).to eq(flavor)
      end
    end

    context 'when the server opens a stream of its own' do
      it 'does not nest inside it, and resumes after it closes' do
        push = "<pushStream id=\"combat\" />You swing a mace at #{CombatStreamSpec::CONSTRUCT}!\r\n"
        expect(router.call(push)).to eq(push)
        expect(router.call(attack)).to eq(attack)
        pop = "<popStream id=\"combat\" />\r\n"
        expect(router.call(pop)).to eq(pop)
        expect(router.call(attack)).to eq(wrapped(attack))
      end

      it 'resets at the prompt if the server never closed it' do
        router.call("<pushStream id=\"familiar\" />Your raven croaks.\r\n")
        router.call(CombatStreamSpec::PROMPT)
        expect(router.call(attack)).to eq(wrapped(attack))
      end
    end

    it 'never wraps a string carrying structural tags' do
      comp = "<component id='room objs'>You also see #{CombatStreamSpec::CONSTRUCT}.</component>\r\n"
      combat_lines << comp
      expect(router.call(comp)).to eq(comp)
    end

    it 'keeps bold tags balanced inside each wrapped string' do
      out = router.call(attack)
      expect(out.scan('<pushBold/>').size).to eq(out.scan('<popBold/>').size)
      expect(out.scan('<pushStream').size).to eq(out.scan('<popStream').size)
    end

    it 'reports the family of each routed line to the debug callback' do
      seen = []
      debug_router = harness::Router.new(classifier, debug: ->(family, line) { seen << [family, line] })
      debug_router.call(attack)
      debug_router.call(flavor)
      expect(seen).to eq([[:attack, attack], [:block, flavor]])
    end
  end

  describe 'Router in compress mode' do
    let(:rounds) { [] }
    let(:combat_lines) { [] }
    let(:classifier) { ->(line) { combat_lines.include?(line) ? :attack : nil } }
    let(:log) { [] }
    let(:router) do
      harness::Router.new(classifier, commands: -> { log.dup },
                                      compress: ->(time, commands, raw) { rounds << [time, commands, raw] })
    end
    let(:attack) { "You swing a mace at #{CombatStreamSpec::CONSTRUCT}!\r\n" }
    let(:flavor) { "The greater construct gurgles once and goes still.\r\n" }

    before { combat_lines << attack }

    it 'hides the round and hands it over at the prompt, stamped with its server time' do
      router.call(CombatStreamSpec::PROMPT)
      log << '<c>attack construct'
      setup = "You lunge forward.\r\n"
      expect(router.call(setup)).to equal(setup)
      expect(router.call(attack)).to be_nil
      expect(router.call(flavor)).to be_nil
      expect(rounds).to be_empty
      expect(router.call(CombatStreamSpec::PROMPT)).to equal(CombatStreamSpec::PROMPT)
      expect(rounds).to eq([[1_758_500_000, ['>attack construct'], [setup, attack, flavor]]])
    end

    it 'hands over nothing for a round without combat' do
      router.call("Obvious paths: north.\r\n")
      router.call(CombatStreamSpec::PROMPT)
      expect(rounds).to be_empty
    end

    it 'leaves speech and structure in the story window mid-fight' do
      router.call(attack)
      speech = "<preset id='speech'>Bob says,</preset> \"Nice!\"\r\n"
      expect(router.call(speech)).to eq(speech)
    end
  end

  describe 'Summary' do
    let(:construct) { { id: 37_507_821, noun: 'construct', name: 'greater construct' } }
    let(:kobold) { { id: 11, noun: 'kobold', name: 'kobold' } }

    def event(**fields)
      { name: :attack, target: {}, attacker: nil, inbound: nil, foreign_caster: nil,
        hits: [], flares: [], outcomes: [], statuses: [] }.merge(fields)
    end

    def crit(location, rank, **extra)
      { type: 'crush', location: location, rank: rank, fatal: false, stunned: 0 }.merge(extra)
    end

    def lines(events, hp: nil)
      harness::Summary.lines(events, hp: hp)
    end

    it 'totals our swing on a creature: damage, hits, crits and flares' do
      swing = event(target: construct, hits: [{ damage: 20, crit: crit('left leg', 1) }],
                    flares: [{ name: :ensorcell, hits: [], outcomes: [] }])
      expect(lines([swing])).to eq(['greater construct: 20 dmg, 1 hit, L leg r1, ensorcell'])
    end

    it 'sums every swing and flare on the same creature in the round' do
      one = event(target: construct, hits: [{ damage: 20, crit: crit('right arm', 2) }])
      two = event(target: construct, hits: [{ damage: 15, crit: nil }],
                  flares: [{ name: :fire_flare, hits: [{ damage: 12, crit: crit('chest', 3) }], outcomes: [] }])
      expect(lines([one, two])).to eq(['greater construct: 47 dmg, 2 hits, R arm r2, chest r3, fire flare'])
    end

    it 'shows what a creature did to us, including what we avoided' do
      inbound = event(inbound: true, attacker: construct, outcomes: [:evade])
      expect(lines([inbound])).to eq(['you: 0 dmg (1 evaded)'])
    end

    it 'marks a kill and leaves the HP estimate off' do
      swing = event(target: construct, hits: [{ damage: 40, crit: crit('head', 9, fatal: true) }])
      expect(lines([swing], hp: ->(_id) { 10 })).to eq(['greater construct: 40 dmg, 1 hit, head r9 -- killed'])
    end

    it 'adds the HP estimate when one is known' do
      swing = event(target: construct, hits: [{ damage: 20, crit: nil }])
      expect(lines([swing], hp: ->(id) { id == construct[:id] ? 64 : nil }))
        .to eq(['greater construct: 20 dmg, 1 hit [~64% hp]'])
    end

    it 'credits a flare that names another creature to that creature' do
      swing = event(target: construct, hits: [{ damage: 5, crit: nil }],
                    flares: [{ name: :lightning, target_info: kobold, hits: [{ damage: 9, crit: nil }], outcomes: [] }])
      expect(lines([swing])).to eq(['greater construct: 5 dmg, 1 hit', 'kobold: 9 dmg, lightning'])
    end

    it "credits a reactive flare on a creature's attack to that attacker, not to us" do
      inbound = event(inbound: true, attacker: construct, hits: [{ damage: 7, crit: nil }],
                      flares: [{ name: :spikes, hits: [{ damage: 4, crit: nil }], outcomes: [] }])
      expect(lines([inbound])).to eq(['you: 7 dmg, 1 hit', 'greater construct: 4 dmg, spikes'])
    end

    it "keeps another player's attack apart from ours" do
      theirs = event(foreign_caster: true, attacker: { id: -5, name: 'Bob' }, target: construct,
                     hits: [{ damage: 30, crit: nil }])
      expect(lines([theirs])).to eq(['Bob on greater construct: 30 dmg, 1 hit'])
    end

    it 'lists stuns from crits and statuses the attack applied' do
      swing = event(target: construct, hits: [{ damage: 10, crit: crit('neck', 4, stunned: 2) }], statuses: [:prone])
      expect(lines([swing])).to eq(['greater construct: 10 dmg, 1 hit, neck r4, stunned, prone'])
    end

    it 'skips an event with nothing to show' do
      expect(lines([event(target: construct)])).to be_empty
    end
  end

  describe 'Compressor' do
    let(:summaries) { [] }
    let(:compressor) do
      harness::Compressor.new(lambda { |events|
        summaries << events
        events.map { |e| "summary of #{e[:name]}" }
      })
    end
    let(:wait) { harness::Compressor::ROUND_WAIT }

    def batch_event(id, index, size, at, name = :attack)
      { name: name, at: Time.at(at), observation_batch: { id: id, index: index, size: size } }
    end

    it 'replaces a round with the summary of its batch, after the commands' do
      expect(compressor.add_round(100, ['>attack'], ['raw'], now: 0)).to eq([])
      expect(compressor.add_event(batch_event(1, 0, 1, 100), now: 0.01)).to eq([['>attack', 'summary of attack']])
      expect(compressor).not_to be_waiting
    end

    it 'waits for every event in the batch' do
      compressor.add_round(100, [], ['raw'], now: 0)
      expect(compressor.add_event(batch_event(1, 0, 2, 100, :swing), now: 0)).to eq([])
      expect(compressor.add_event(batch_event(1, 1, 2, 100, :flare), now: 0)).to eq([['summary of swing', 'summary of flare']])
    end

    it 'pairs a batch that arrives before its round' do
      expect(compressor.add_event(batch_event(1, 0, 1, 100), now: 0)).to eq([])
      expect(compressor.add_round(100, [], ['raw'], now: 0.01)).to eq([['summary of attack']])
    end

    it 'accepts a round one second off (server time offset read a prompt apart)' do
      compressor.add_round(101, [], ['raw'], now: 0)
      expect(compressor.add_event(batch_event(1, 0, 1, 100), now: 0)).to eq([['summary of attack']])
    end

    it 'shows a round as-is when no batch comes in time' do
      compressor.add_round(100, ['>look'], ['raw 1', 'raw 2'], now: 0)
      expect(compressor.tick(now: wait - 0.1)).to eq([])
      expect(compressor.tick(now: wait)).to eq([['>look', 'raw 1', 'raw 2']])
    end

    it 'shows an earlier waiting round as-is once a later batch completes' do
      compressor.add_round(100, [], ['first'], now: 0)
      compressor.add_round(105, [], ['second'], now: 0)
      expect(compressor.add_event(batch_event(1, 0, 1, 105), now: 0)).to eq([['first'], ['summary of attack']])
    end

    it 'shows the round as-is when the summary comes out empty' do
      quiet = harness::Compressor.new(->(_events) { [] })
      quiet.add_round(100, [], ['raw'], now: 0)
      expect(quiet.add_event(batch_event(1, 0, 1, 100), now: 0)).to eq([['raw']])
    end

    it 'drops a batch no round ever claims' do
      compressor.add_event(batch_event(1, 0, 1, 100), now: 0)
      expect(compressor.tick(now: harness::Compressor::BATCH_KEEP + 1)).to eq([])
      expect(compressor).not_to be_waiting
    end

    it 'ignores events without batch information' do
      expect(compressor.add_event({ name: :attack }, now: 0)).to eq([])
      expect(compressor).not_to be_waiting
    end
  end

  describe 'hook_options' do
    it 'runs our hook last where the registry supports priorities (current lich-5)' do
      registry = Class.new { def self.add(_name, _action, persist: nil, priority: 0); end }
      expect(harness.hook_options(registry)).to eq(persist: false, priority: harness::HOOK_PRIORITY)
      expect(harness::HOOK_PRIORITY).to be_negative
    end

    it 'passes only what an older registry accepts (lich-5 5.21)' do
      registry = Class.new { def self.add(_name, _action, persist: nil); end }
      expect(harness.hook_options(registry)).to eq(persist: false)
    end
  end

  describe 'Classifier (real lich-5 combat definitions)' do
    before { skip 'no lich-5 checkout (set LICH5_PATH)' unless CombatStreamSpec::LICH5_DEFS }

    let(:families) { harness::Classifier.build(Lich::Gemstone) }

    def classify(line)
      harness::Classifier.classify(families, line)
    end

    it 'recognizes each kind of combat line in a real round' do
      round = CombatStreamSpec::ROUND
      expect(classify(round[0])).to eq(:attack)
      expect(classify(round[1])).to eq(:resolution)
      expect(classify(round[2])).to eq(:damage)
      expect(classify(round[3])).to eq(:crit)
      expect(classify(round[4])).to eq(:flare)
    end

    it 'recognizes evades' do
      expect(classify("You dodge just in the nick of time!\r\n")).to eq(:outcome)
    end

    it 'ignores ordinary story text' do
      expect(classify("Obvious paths: north, east.\r\n")).to be_nil
      expect(classify("You feel energized!\r\n")).to be_nil
    end

    it "summarizes lich-5's own parse of a real round" do
      skip 'lich-5 here has no whole-attack events (needs newer than 5.21)' unless CombatStreamSpec.load_processor

      stub_const('Lich::Gemstone::Combat::Tracker', Module.new)
      allow(Lich::Gemstone::Combat::Tracker).to receive_messages(
        settings: { track_statuses: true, track_ucs: true, emit_attacks: true, track_damage: true, track_wounds: true },
        debug?: false
      )
      events = Lich::Gemstone::Combat::Processor.parse_events(CombatStreamSpec::ROUND.map(&:chomp),
                                                              include_attack_events: true)
      expect(harness::Summary.lines(events)).to eq(['greater construct: 20 dmg, 1 hit, L leg r1, ensorcell'])
    end

    it 'routes a whole round, flavor lines included, and nothing after the prompt' do
      router = harness::Router.new(->(line) { harness::Classifier.classify(families, line) })
      out = CombatStreamSpec::ROUND.map { |line| router.call(line) }
      expect(out).to all(start_with('<pushStream id="CombatStream"/>'))
      expect(router.call(CombatStreamSpec::PROMPT)).to eq(CombatStreamSpec::PROMPT)
      expect(router.call("Obvious paths: north.\r\n")).to eq("Obvious paths: north.\r\n")
    end
  end
end
