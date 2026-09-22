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
  ROUTER_SRC     = extract_lic_module(SOURCE, 'Router', kind: 'class', source_path: SOURCE_PATH)

  module Harness; end
  Harness.module_eval(CLASSIFIER_SRC, SOURCE_PATH)
  Harness.module_eval(ROUTER_SRC, SOURCE_PATH)

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
    let(:router) { harness::Router.new(classifier, stream: 'combat', mode: mode) }

    def wrapped(line, id = 'combat')
      "<pushStream id=\"#{id}\"/>#{line.chomp}\r\n<popStream/>\r\n"
    end

    let(:attack) { "You swing a mace at #{CombatStreamSpec::CONSTRUCT}!\r\n" }
    let(:flavor) { "The greater construct gurgles once and goes still.\r\n" }

    before { combat_lines << attack }

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

    it 'routes a whole round, flavor lines included, and nothing after the prompt' do
      router = harness::Router.new(->(line) { harness::Classifier.classify(families, line) })
      out = CombatStreamSpec::ROUND.map { |line| router.call(line) }
      expect(out).to all(start_with('<pushStream id="combat"/>'))
      expect(router.call(CombatStreamSpec::PROMPT)).to eq(CombatStreamSpec::PROMPT)
      expect(router.call("Obvious paths: north.\r\n")).to eq("Obvious paths: north.\r\n")
    end
  end
end
