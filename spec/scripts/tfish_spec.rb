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

  # Every constant tfish.lic assigns has to be in its module's removal list
  # (the `%i[...].each { remove_const }` line at the top of each module), or
  # a rerun in the same Lich session warns about redefining it.
  it 'lists every constant it defines for removal on rerun' do
    listed = TFishSpec::SOURCE.scan(/%i\[([^\]]*)\]\.each \{ \|name\| remove_const/).flatten.flat_map(&:split)
    assigned = TFishSpec::SOURCE.scan(/^ +([A-Z][A-Za-z_]*) = /).flatten

    expect(listed).to match_array(assigned)
  end

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

    it 'defaults to no weight cycling' do
      expect(h::Config[:cycle_weights]).to be false
    end

    it 'turns off weight cycling saved by pre-2.0 tfish, once' do
      LichStub::UserVars.tfish = { cycle_weights: true }
      h::Config.setup!
      expect(h::Config[:cycle_weights]).to be false

      h::Config.store[:cycle_weights] = true
      h::Config.setup!
      expect(h::Config[:cycle_weights]).to be true
    end

    it 'lists every setting with its value, flagging changed ones' do
      h::Config.store[:supplies_pole] = 'pole'
      listing = h::Config.listing

      expect(listing.lines.size).to eq(h::Config::DEFAULTS.size + 1)
      expect(listing).to match(/^  supplies_pole +"pole"  \(default "rod"\)$/)
      expect(listing).to match(/^  cast_distance +"far"$/)
    end

    it 'only treats the constant weight as active when cycling is off and one is set' do
      expect(h::Config.constant_weight?).to be false

      h::Config.store[:weight_noncycle] = 'glaes'
      expect(h::Config.constant_weight?).to be true

      h::Config.store[:cycle_weights] = true
      expect(h::Config.constant_weight?).to be false
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
      expect(h::Messages.reel_outcome('The line of your black fishing pole strains and breaks with a sharp *SNAP*!')).to eq(:lost)
      expect(h::Messages.reel_outcome('You reel the line of your black fishing pole in.  The snowflake lure strung on the line breaks the surface and dangles briefly over the water as you finish retracting the line.')).to eq(:empty)
      expect(h::Messages.reel_outcome('But the pole is already reeled in!')).to eq(:empty)
      expect(h::Messages.reel_outcome('Roundtime: 8 sec.')).to eq(:reeling)
      expect(h::Messages.reel_outcome(nil)).to be_nil
    end

    it 'waits on roundtime, catch, snap and empty-line replies when reeling' do
      expect('Roundtime: 5 sec.').to match(h::Messages::REEL_REPLY)
      expect(caught).to match(h::Messages::REEL_REPLY)
      expect('Your hook is now about 244 feet away.').not_to match(h::Messages::REEL_REPLY)
      expect('You take in some of the slack from the line of your black fishing pole.').not_to match(h::Messages::REEL_REPLY)
    end

    it 'does not treat the run-out-of-line warning as a snap' do
      expect('Your reel lets out a groan of protest as it runs out of line to give!').not_to match(h::Messages::REEL_REPLY)
    end

    # Ebon Gate docks are shared: other players' fishing lines arrive in the
    # same stream and must never be taken for your own.
    it "ignores other players' hook, snap and catch lines" do
      others = [
        "Remzsii's sugar cane rod bends slightly and its tip dips.  She swiftly gives the rod a tug to set the hook!",
        "The line of Lakishiie's fishing rod strains and breaks with a sharp *SNAP*!",
        'Kenzsii gives her sugar cane rod one final tug and a dark brown yellow-finned batfish comes wriggling to the surface!  Moving swiftly, she takes in the rest of her line and unhooks the batfish, then takes hold of it tightly.',
        "Remzsii's sugar cane rod lets out a groan of protest as it runs out of line to give!",
      ]

      others.each do |line|
        expect(line).not_to match(h::Messages::HOOKED)
        expect(line).not_to match(h::Messages::REEL_REPLY)
      end
    end

    it 'fails a cast with no free hand right away instead of waiting for a reply' do
      expect("You can't cast without a free hand.").to match(h::Messages::CAST_FAIL)
    end

    it 'finds what cutting the line dropped at your feet' do
      plain = 'With a swift, sharp tug, you snap the line of your fishing rod.  Your freckled grey squid falls to the ground at your feet.'
      xml = 'With a swift, sharp tug, you snap the line of your <a exist="1234" noun="rod">fishing rod</a>.  ' \
            'Your <a exist="5678" noun="squid">freckled grey squid</a> falls to the ground at your feet.'

      expect(plain.match(h::Messages::AT_FEET).named_captures).to eq('id' => nil, 'noun' => nil, 'name' => 'freckled grey squid')
      expect(xml.match(h::Messages::AT_FEET).named_captures).to eq('id' => '5678', 'noun' => 'squid', 'name' => 'freckled grey squid')
    end

    it 'recognizes an overfished spot' do
      overfished = "It looks like this area has been heavily overfished.  You'll need to wait some time before you can fish here again."

      expect(overfished).to match(h::Messages::OVERFISHED)
      expect(overfished).not_to match(h::Messages::CAST_OK)
    end

    it 'tells a cast apart from a failed one' do
      cast = 'You lean back and let the line of your black fishing pole go with a sharp *WHOOSH!*  The freckled grey squid attached near the hook flies through the air before landing with a soft *plink* right off of the side of the jetty.'
      already = "You've already cast the line of your black fishing pole and will need to pull on your black fishing pole to reel it in."

      expect(cast).to match(h::Messages::CAST_OK)
      expect(already).to match(h::Messages::CAST_OK)
      expect('You must be holding a fishing rod.').to match(h::Messages::CAST_FAIL)
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
          +12 to attracting fish at middle depths
          +16 to attracting fish in deep water
    LOOK

    it 'reads line condition, lure and weight' do
      state = h::Pole.parse(rigged)

      expect(state.line).to eq('excellent')
      expect(state.lure).to eq('twisted iron ebon gate lure dangling a tiny gold key')
      expect(state.weight).to eq('small silver weight')
    end

    it 'reads the lure bonus for each depth' do
      state = h::Pole.parse(rigged)

      expect(state.lure_bonus).to eq(surface: 12, middle: 12, deep: 16)
      expect(state.best_depth).to eq(:deep)
      expect(state.surface_lure?).to be false
    end

    it 'counts a lure that is best (or tied best) at the surface as a surface lure' do
      snowflake = h::Pole.parse(<<~LOOK)
        A pale snowflake lure is currently attached near the hook to attract fish.
        The lure has the following qualities:
            +15 to attracting fish near the surface
            +10 to attracting fish at middle depths
            +10 to attracting fish in deep water
      LOOK
      tied = h::Pole.parse("    +12 to attracting fish near the surface\n    +12 to attracting fish in deep water")

      expect(snowflake.surface_lure?).to be true
      expect(snowflake.best_depth).to eq(:surface)
      expect(tied.surface_lure?).to be true
    end

    it 'does not flag a lure whose bonuses are unknown' do
      expect(h::Pole.parse('A pale snowflake lure is currently attached near the hook to attract fish.').surface_lure?).to be true
    end

    it 'reads a pole with no weight, using the line wording shown when unweighted' do
      state = h::Pole.parse(<<~LOOK)
        The pole's line looks to be in excellent condition.
        A dead-eyed freckled grey squid is currently attached near the hook to attract fish.
        The squid has the following qualities:
            +16 to attracting fish near the surface
            +12 to attracting fish at middle depths
            +12 to attracting fish in deep water
      LOOK

      expect(state).to eq(h::Pole::State.new(line: 'excellent', lure: 'dead-eyed freckled grey squid', weight: nil,
                                             lure_bonus: { surface: 16, middle: 12, deep: 12 }))
    end

    it 'sees a fresh line with no lure after restringing' do
      state = h::Pole.parse("The pole's line looks to be in excellent condition.")

      expect(state.line).to eq('excellent')
      expect(state.lure).to be_nil
    end

    it 'exposes the weight noun so sinkers and weights both come off the pole' do
      expect(h::Pole.parse(rigged).weight_noun).to eq('weight')
      expect(h::Pole.parse('An iron sinker is currently strung from the line of the rod to serve as a weight.').weight_noun).to eq('sinker')
    end

    # Wear levels from https://gswiki.play.net/Fishing_equipment. Only
    # "excellent" has been seen in a real log, in both lead-ins ("The line
    # itself" with a weight on, "The pole's line" without); the other levels
    # assume the same sentence shape.
    {
      'The line itself looks to be in excellent condition.'          => ['excellent', false],
      "The pole's line looks to be in excellent condition."          => ['excellent', false],
      "The rod's line looks to be in decent condition."              => ['decent', false],
      "The pole's line looks to be showing signs of wear."           => ['showing signs of wear', false],
      'The line itself looks frayed and in danger of snapping soon.' => ['frayed and in danger of snapping soon', true],
    }.each do |sentence, (condition, frayed)|
      it "reads line wear: #{condition}" do
        state = h::Pole.parse(sentence)

        expect(state.line).to eq(condition)
        expect(state.frayed?).to be frayed
      end
    end

    # LOOK is captured as XML, so the start pattern sees tags; it must catch
    # your pole's first line but not a neighbour's fishing line.
    it "starts capturing on your pole description, not on other players' lines" do
      starts = [
        'The <a exist="709969844" noun="pole">pole\'s</a> line looks to be frayed and in danger of snapping soon.',
        "The rod's line looks to be in excellent condition.",
        'The line of the <a exist="1" noun="pole">black fishing pole</a> is cast out into the water about 95 feet away.',
        'The line itself looks to be in excellent condition.',
        'A small silver weight is currently strung from the line of the pole to serve as a weight.',
        'You take a closer look at a twisted black fishing pole adorned with tiny fish skulls.',
        'You see nothing unusual.',
      ]
      others = [
        "The line of Kenzsii's sugar cane rod zigzags back and forth wildly as her catch struggles against her!",
        "The tension on the line of Maziie's sugar cane rod vanishes for a heartbeat.",
        "Remzsii's sugar cane rod lets out a groan of protest as it runs out of line to give!",
        '<a exist="2" noun="Rippee">Rippee</a> leans back and lets the line of his black fishing pole go with a sharp *WHOOSH!*',
      ]

      starts.each { expect(it).to match(h::Pole::LOOK_START) }
      others.each { expect(it).not_to match(h::Pole::LOOK_START) }
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

  describe 'depth lures' do
    it 'fishes the surface with no weight, rotates when cycling, and is unknown with a constant weight' do
      expect(h::Weights.fishing_depth(1)).to eq('Top')

      h::Config.store[:cycle_weights] = true
      expect((0..2).map { h::Weights.fishing_depth(it) }).to eq(%w[Top Middle Bottom])

      h::Config.store[:cycle_weights] = false
      h::Config.store[:weight_noncycle] = 'glaes'
      expect(h::Weights.fishing_depth(0)).to be_nil
    end

    it 'uses the lure set for each depth, and none when unset' do
      h::Config.store[:lure_middle] = 'skull-shaped lure'

      expect(h::Weights.lure_for('Middle')).to eq('skull-shaped lure')
      expect(h::Weights.lure_for('Top')).to be_nil
      expect(h::Weights.lure_for(nil)).to be_nil
    end
  end

  describe 'Supplies.shortages' do
    item = TFishSpec::FakeItem

    def stocked(count)
      Array.new(count) { TFishSpec::FakeItem.new('weight', 'blown glass weight') } +
        Array.new(count) { TFishSpec::FakeItem.new('weight', 'glaes weight') }
    end

    it 'only needs line by default, since no weight is used' do
      expect(h::Supplies.shortages([item.new('wire', 'fishing wire')])).to be_empty
      expect(h::Supplies.shortages([])).to eq(['Fishing Line - wire - 0/1'])
    end

    it 'is empty when line and both cycling weights are stocked' do
      h::Config.store[:cycle_weights] = true
      expect(h::Supplies.shortages(stocked(5) + [item.new('wire', 'fishing wire')])).to be_empty
    end

    it 'reports missing line and short weights' do
      h::Config.store[:cycle_weights] = true
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

    it 'needs one of each depth lure that is set and in use' do
      h::Config.store[:lure_surface] = 'mandrake lure'
      h::Config.store[:lure_deep] = 'ebon gate lure'
      wire = item.new('wire', 'fishing wire')
      mandrake = item.new('lure', 'leaf-topped grey mandrake lure with tiny thorn teeth')

      expect(h::Supplies.shortages([wire, mandrake])).to be_empty
      expect(h::Supplies.shortages([wire])).to eq(['Lure - mandrake lure - 0/1'])

      h::Config.store[:cycle_weights] = true
      expect(h::Supplies.shortages(stocked(5) + [wire, mandrake])).to eq(['Lure - ebon gate lure - 0/1'])
    end

    it 'matches items by words, the way you would in game' do
      mandrake = 'leaf-topped grey mandrake lure'

      expect(h::Supplies.named?(mandrake, 'grey lure')).to be true
      expect(h::Supplies.named?(mandrake, 'mandrake lure')).to be true
      expect(h::Supplies.named?(mandrake, 'Leaf-Topped Grey')).to be true
      expect(h::Supplies.named?(mandrake, 'gre lur')).to be true
      expect(h::Supplies.named?('pale carved skull-shaped lure', 'skull lure')).to be true
      expect(h::Supplies.named?(mandrake, 'skull lure')).to be false
      expect(h::Supplies.named?('blown glass weight', 'glaes weight')).to be false
      expect(h::Supplies.named?(nil, 'grey lure')).to be false
    end

    it 'treats a missing container as empty' do
      expect(h::Supplies.shortages(nil)).to include('Fishing Line - wire - 0/1')
    end
  end

  describe 'Supplies.check' do
    item = TFishSpec::FakeItem
    surface_squid = "The rod's line looks to be in excellent condition.\n" \
                    "A dead-eyed freckled grey squid is currently attached near the hook to attract fish.\n" \
                    "    +16 to attracting fish near the surface\n    +12 to attracting fish at middle depths\n    +12 to attracting fish in deep water"
    let(:knife_box) { [item.new('dagger', 'drake dagger')] }
    let(:supplies) { [item.new('rod', 'flexible fishing rod'), item.new('wire', 'ball of indigo fishing wire')] }

    def statuses(rows) = rows.to_h { |status, text| [text[/^[^:(]+/].strip, status] }

    it 'passes a default surface setup with a surface lure on the pole' do
      rows = h::Supplies.check(supplies, knife_box, h::Pole.parse(surface_squid))

      expect(rows.map(&:first)).to all(eq(:ok))
    end

    # From a real ;tfish check: supplies_lure set to the in-game style name
    # "grey mandrake lure" counted 0 spares when compared against the noun.
    it 'finds gear set by name, not just by noun' do
      h::Config.store[:supplies_lure] = 'grey mandrake lure'
      h::Config.store[:supplies_pole] = 'black pole'
      contents = [item.new('pole', 'twisted black fishing pole'), item.new('wire', 'ball of dark braided fishing wire')] +
                 Array.new(10) { item.new('lure', 'leaf-topped grey mandrake lure') }
      rows = h::Supplies.check(contents, knife_box, h::Pole.parse("The pole's line looks to be frayed and in danger of snapping soon."))

      expect(rows).to include([:ok, 'Lure: none on the pole, 10 spare grey mandrake lure'],
                              [:warn, 'Line on the pole: frayed and in danger of snapping soon, will be cut and replaced before fishing'])
      expect(rows.map(&:first) - [:warn]).to all(eq(:ok))
    end

    it 'flags a missing pole, spare line and knife' do
      rows = h::Supplies.check([], [], nil)

      expect(statuses(rows)).to include('Pole' => :missing, 'Spare line' => :missing, 'Knife' => :missing, 'Lure' => :missing)
    end

    it 'checks both cycling weights and every depth lure that is set' do
      h::Config.store[:cycle_weights] = true
      h::Config.store[:lure_surface] = 'grey lure'
      h::Config.store[:lure_middle] = 'skull lure'
      contents = supplies + Array.new(5) { item.new('weight', 'blown glass weight') } +
                 [item.new('lure', 'leaf-topped grey mandrake lure')]
      rows = h::Supplies.check(contents, knife_box, h::Pole.parse(surface_squid))

      expect(rows).to include([:ok, 'Weight blown glass weight: 5/5'], [:missing, 'Weight glaes weight: 0/5'],
                              [:ok, 'Top lure (grey lure): leaf-topped grey mandrake lure'],
                              [:missing, 'Middle lure (skull lure): not found'])
      expect(rows.map(&:last).grep(/Bottom lure/)).to be_empty
    end

    it 'warns when surface fishing with a lure that is better deeper' do
      deep = surface_squid.sub('+16 to attracting fish near the surface', '+12 to attracting fish near the surface')
                          .sub('+12 to attracting fish in deep water', '+16 to attracting fish in deep water')
      rows = h::Supplies.check(supplies, knife_box, h::Pole.parse(deep))

      expect(rows.last).to eq([:warn, 'dead-eyed freckled grey squid is better at deep depth than the surface'])
    end
  end

  describe 'Rooms' do
    it 'tells a dock entrance apart from its fishing spots' do
      dock = h::Rooms.dock(1)

      expect(dock.fishing?(32117)).to be true
      expect(dock.fishing?(dock.entrance)).to be false
      expect(dock.here?(dock.entrance)).to be true
      expect(dock.here?(1)).to be false
    end

    it 'defaults to dock 1 and picks a dock by number' do
      expect(h::Rooms.dock).to eq(h::Rooms::DOCKS[1])
      expect(h::Rooms.dock(3).entrance).to eq(32074)
      expect(h::Rooms.dock('3').spots).to eq([32120, 32121, 32122])
    end

    it 'picks a dock by part of its name' do
      expect(h::Rooms.dock('moss').name).to eq('Moss Pond')
      expect(h::Rooms.dock('Misty Waters').entrance).to eq(31846)
    end

    it 'falls back to dock 1 for an unknown dock' do
      expect(h::Rooms.dock(9)).to eq(h::Rooms::DOCKS[1])
      expect(h::Rooms.dock('nowhere')).to eq(h::Rooms::DOCKS[1])
      expect(h::Rooms.dock('')).to eq(h::Rooms::DOCKS[1])
    end

    # Room ids from elanthia-online/mapdb-backup-gs: each entrance is tagged
    # fishing..fishing4, and every dock's three spots link to each other.
    it 'has four docks with unique entrances and spots' do
      docks = h::Rooms::DOCKS.values

      expect(docks.size).to eq(4)
      expect(docks.map(&:entrance).uniq.size).to eq(4)
      expect(docks.flat_map(&:spots).uniq.size).to eq(12)
    end

    it 'accepts a custom dock for one not listed yet' do
      dock = h::Rooms.dock({ entrance: 40000, spots: [40001, '40002'] })

      expect(dock.entrance).to eq(40000)
      expect(dock.spots).to eq([40001, 40002])
    end

    it 'moves to the next spot on the dock, wrapping around' do
      dock = h::Rooms.dock(1)

      expect(dock.next_spot(32116)).to eq(32117)
      expect(dock.next_spot(32118)).to eq(32116)
      expect(dock.next_spot(dock.entrance)).to eq(32116)
      expect(dock.next_spot(nil)).to eq(32116)
    end

    it 'finds which known dock a room is on' do
      expect(h::Rooms.dock_at(32121)).to eq(h::Rooms::DOCKS[3])
      expect(h::Rooms.dock_at(32073)).to eq(h::Rooms::DOCKS[4])
      expect(h::Rooms.dock_at(31834)).to eq(h::Rooms::DOCKS[1])
      expect(h::Rooms.dock_at(1)).to be_nil
      expect(h::Rooms.dock_at(nil)).to be_nil
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
