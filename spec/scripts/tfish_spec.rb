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

  MODULES = %w[Config Messages Pole Weights Supplies Tackle Rooms Familiar Setup].freeze

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
      expect(h::Config[:depths]).to eq(%w[surface])
      expect(h::Config[:distances]).to eq(%w[far])
      expect(h::Config[:lure_bottom]).to eq('lure')
    end

    it 'reads depths and distances from a list or words, in rotation order' do
      h::Config.store[:depths] = %w[bottom SURFACE]
      expect(h::Config.depths).to eq(%w[surface bottom])

      h::Config.store[:distances] = 'far, near'
      expect(h::Config.distances).to eq(%w[near far])
    end

    it 'falls back to the surface and far when nothing valid is set' do
      h::Config.store.merge!(depths: [], distances: 'yonder')
      expect(h::Config.depths).to eq(%w[surface])
      expect(h::Config.distances).to eq(%w[far])
    end

    it 'holds each distance for a full rotation of the depths' do
      h::Config.store.merge!(depths: %w[surface middle bottom], distances: %w[near middle far])
      pairs = (0..8).map { [h::Config.cast_distance_for(it), h::Weights.depth(it)] }

      expect(pairs.uniq.size).to eq(9)
      expect(pairs.first(4)).to eq([%w[near surface], %w[near middle], %w[near bottom], %w[middle surface]])
    end

    it 'rotates distances on their own with one depth' do
      h::Config.store[:distances] = %w[near far]
      expect((0..2).map { h::Config.cast_distance_for(it) }).to eq(%w[near far near])
    end

    it 'lists every setting with its value, flagging changed ones' do
      h::Config.store[:supplies_pole] = 'pole'
      listing = h::Config.listing

      expect(listing.lines.size).to eq(h::Config::DEFAULTS.size + 1)
      expect(listing).to match(/^  supplies_pole +"pole"  \(default "rod"\)$/)
      expect(listing).to match(/^  depths +\["surface"\]$/)
    end

    it 'tells whether fishing mode is bypass' do
      expect(h::Config.bypass?).to be false
      h::Config.store[:fishing_mode] = 'bypass'
      expect(h::Config.bypass?).to be true
    end
  end

  describe 'Config.migrate!' do
    def migrate(old)
      LichStub::UserVars.tfish = old.merge(v2_settings: true)
      notes = h::Config.setup!
      [h::Config.store, notes]
    end

    it 'turns weight cycling saved by pre-2.0 tfish into the surface only, once' do
      LichStub::UserVars.tfish = { cycle_weights: true }
      h::Config.setup!
      expect(h::Config.depths).to eq(%w[surface])
    end

    it 'carries cycling and the default lure over to every depth' do
      store, notes = migrate(cycle_weights: true, supplies_lure: 'grey lure', lure_deep: 'ebon gate lure',
                             weight_depths: 'blown glass weight', cast_distance: 'middle', use_cman: true)

      expect(store).to include(depths: %w[surface middle bottom], distances: %w[middle],
                               lure_surface: 'grey lure', lure_middle: 'grey lure', lure_bottom: 'ebon gate lure',
                               weight_middle: 'blown glass weight')
      expect(store.keys & h::Config::OLD_KEYS).to be_empty
      expect(notes.last).to include('depths surface/middle/bottom, cast middle')
    end

    it 'turns a constant weight into the depth whose weight it matches' do
      expect(migrate(weight_noncycle: 'glaes').first[:depths]).to eq(%w[bottom])
      expect(migrate(weight_noncycle: 'blown glass').first[:depths]).to eq(%w[middle])
    end

    it 'makes an unknown constant weight the bottom weight, with a note' do
      store, notes = migrate(weight_noncycle: 'granite')

      expect(store).to include(depths: %w[bottom], weight_bottom: 'granite weight')
      expect(notes.first).to include('granite weight is now the bottom weight')
    end

    it 'carries cycle_distance over to every distance, and fishes the surface by default' do
      expect(migrate(cycle_distance: true, cast_distance: 'near').first).to include(distances: %w[near middle far], depths: %w[surface])
    end

    it 'gives a fresh install the defaults without a migration note' do
      LichStub::UserVars.tfish = nil
      expect(h::Config.setup!).to be_empty
      expect(h::Config.store.keys & h::Config::OLD_KEYS).to be_empty
      expect(h::Config.depths).to eq(%w[surface])
    end

    it 'leaves settings already in the new form alone' do
      LichStub::UserVars.tfish = { v2_settings: true, depths: %w[middle], lure_middle: 'skull lure' }
      expect(h::Config.setup!).to be_empty
      expect(h::Config.store).to include(depths: %w[middle], lure_middle: 'skull lure')
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

    # From a live run: CUT with no lure on, and a new line on an intact one,
    # are both refused, and a GET with full hands must not time out.
    it 'recognizes refused cuts and restrings, and full hands' do
      expect("Your black fishing pole isn't currently strung.").to match(h::Messages::CUT_REPLY)
      intact = "The line of your black fishing pole is intact.  You'll need to wait before restringing it with a new one."
      expect(intact).to match(h::Messages::RESTRING_REPLY)
      expect(intact).not_to match(h::Messages::RESTRUNG)
      expect('You coil some of your thin silver wire around the reel of your black fishing pole before threading the remainder through its guides.').to match(h::Messages::RESTRUNG)
      expect('You need a free hand to pick that up.').to match(h::Messages::GET_FAIL)
      expect('You need a free hand to pick that up.').to match(h::Messages::HANDS_FULL)
    end

    it 'fails a cast with no free hand right away instead of waiting for a reply' do
      expect("You can't cast without a free hand.").to match(h::Messages::CAST_FAIL)
    end

    it 'finds what cutting the line dropped at your feet' do
      plain = 'With a swift, sharp tug, you snap the line of your fishing rod.  Your freckled grey squid falls to the ground at your feet.'
      xml = 'With a swift, sharp tug, you snap the line of your <a exist="1234" noun="rod">fishing rod</a>.  ' \
            'Your <a exist="5678" noun="squid">freckled grey squid</a> falls to the ground at your feet.'

      expect(h::Messages.dropped(plain)).to eq([{ id: nil, noun: 'squid', name: 'freckled grey squid' }])
      expect(h::Messages.dropped(xml)).to eq([{ id: '5678', noun: 'squid', name: 'freckled grey squid' }])
      expect(h::Messages.dropped('Roundtime: 5 sec.')).to eq([])
    end

    # fishing_log015: a lure and a weight on the line drop together, "fall".
    it 'finds every item when the lure and weight both drop' do
      plain = 'With a swift, sharp tug, you snap the line of your black fishing pole.  Your skull-shaped lure and blown glass weight fall to the ground at your feet.'
      xml = 'Your <a exist="11" noun="lure">skull-shaped lure</a> and <a exist="22" noun="weight">blown glass weight</a> fall to the ground at your feet.'

      expect(h::Messages.dropped(plain).map { it[:noun] }).to eq(%w[lure weight])
      expect(h::Messages.dropped(xml)).to eq([{ id: '11', noun: 'lure', name: 'skull-shaped lure' },
                                              { id: '22', noun: 'weight', name: 'blown glass weight' }])
    end

    it 'recognizes being stopped by something left at your feet' do
      expect('As you prepare to move away, you remember the things still placed alongside you.').to match(h::Messages::DOCK_BLOCKED)
      expect('As you prepare to move away, you remember the freckled grey squid still placed alongside you.').to match(h::Messages::DOCK_BLOCKED)
    end

    it 'reads the prize found inside a fish' do
      coffin = "In addition, you find a gilt-cornered pumpkin ash coffin inside the butterflyfish's belly.  You toss the remaining carcass aside."
      tombstone = "In addition, you find a laughing dog-shaped tombstone inside the parrotfish's belly.  You toss the remaining carcass aside."

      expect(coffin[h::Messages::FOUND, :item]).to eq('a gilt-cornered pumpkin ash coffin')
      expect(tombstone[h::Messages::FOUND, :item]).to eq('a laughing dog-shaped tombstone')
      expect("Lakishiie also found a ghost white turnip inside the roosterfish's belly.")
        .not_to match(h::Messages::FOUND)
    end

    it "reads a non-Ebon Gate fish's rarity from LOOK" do
      expect('It is of rare quality.'[h::Messages::QUALITY, :rarity]).to eq('rare')
      expect('The bass is about 13 inches long and weighs around 2 pounds.').not_to match(h::Messages::QUALITY)
    end

    it 'reads weight and rarity from a LOOK that shows them, nil when it does not' do
      look = "The silver scakor's body is nearly round.\nThe scakor is about 20 inches long and weighs around 8 pounds.\n" \
             "It is of common quality.\nThe scakor flops and flails wildly in a gregarious struggle to respire!"
      expect(h::Messages.looked_fish(look)).to eq(%w[common 8])
      expect(h::Messages.looked_fish("The glowing butterflyfish's scales shimmer.")).to eq([nil, nil])
      expect(h::Messages.looked_fish('')).to eq([nil, nil])
    end

    # FISH TOTAL before and after a catch from fishing_log010.
    it "tells a catch's rarity from which FISH TOTAL count went up" do
      total = lambda do |common, uncommon, rare, epic, legendary|
        <<~TOTAL
                       Fishing Totals
           --------------------------------------
            Common Fish Caught:                #{common}
            Uncommon Fish Caught:              #{uncommon}
            Rare Fish Caught:                  #{rare}
            Epic Fish Caught:                  #{epic}
            Legendary Fish Caught:             #{legendary}
            Total Fish Caught:                #{common + uncommon + rare + epic + legendary}
            Lines Snapped:                     1
        TOTAL
      end
      before = h::Messages.totals(total.(20, 9, 9, 4, 1))

      expect(before).to eq('common' => 20, 'uncommon' => 9, 'rare' => 9, 'epic' => 4, 'legendary' => 1)
      expect(h::Messages.new_rarity(before, h::Messages.totals(total.(20, 9, 9, 4, 2)))).to eq('legendary')
      expect(h::Messages.new_rarity(before, h::Messages.totals(total.(21, 9, 9, 4, 1)))).to eq('common')
      expect(h::Messages.new_rarity(before, before)).to be_nil
      expect(h::Messages.new_rarity({}, before)).to be_nil
    end

    it 'starts capturing a cut on any reply to it' do
      ["You cut into the red scakor's flesh and after a few deft strokes produce a fine fillet of raw scakor.",
       "You cut into the rainbow roosterfish's flesh but only end up mangling the thing beyond recognition.",
       'Cut what?', 'Try holding the cod first.'].each { expect(it).to match(h::Messages::CUT_FISH) }
      expect('Maziie cuts into the tentacled aberration\'s flesh but completely eviscerates the creature.')
        .not_to match(h::Messages::CUT_FISH)
    end

    # fishing_log016: the hook message was lost, then a fish fought for 15
    # minutes while the script kept "waiting for a bite".
    it "treats your fish's own fight turns as hooked while waiting, but not a neighbour's" do
      mine = [
        'Your black fishing pole bends alarmingly as the fish at the end of your line jerks and tugs violently in its attempt to escape.  You have no more slack to let loose!',
        'With a sudden surge, the catch yanks the line of your black fishing pole forward, creating just enough slack to unsettle your careful hold.',
        'Your catch pulls with surprising force, the line of your fishing rod momentarily slackening as your grip struggles to keep up.',
        'A sharp tug vibrates through your fishing rod as your catch struggles to gain ground.  You maintain tension on the line, thwarting the effort.',
      ]
      not_fish = [
        'With a sudden surge, the catch yanks the line of Lakishiie\'s fishing rod forward, creating just enough slack to unsettle his careful hold.',
        "Kenzsii's sugar cane rod bends alarmingly as the fish at the end of her line jerks and tugs violently in its attempt to escape!",
        'You wait patiently as the skull-shaped lure of your black fishing pole drifts aimlessly in the current.  No curious fish take notice.',
        'The water ripples softly around the line of your black fishing pole, but nothing stirs beneath the surface.',
        'You feel a faint tremor through the line of your fishing rod--a false hope, as it is only the current tugging gently on your freckled grey squid.',
      ]

      mine.each { expect(it).to match(h::Messages::BITE_WAIT) }
      not_fish.each { expect(it).not_to match(h::Messages::BITE_WAIT) }
      expect('The line of your black fishing pole strains and breaks with a sharp *SNAP*!').to match(h::Messages::BITE_WAIT)
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
                                             lure_bonus: { surface: 16, middle: 12, deep: 12 }, lure_noun: 'squid'))
    end

    it 'sees a fresh line with no lure after restringing' do
      state = h::Pole.parse("The pole's line looks to be in excellent condition.")

      expect(state.line).to eq('excellent')
      expect(state.lure).to be_nil
    end

    # Long descriptions don't end with the noun ("...lure dangling a tiny gold
    # key"), so the noun comes from the item's XML link in the LOOK output.
    it 'reads attached gear nouns from the XML link, not the last word of the description' do
      look = <<~XML
        The <a exist="709969844" noun="pole">pole's</a> line looks to be in excellent condition.
        A <a exist="710037312" noun="lure">twisted iron ebon gate lure</a> dangling a tiny gold key is currently attached near the hook to attract fish.
        A <a exist="709996453" noun="weight">translucent glaes weight</a> with gleaming metallic veins is currently strung from the line of the <a exist="709969844" noun="pole">pole</a> to serve as a weight.
      XML
      state = h::Pole.parse(look)

      expect(state.lure).to eq('twisted iron ebon gate lure dangling a tiny gold key')
      expect(state.lure_noun).to eq('lure')
      expect(state.weight).to eq('translucent glaes weight with gleaming metallic veins')
      expect(state.weight_noun).to eq('weight')
    end

    it 'exposes the weight noun so sinkers and weights both come off the pole' do
      expect(h::Pole.parse(rigged).weight_noun).to eq('weight')
      expect(h::Pole.parse('An iron sinker is currently strung from the line of the rod to serve as a weight.').weight_noun).to eq('sinker')
    end

    # Wear levels as seen in game logs, in both lead-ins ("The line itself"
    # with a weight on, "The pole's line" without). The wiki's "signs of wear"
    # is "signs of use" in game.
    {
      'The line itself looks to be in excellent condition.'          => ['excellent', false],
      "The pole's line looks to be in excellent condition."          => ['excellent', false],
      "The rod's line looks to be in decent condition."              => ['decent', false],
      "The pole's line looks to be showing signs of use."            => ['showing signs of use', false],
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

    it 'replaces the line when frayed, or when worn if set to' do
      worn = h::Pole.parse("The pole's line looks to be showing signs of use.")
      frayed = h::Pole.parse("The pole's line looks to be frayed and in danger of snapping soon.")
      decent = h::Pole.parse("The pole's line looks to be in decent condition.")

      expect(worn.replace?('frayed')).to be false
      expect(worn.replace?('worn')).to be true
      expect(frayed.replace?('frayed')).to be true
      expect(decent.replace?('worn')).to be false
    end

    it 'reports nothing rigged on a bare pole' do
      state = h::Pole.parse('You see nothing unusual.')

      expect(state).to eq(h::Pole::State.new(line: nil, lure: nil, weight: nil))
    end
  end

  describe 'Weights' do
    glass = 'shimmering blown glass weight flecked with glitter'
    glaes = 'translucent glaes weight with gleaming metallic veins'

    it 'rotates through the depths being fished' do
      expect((0..1).map { h::Weights.depth(it) }).to eq(%w[surface surface])

      h::Config.store[:depths] = %w[middle bottom]
      expect((0..2).map { h::Weights.depth(it) }).to eq(%w[middle bottom middle])
    end

    it 'uses no weight at the surface and the set weight deeper down' do
      expect(h::Weights::DEPTHS.map { h::Weights.weight_for(it) }).to eq([nil, 'blown glass weight', 'glaes weight'])
    end

    it 'uses the lure set for each depth, any lure when it is empty' do
      h::Config.store.merge!(lure_middle: 'skull-shaped lure', lure_bottom: ' ')

      expect(h::Weights.lure_for('middle')).to eq('skull-shaped lure')
      expect(h::Weights.lure_for('surface')).to eq('lure')
      expect(h::Weights.lure_for('bottom')).to eq('lure')
    end

    it 'starts the rotation at the depth of the weight on the pole' do
      h::Config.store[:depths] = %w[surface middle bottom]
      expect(h::Weights.start_index(nil)).to eq(0)
      expect(h::Weights.start_index(glass)).to eq(1)
      expect(h::Weights.start_index(glaes)).to eq(2)
      expect(h::Weights.start_index('lead weight')).to eq(0)

      h::Config.store[:depths] = %w[surface bottom]
      expect(h::Weights.start_index(glass)).to eq(0)
      expect(h::Weights.start_index(glaes)).to eq(1)
    end

    it 'matches the weight on the pole against the one wanted' do
      expect(h::Weights.matches?(nil, nil)).to be true
      expect(h::Weights.matches?(glaes, nil)).to be false
      expect(h::Weights.matches?(glaes, 'glaes weight')).to be true
      expect(h::Weights.matches?(glass, 'glaes weight')).to be false
    end

    it 'reads how deep a weight sinks the line' do
      expect(h::Weights.sink_depth('The weight looks like it is heavy enough to sink a line to the middle depths of a body of water.')).to eq('middle depths')
      expect(h::Weights.sink_depth('The weight looks like it is heavy enough to sink a line to the bottom of a body of water.')).to eq('bottom')
      expect(h::Weights.sink_depth('You see nothing unusual.')).to be_nil
    end
  end

  describe 'Supplies.shortages' do
    item = TFishSpec::FakeItem
    wire = item.new('wire', 'fishing wire')

    def stocked(count)
      Array.new(count) { TFishSpec::FakeItem.new('weight', 'blown glass weight') } +
        Array.new(count) { TFishSpec::FakeItem.new('weight', 'glaes weight') }
    end

    def lures(count, name = 'leaf-topped grey mandrake lure') = Array.new(count) { TFishSpec::FakeItem.new('lure', name) }

    it 'needs line and the minimum of spare lures by default, with no weight' do
      expect(h::Supplies.shortages([wire] + lures(5))).to be_empty
      expect(h::Supplies.shortages(lures(4))).to eq(['Fishing Line - wire - 0/1', 'Lure - lure - 4/5'])
    end

    it 'is empty when line, lures and the weights for the depths fished are stocked' do
      h::Config.store[:depths] = %w[surface middle bottom]
      expect(h::Supplies.shortages(stocked(5) + lures(5) + [wire])).to be_empty
    end

    it 'reports missing line and short weights' do
      h::Config.store[:depths] = %w[surface middle bottom]
      expect(h::Supplies.shortages(stocked(4) + lures(5))).to eq([
                                                                   'Fishing Line - wire - 0/1',
                                                                   'Weight - blown glass weight - 4/5',
                                                                   'Weight - glaes weight - 4/5',
                                                                 ])
    end

    it 'only needs the weights for the depths fished' do
      h::Config.store[:depths] = %w[bottom]

      expect(h::Supplies.shortages(stocked(5) + lures(5) + [wire])).to be_empty
      expect(h::Supplies.shortages(lures(5) + [wire])).to eq(['Weight - glaes weight - 0/5'])
    end

    it 'needs the minimum of each lure in use' do
      h::Config.store.merge!(lure_surface: 'mandrake lure', lure_bottom: 'ebon gate lure')

      expect(h::Supplies.shortages([wire] + lures(5))).to be_empty
      expect(h::Supplies.shortages([wire] + lures(2))).to eq(['Lure - mandrake lure - 2/5'])

      h::Config.store[:depths] = %w[surface middle bottom]
      expect(h::Supplies.shortages(stocked(5) + [wire] + lures(5))).to eq(['Lure - ebon gate lure - 0/5'])
      expect(h::Supplies.shortages(stocked(5) + [wire] + lures(5) + lures(5, 'twisted iron ebon gate lure'))).to be_empty
    end

    it 'lists the lure and weight for each depth fished' do
      h::Config.store.merge!(lure_surface: 'mandrake lure', lure_bottom: 'ebon gate lure')
      expect(h::Supplies.lures_in_use).to eq('mandrake lure' => ['surface'])
      expect(h::Supplies.weights_in_use).to be_empty

      h::Config.store[:depths] = %w[surface middle bottom]
      expect(h::Supplies.lures_in_use).to eq('mandrake lure' => ['surface'], 'lure' => ['middle'], 'ebon gate lure' => ['bottom'])
      expect(h::Supplies.weights_in_use).to eq('blown glass weight' => 'middle', 'glaes weight' => 'bottom')
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
      spares = Array.new(5) { item.new('lure', 'glittery pink fish lure') }
      rows = h::Supplies.check(supplies + spares, knife_box, h::Pole.parse(surface_squid))

      expect(rows.map(&:first)).to all(eq(:ok))
    end

    # From a real ;tfish check: the lure set to the in-game style name
    # "grey mandrake lure" counted 0 spares when compared against the noun.
    it 'finds gear set by name, not just by noun' do
      h::Config.store[:lure_surface] = 'grey mandrake lure'
      h::Config.store[:supplies_pole] = 'black pole'
      contents = [item.new('pole', 'twisted black fishing pole'), item.new('wire', 'ball of dark braided fishing wire')] +
                 Array.new(10) { item.new('lure', 'leaf-topped grey mandrake lure') }
      rows = h::Supplies.check(contents, knife_box, h::Pole.parse("The pole's line looks to be frayed and in danger of snapping soon."))

      expect(rows).to include([:ok, 'Lure on the pole: none'], [:ok, 'Lure grey mandrake lure (surface): 10/5'],
                              [:warn, 'Line on the pole: frayed and in danger of snapping soon, will be replaced before fishing'])
      expect(rows.map(&:first) - [:warn]).to all(eq(:ok))
    end

    it 'flags a missing pole, spare line and knife' do
      rows = h::Supplies.check([], [], nil)

      expect(statuses(rows)).to include('Pole' => :missing, 'Spare line' => :missing, 'Knife' => :missing, 'Lure lure' => :missing)
    end

    it 'checks the weight and lure for each depth fished' do
      h::Config.store.merge!(depths: %w[surface middle bottom], lure_surface: 'grey lure', lure_middle: 'skull lure')
      contents = supplies + Array.new(5) { item.new('weight', 'blown glass weight') } +
                 [item.new('lure', 'leaf-topped grey mandrake lure')]
      rows = h::Supplies.check(contents, knife_box, h::Pole.parse(surface_squid))

      expect(rows).to include([:ok, 'Weight blown glass weight (middle): 5/5'], [:missing, 'Weight glaes weight (bottom): 0/5'],
                              [:missing, 'Lure grey lure (surface): 1/5'], [:missing, 'Lure skull lure (middle): 0/5'],
                              [:missing, 'Lure lure (bottom): 1/5'])
    end

    it 'checks each weight sinks to the depth its setting is for' do
      h::Config.store[:depths] = %w[middle bottom]
      contents = supplies + Array.new(5) { item.new('weight', 'shimmering blown glass weight') } +
                 Array.new(5) { item.new('weight', 'translucent glaes weight') }
      right = h::Supplies.check(contents, knife_box, nil, { 'blown glass weight' => 'middle depths', 'glaes weight' => 'bottom' })
      swapped = h::Supplies.check(contents, knife_box, nil, { 'blown glass weight' => 'bottom', 'glaes weight' => 'middle depths' })

      expect(right).to include([:ok, 'Weight blown glass weight sinks to the middle depths'], [:ok, 'Weight glaes weight sinks to the bottom'])
      expect(swapped).to include([:warn, 'Weight blown glass weight sinks to the bottom, expected the middle depths'],
                                 [:warn, 'Weight glaes weight sinks to the middle depths, expected the bottom'])
    end

    it 'warns when surface fishing with a lure that is better deeper' do
      deep = surface_squid.sub('+16 to attracting fish near the surface', '+12 to attracting fish near the surface')
                          .sub('+12 to attracting fish in deep water', '+16 to attracting fish in deep water')
      rows = h::Supplies.check(supplies, knife_box, h::Pole.parse(deep))

      expect(rows.last).to eq([:warn, 'dead-eyed freckled grey squid is better at deep depth than the surface'])
    end
  end

  describe 'Familiar' do
    at = Time.new(2026, 10, 10, 13, 16, 5)

    it 'writes one line per catch with what FISH TOTAL does not show' do
      line = h::Familiar.catch_line(number: 6, at:, cast: 'far', depth: 'surface', fish: 'tentacled aberration', rarity: 'legendary',
                                    pounds: '5', bite: 25, fight: 252, reels: 40, prize: 'a piece of pitted grey scoria')

      expect(line).to eq('#6 13:16 far/surface tentacled aberration (legendary) 5lb | bite 25s, fight 252s / 40 reels | a piece of pitted grey scoria')
    end

    it 'leaves out what is unknown' do
      expect(h::Familiar.catch_line(number: 1, at:, cast: 'middle', depth: nil, fish: 'sand bass', bite: 40, fight: 200, reels: 30))
        .to eq('#1 13:16 middle sand bass | bite 40s, fight 200s / 30 reels')
    end

    it 'writes a line for a snap or a fish that got away' do
      expect(h::Familiar.loss_line(number: 7, at:, cast: 'far', depth: 'bottom', outcome: :lost, fight: 48, reels: 8))
        .to eq('#7 13:16 far/bottom SNAP after 48s / 8 reels')
      expect(h::Familiar.loss_line(number: 7, at:, cast: 'far', depth: 'bottom', outcome: :lost, fight: 48, reels: 8, pounds: '12'))
        .to eq('#7 13:16 far/bottom SNAP (12lb fish) after 48s / 8 reels')
      expect(h::Familiar.loss_line(number: 7, at:, cast: 'near', depth: 'middle', outcome: :empty, fight: 90, reels: 15))
        .to eq('#7 13:16 near/middle got away after 90s / 15 reels')
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

    it "stays on a dock you're already fishing, otherwise goes to the configured one" do
      h::Config.store[:dock] = 4

      expect(h::Rooms.dock_for(32127).name).to eq('Misty Waters')
      expect(h::Rooms.dock_for(31846).name).to eq('Moss Pond')
      expect(h::Rooms.dock_for(1).name).to eq('Moss Pond')
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

  describe 'Setup' do
    let(:values) { h::Setup.values_from(h::Config.store) }

    it 'has a field for every setting except the counters, with tick boxes for depths and distances' do
      ticks = h::Setup::TICKS.values.flat_map(&:values)
      expect(h::Setup::FIELDS.keys - ticks).to match_array(h::Config::DEFAULTS.keys - %i[cast_total fish_total snap_total depths distances])
      expect(ticks).to eq(%i[depth_surface depth_middle depth_bottom distance_near distance_middle distance_far])
    end

    it 'gives every field a tooltip' do
      expect(h::Setup::FIELDS.values.map(&:tip)).to all(be_a(String).and(satisfy { !it.strip.empty? }))
    end

    it 'cleans up loaded settings so each fits its widget' do
      store = h::Config.store
      store.merge!(dock: 'moss', fav_room: 32116, replace_line_at: 'nonsense', cast_timer: 5, supplies_minimum: '3')
      values = h::Setup.values_from(store)

      expect(values).to include(dock: 4, fav_room: 0, replace_line_at: 'frayed', cast_timer: 10, supplies_minimum: 3)
    end

    it 'ticks the depths and distances being fished' do
      h::Config.store.merge!(depths: 'bottom surface', distances: %w[middle])

      expect(values).to include(depth_surface: true, depth_middle: false, depth_bottom: true,
                                distance_near: false, distance_middle: true, distance_far: false)
    end

    it 'keeps a spot on the chosen dock and a custom dock' do
      h::Config.store.merge!(dock: 2, fav_room: 32127)
      expect(values).to include(dock: 2, fav_room: 32127)

      custom = { entrance: 1, spots: [2, 3] }
      h::Config.store.merge!(dock: custom, fav_room: 3)
      reloaded = h::Setup.values_from(h::Config.store)
      expect(reloaded).to include(dock: custom, fav_room: 3)
      expect(h::Setup.choices(:dock, reloaded).first).to eq([custom, 'Custom (entrance 1)'])
    end

    it "offers the chosen dock's spots" do
      values[:dock] = 3
      expect(h::Setup.choices(:fav_room, values)).to eq([[0, 'Least crowded'], [32120, 'Room 32120'], [32121, 'Room 32121'], [32122, 'Room 32122']])
    end

    it "only enables a depth's lure and weight when that depth is ticked" do
      expect(h::Setup.enabled?(:lure_surface, values)).to be true
      %i[lure_middle weight_middle lure_bottom weight_bottom].each { expect(h::Setup.enabled?(it, values)).to be false }

      values.merge!(depth_surface: false, depth_bottom: true)
      expect(h::Setup.enabled?(:lure_surface, values)).to be false
      expect(h::Setup.enabled?(:lure_bottom, values)).to be true
      expect(h::Setup.enabled?(:weight_bottom, values)).to be true
      expect(h::Setup.enabled?(:weight_middle, values)).to be false
    end

    it 'switches between Ebon Gate and bypass fishing' do
      expect(values[:fishing_mode]).to eq('ebon_gate')
      %i[dock fav_room squelch_script].each { expect(h::Setup.enabled?(it, values)).to be true }
      expect(h::Setup.enabled?(:overfished_wait, values)).to be false

      values[:fishing_mode] = 'bypass'
      %i[dock fav_room squelch_script].each { expect(h::Setup.enabled?(it, values)).to be false }
      expect(h::Setup.enabled?(:overfished_wait, values)).to be true
      h::Setup.save(values, h::Config.store)
      expect(h::Config.bypass?).to be true

      h::Config.store[:fishing_mode] = 'nonsense'
      expect(h::Setup.values_from(h::Config.store)[:fishing_mode]).to eq('ebon_gate')
    end

    it 'accepts the defaults' do
      expect(h::Setup.errors(values)).to be_empty
    end

    it 'flags required, quoted and "my" names, but not settings that are off' do
      values.merge!(supplies_container: ' ', lure_surface: '"grey lure"', fillet_knife: 'my dagger', lure_middle: '')
      errors = h::Setup.errors(values)

      expect(errors[:supplies_container]).to eq('Required')
      expect(errors[:lure_surface]).to include('no quotes')
      expect(errors[:fillet_knife]).to include('my')
      expect(errors).not_to have_key(:lure_middle)
    end

    it 'needs at least one depth and one distance ticked' do
      values.merge!(depth_surface: false, distance_far: false)
      expect(h::Setup.errors(values)).to include(depth_surface: 'tick at least one depth', distance_near: 'tick at least one cast distance')
    end

    it 'needs two different weights when fishing both depths' do
      values.merge!(depth_middle: true, depth_bottom: true, weight_middle: 'glaes weight', weight_bottom: 'Glaes Weight ')
      expect(h::Setup.errors(values)[:weight_bottom]).to include('different weight')

      values[:depth_middle] = false
      expect(h::Setup.errors(values)).to be_empty

      values.merge!(depth_middle: true, weight_middle: '')
      expect(h::Setup.errors(values)[:weight_middle]).to eq('Required')
    end

    it "accepts names with hyphens and apostrophes" do
      values[:supplies_container] = "djinn's sea-green sack"
      expect(h::Setup.errors(values)).to be_empty
    end

    it 'saves every field with text trimmed, and the ticks as lists' do
      values.merge!(lure_bottom: '  ebon gate lure ', depth_bottom: true, distance_near: true, distance_far: false)
      h::Setup.save(values, h::Config.store)

      expect(h::Config.store).to include(lure_bottom: 'ebon gate lure', depths: %w[surface bottom], distances: %w[near])
      expect(h::Config.store.keys & h::Setup::TICKS.values.flat_map(&:values)).to be_empty
    end
  end

  describe 'Tackle' do
    # From a real GAZE of a Super-Fish-All Tackle Box, as XML.
    gaze = <<~XML
      Sifting through the angular trays of your <a exist="767883310" noun="box">mithril tackle box</a>, you mentally catalog each in turn:

      1.  a leaf-topped grey mandrake lure with tiny thorn teeth<pushBold/> (25 pieces, one of which is ready for plucking)
      <popBold/>2.  a pale carved skull-shaped lure with granite-inset eyes<pushBold/> (25 pieces)
      <popBold/>3.  a twisted iron ebon gate lure dangling a tiny gold key<pushBold/> (1 piece)
      <popBold/>4.  a translucent glaes weight with gleaming metallic veins<pushBold/> (25 pieces)
      <popBold/>5.  a shimmering blown glass weight flecked with glitter<pushBold/> (25 pieces)
      <popBold/>6.  a ball of dark braided fishing wire<pushBold/> (25 pieces)
      <popBold/><prompt time="1791990767">&gt;</prompt>
    XML

    it 'reads the trays from GAZE, and which one PLUCK takes from' do
      trays = h::Tackle.trays(gaze)

      expect(trays.size).to eq(6)
      expect(trays.first).to have_attributes(number: 1, name: 'leaf-topped grey mandrake lure with tiny thorn teeth', count: 25, ready: true)
      expect(trays[2]).to have_attributes(number: 3, name: 'twisted iron ebon gate lure dangling a tiny gold key', count: 1, ready: false)
      expect(trays.find { h::Supplies.named?(it.name, 'glaes weight') }.number).to eq(4)
    end

    # From a real GAZE: the last piece in a tray words its ready marker differently.
    it 'reads a one-piece tray, ready or not' do
      ready = h::Tackle.trays('1.  a leaf-topped grey mandrake lure with tiny thorn teeth (1 piece, which is ready for plucking)').first
      waiting = h::Tackle.trays('6.  a leaf-topped grey mandrake lure with tiny thorn teeth (1 piece)').first

      expect(ready).to have_attributes(number: 1, count: 1, ready: true)
      expect(waiting).to have_attributes(number: 6, count: 1, ready: false)
    end

    # From a real GAZE: the same gear can fill several trays.
    it 'prefers a ready tray when the same gear fills several, and counts them all' do
      trays = h::Tackle.trays(<<~GAZE)
        4.  a shimmering blown glass weight flecked with glitter (25 pieces)
        5.  a ball of dark braided fishing wire (25 pieces)
        10. a shimmering blown glass weight flecked with glitter (9 pieces, one of which is ready for plucking)
        12. a ball of dark braided fishing wire (1 piece)
        13. a ball of dark braided fishing wire (7 pieces)
      GAZE

      expect(h::Tackle.pick(trays, 'blown glass weight').number).to eq(10)
      expect(h::Tackle.pick(trays, 'wire').number).to eq(5)
      expect(h::Tackle.pick(trays, 'glaes weight')).to be_nil
      expect(h::Tackle.items(trays).count { h::Supplies.named?(it.name, 'wire') }).to eq(33)
    end

    it 'counts each piece in the trays as supplies' do
      LichStub::UserVars.tfish.merge!(tackle_box: true, depths: %w[surface middle bottom], lure_surface: 'grey lure',
                                      lure_middle: 'skull lure', lure_bottom: 'ebon gate lure')
      expect(h::Supplies.shortages(h::Tackle.items(h::Tackle.trays(gaze)))).to eq(['Lure - ebon gate lure - 1/5'])
    end

    it 'reads the tray WHISPER moved to the top' do
      line = 'Whispering quietly to yourself, you inspect each of the marked labels on the angular trays of your mithril tackle box.  ' \
             'You quickly find the one with a twisted iron ebon gate lure dangling a tiny gold key inside and move it to the top.'

      expect(h::Tackle.whispered(line)).to eq('twisted iron ebon gate lure dangling a tiny gold key')
      expect(h::Tackle.whispered('USAGE: WHISPER {my} box [#]')).to be_nil
    end

    it 'reads what PLUCK took' do
      line = 'You fiddle with the angular trays of your mithril tackle box and pluck a twisted iron ebon gate lure dangling a tiny gold key ' \
             'from the one that is currently opened.'
      expect(h::Tackle.plucked(line)).to eq('twisted iron ebon gate lure dangling a tiny gold key')
    end

    # From a real TINKER, for boxes without WHISPER.
    it 'reads the tray TINKER cycled to the top' do
      line = 'You discreetly rearrange the angular trays of your mithril tackle box, shifting the one storing ' \
             'a pale carved skull-shaped lure with granite-inset eyes (fishing lure) to the top.'

      expect(h::Tackle.tinkered(line)).to eq('pale carved skull-shaped lure with granite-inset eyes')
      expect(h::Tackle.tinkered(nil)).to be_nil
    end

    it 'finds the pole on the loops from LOOK ON' do
      look = <<~XML
        <container id='767883310' title='Box' target='#767883310' location='right'/><clearContainer id="767883310"/><inv id='767883310'>The <a exist="767883310" noun="box">box</a> is closed.</inv><inv id='767883310'>On the <a exist="767883310" noun="box">box</a>:</inv><inv id='767883310'> a <a exist="767883098" noun="pole">twisted black fishing pole</a> adorned with tiny fish skulls</inv>On the <a exist="767883310" noun="box">mithril tackle box</a>:
        <pushBold/>Special [1]:<popBold/> a <a exist="767883098" noun="pole">twisted black fishing pole</a> adorned with tiny fish skulls
      XML
      pole = h::Tackle.on_box(look).find { h::Supplies.named?(it[:name], 'black pole') }

      expect(pole).to eq(id: '767883098', noun: 'pole', name: 'twisted black fishing pole')
    end

    it "won't keep the knife in the tackle box" do
      values = h::Setup.values_from(h::Config.store).merge(tackle_box: true, supplies_container: 'box', knife_container: 'Box')
      expect(h::Setup.errors(values)[:knife_container]).to include("can't hold your knife")

      values[:knife_container] = 'cloak'
      expect(h::Setup.errors(values)).to be_empty
    end
  end

  describe 'lag and pulling in' do
    # From a real log of reeling a near cast in before a bite.
    it "reads where a pull left the hook, or that it's all the way in" do
      expect('Your hook is now about 18 feet away.'[h::Messages::PULL_REPLY, :feet]).to eq('18')
      reeled = 'You reel the line of your black fishing pole in.  The grey mandrake lure strung on the line breaks the surface ' \
               'and dangles briefly over the water as you finish retracting the line.'
      expect(reeled).to match(h::Messages::PULL_REPLY)
      expect(reeled[h::Messages::PULL_REPLY, :feet]).to be_nil
      expect('But the pole is already reeled in!').to match(h::Messages::PULL_REPLY)
    end

    it "doesn't take the pull's slack line for a fish on the line" do
      slack = 'You take in some of the slack from the line of your black fishing pole.'
      expect(slack).not_to match(h::Messages::FISH_ON)
      expect(slack).not_to match(h::Messages::PULL_REPLY)
    end

    it 'only offers pulling in with near and surface ticked' do
      values = h::Setup.values_from(h::Config.store)
      expect(h::Setup.enabled?(:pull_in, values)).to be false

      values[:distance_near] = true
      expect(h::Setup.enabled?(:pull_in, values)).to be true

      values[:depth_surface] = false
      expect(h::Setup.enabled?(:pull_in, values)).to be false
    end
  end

  describe 'catches outside Ebon Gate' do
    let(:values) { h::Setup.values_from(h::Config.store) }

    it 'only offers tossing or keeping fish in bypass mode' do
      expect(h::Setup.enabled?(:catch_action, values)).to be false
      expect(h::Setup.enabled?(:trash_cut, values)).to be true

      values[:fishing_mode] = 'bypass'
      expect(h::Setup.enabled?(:catch_action, values)).to be true

      values[:catch_action] = 'keep'
      expect(h::Setup.enabled?(:fish_container, values)).to be true
      expect(h::Setup.enabled?(:trash_cut, values)).to be false

      values[:catch_action] = 'toss'
      expect(h::Setup.enabled?(:fish_container, values)).to be false
      expect(h::Setup.enabled?(:trash_cut, values)).to be false

      values[:catch_action] = 'cut' # fillets that can't be trashed go there too
      expect(h::Setup.enabled?(:fish_container, values)).to be true
    end

    it 'lets the fish container be left empty for the lootsack' do
      values.merge!(fishing_mode: 'bypass', catch_action: 'keep', fish_container: '')
      expect(h::Setup.errors(values)).to be_empty

      values[:fish_container] = 'my creel'
      expect(h::Setup.errors(values)[:fish_container]).to include('my')
    end

    it 'cuts fish open unless set to toss or keep' do
      h::Config.store[:catch_action] = 'release'
      expect(h::Setup.values_from(h::Config.store)[:catch_action]).to eq('cut')
      expect(h::Setup.choices(:catch_action, values).map(&:first)).to eq(%w[cut toss keep])
    end
  end

  describe 'toggletfish' do
    it 'matches what you type, with or without a semicolon' do
      %W[toggletfish ;toggletfish <c>toggletfish\n TOGGLETFISH].each { expect(it).to match(h::Messages::TOGGLE) }
      ['toggletfish now', 'say toggletfish', ';tfish'].each { expect(it).not_to match(h::Messages::TOGGLE) }
    end
  end
end
