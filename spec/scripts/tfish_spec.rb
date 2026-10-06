# frozen_string_literal: true

require_relative '../spec_helper'

# Spec for the pure TFish:: modules in tfish.lic (Ebon Gate fishing).
# tfish.lic runs `TFish.start` on load and needs a live game, so each pure
# module body is extracted verbatim and module_eval'd into a Harness
# namespace, the same approach as treim_spec.rb. Runner is not covered: it
# only drives live game commands.
#
# Game message fixtures are copied from real in-game logs of the FISH
# CAST / FISH REEL system.
module TFishSpec
  SOURCE_PATH = find_lic_source('tfish.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH)

  MODULES = %w[Config Messages Pole Weights Supplies Rooms].freeze

  FakeItem = Struct.new(:noun, :name)
  FakePc = Struct.new(:noun)

  module Harness
    UserVars = LichStub::UserVars

    MODULES.each do |name|
      module_eval(extract_lic_module(SOURCE, name, source_path: SOURCE_PATH), SOURCE_PATH)
    end
  end
end

RSpec.describe 'TFish' do
  let(:h) { TFishSpec::Harness }

  before { h::Config.setup! }

  describe 'Config' do
    it 'fills in defaults without overwriting existing settings' do
      LichStub::UserVars.tfish = { supplies_pole: 'pole' }
      h::Config.setup!

      expect(h::Config[:supplies_pole]).to eq('pole')
      expect(h::Config[:supplies_lure]).to eq('lure')
      expect(h::Config[:cast_distance]).to eq('far')
    end

    it 'falls back to far for an invalid cast distance' do
      h::Config.store[:cast_distance] = 'MIDDLE'
      expect(h::Config.cast_distance).to eq('middle')

      h::Config.store[:cast_distance] = 'yonder'
      expect(h::Config.cast_distance).to eq('far')
    end

    it 'only treats the constant weight as active when cycling is off and one is set' do
      expect(h::Config.constant_weight?).to be false

      h::Config.store[:weight_noncycle] = 'glaes'
      expect(h::Config.constant_weight?).to be false

      h::Config.store[:cycle_weights] = false
      expect(h::Config.constant_weight?).to be true
    end
  end

  describe 'Messages' do
    hooked = "You feel a brief jerk on your line before it begins to reel out wildly.  You manage to yank your black fishing pole back to set the hook.  The pole bends and its tip dips as the catch on your line weaves back and forth in a frantic effort to escape!"
    caught = "You give your black fishing pole one final tug and the sand bass comes wriggling to the surface!  Moving swiftly, you quickly unhook it from the line and take hold of it tightly."
    long_pole_caught = "You give your twisted black fishing pole adorned with tiny fish skulls one final tug and the albino cod comes wriggling to the surface!  Moving swiftly, you quickly unhook it from the line and take hold of it tightly."

    it 'recognizes the hook being set' do
      expect(hooked).to match(h::Messages::HOOKED)
    end

    it 'captures the fish name when landed, whatever the pole is called' do
      expect(caught.match(h::Messages::CAUGHT)[:fish]).to eq('sand bass')
      expect(long_pole_caught.match(h::Messages::CAUGHT)[:fish]).to eq('albino cod')
    end

    it 'classifies reel replies' do
      expect(h::Messages.reel_outcome(caught)).to eq(:caught)
      expect(h::Messages.reel_outcome('Your line suddenly twists and then breaks with a sharp, poignant *SNAP*!')).to eq(:lost)
      expect(h::Messages.reel_outcome('Roundtime: 8 sec.')).to eq(:reeling)
      expect(h::Messages.reel_outcome(nil)).to be_nil
    end

    it 'waits on roundtime, catch and loss replies when reeling' do
      expect('Roundtime: 5 sec.').to match(h::Messages::REEL_REPLY)
      expect(caught).to match(h::Messages::REEL_REPLY)
      expect('Your hook is now about 244 feet away.').not_to match(h::Messages::REEL_REPLY)
    end

    it 'reads pounds from a weigh reply' do
      expect(h::Messages.pounds('You carefully examine the black fishing pole and determine that the weight is about 5 pounds.')).to eq('5')
      expect(h::Messages.pounds('...wait 2 seconds.')).to be_nil
      expect(h::Messages.pounds(nil)).to be_nil
    end
  end

  describe 'Pole.parse' do
    rigged = <<~LOOK
      The line of the black fishing pole is cast out into the water about 254 feet away.

      The line is almost completely still, leading you to believe that the ebon gate lure attached to it is resting on the bottom.

      A small silver weight is currently strung from the line of the pole to serve as a weight.  The weight looks like it is heavy enough to sink a line to the bottom of a body of water.

      The line itself looks to be in excellent condition.

      A twisted iron ebon gate lure dangling a tiny gold key is currently attached near the hook to attract fish.

      The lure has the following qualities:

          +12 to attracting fish near the surface
    LOOK

    it 'reads line condition, lure and weight' do
      state = h::Pole.parse(rigged)

      expect(state.line).to eq('excellent')
      expect(state.lure).to eq('twisted iron ebon gate lure dangling a tiny gold key')
      expect(state.weight).to eq('small silver weight')
    end

    it 'exposes the weight noun so sinkers and weights both come off the pole' do
      expect(h::Pole.parse(rigged).weight_noun).to eq('weight')
      expect(h::Pole.parse('An iron sinker is currently strung from the line of the rod to serve as a weight.').weight_noun).to eq('sinker')
    end

    # Wear levels from https://gswiki.play.net/Fishing_equipment. Only the
    # "excellent" sentence has been seen in a real log; the others assume the
    # same "The line itself looks ..." lead-in.
    {
      'The line itself looks to be in excellent condition.'          => ['excellent', false],
      'The line itself looks to be in decent condition.'             => ['decent', false],
      'The line itself looks to be showing signs of wear.'           => ['showing signs of wear', false],
      'The line itself looks frayed and in danger of snapping soon.' => ['frayed and in danger of snapping soon', true],
    }.each do |sentence, (condition, frayed)|
      it "reads line wear: #{condition}" do
        state = h::Pole.parse(sentence)

        expect(state.line).to eq(condition)
        expect(state.frayed?).to be frayed
      end
    end

    it 'reports nothing rigged on a bare pole' do
      state = h::Pole.parse('You see nothing unusual.')

      expect(state).to eq(h::Pole::State.new(line: nil, lure: nil, weight: nil))
    end
  end

  describe 'Weights' do
    it 'rotates top, middle, bottom' do
      expect((0..3).map { h::Weights.depth(it) }).to eq(%w[Top Middle Bottom Top])
    end

    it 'picks no weight, then the depths weight, then the bottom weight' do
      expect((0..2).map { h::Weights.for_cast(it) }).to eq([nil, 'blown glass weight', 'glaes weight'])
    end
  end

  describe 'Supplies.shortages' do
    item = TFishSpec::FakeItem

    def stocked(count)
      Array.new(count) { TFishSpec::FakeItem.new('weight', 'blown glass weight') } +
        Array.new(count) { TFishSpec::FakeItem.new('weight', 'glaes weight') }
    end

    it 'is empty when line and both cycling weights are stocked' do
      expect(h::Supplies.shortages(stocked(5) + [item.new('wire', 'fishing wire')])).to be_empty
    end

    it 'reports missing line and short weights' do
      expect(h::Supplies.shortages(stocked(4))).to eq([
                                                        'Fishing Line - wire - 0/1',
                                                        'blown glass weight - 4/5',
                                                        'glaes weight - 4/5',
                                                      ])
    end

    it 'checks only the constant weight when cycling is off' do
      h::Config.store[:cycle_weights] = false
      h::Config.store[:weight_noncycle] = 'glaes'

      expect(h::Supplies.shortages(stocked(5) + [item.new('wire', 'fishing wire')])).to be_empty
      expect(h::Supplies.shortages([item.new('wire', 'fishing wire')])).to eq(['Constant Weight - glaes - 0/5'])
    end

    it 'treats a missing container as empty' do
      expect(h::Supplies.shortages(nil)).to include('Fishing Line - wire - 0/1')
    end
  end

  describe 'Rooms' do
    it 'knows the dock and entrance' do
      expect(h::Rooms.fishing?(32117)).to be true
      expect(h::Rooms.fishing?(h::Rooms::ENTRANCE)).to be false
      expect(h::Rooms.ebon_gate?(h::Rooms::ENTRANCE)).to be true
      expect(h::Rooms.ebon_gate?(1)).to be false
    end

    it 'does not count fishing bots toward the crowd' do
      pcs = %w[Fishmon Ilten Tysong].map { TFishSpec::FakePc.new(it) }

      expect(h::Rooms.crowd(pcs)).to eq(1)
      expect(h::Rooms.crowd(nil)).to eq(0)
    end

    it 'picks the least crowded room, first on ties' do
      expect(h::Rooms.least_crowded({ 32116 => 2, 32117 => 0, 32118 => 0 })).to eq(32117)
    end
  end
end
