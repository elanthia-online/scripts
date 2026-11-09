# frozen_string_literal: true

require_relative '../spec_helper'

# Spec for tsquelch.lic's FISH CAST/REEL squelch patterns. The script hooks
# the live game stream on load, so only the Fisher/Fishing_Squelch constants
# are extracted and evaluated. Fixtures are copied from real in-game logs,
# with the XML tags already stripped the way the downstream hook strips them.
module TSquelchSpec
  SOURCE_PATH = find_lic_source('tsquelch.lic', from: __dir__)
  module_eval(File.read(SOURCE_PATH)[/^  Fisher = .*?^  \)\r?\n/m], SOURCE_PATH)
end

RSpec.describe 'TSquelch fishing' do
  others = [
    "Kenzsii just lunged in.",
    "Rippee just slogged down a patchwork moldy fishing dock.",
    "Myasarie leans back and lets the line of her sugar cane rod go with a sharp *WHOOSH!*  The ebon gate lure attached near the hook flies through the air before landing with a soft *plink* right off of the side of the dock.",
    "Remzsii's sugar cane rod bends slightly and its tip dips.  She swiftly gives the rod a tug to set the hook!",
    "Remzsii's sugar cane rod bends alarmingly as the fish at the end of her line jerks and tugs violently in its attempt to escape!",
    "Rippee braces himself and reels with all his strength, but his line seems locked in place.",
    "Lakishiie tugs hard on his fishing rod, but the resistance from the fish at the end of the line makes the rod bend sharply.  He fails to bring in any more line!",
    "The line of Kenzsii's sugar cane rod zigzags back and forth wildly as her catch struggles against her!",
    "The tension on the line of Kenzsii's sugar cane rod vanishes for a heartbeat as an unexpected burst of strength from her catch earns it a brief reprieve.",
    "Kenzsii's catch fights, sending small ripples across the water.  She maintains control, the reel of her sugar cane rod whirring gently as the distance between fisher and fish narrows.",
    "Maziie gives her sugar cane rod one final tug and a spectral viridian parrotfish comes wriggling to the surface!  Moving swiftly, she takes in the rest of her line and unhooks the parrotfish, then takes hold of it tightly.",
    "The line of Rippee's black fishing pole strains and breaks with a sharp *SNAP*!",
    "Lakishiie removes a drake dagger from in his cotton sack.",
    "Kenzsii cuts into the glowing butterflyfish's flesh but completely eviscerates the creature.",
    "Kenzsii also found a ghost white turnip inside the roosterfish's belly.  She tosses the remaining carcass aside.",
  ]
  mine = [
    "You leans back and lets the line of your fishing rod go with a sharp *WHOOSH!*",
    "The tip of your fishing rod bends alarmingly as you fight unsuccessfully to reel in your catch!",
    "The line of your fishing rod zigzags back and forth wildly as your catch struggles against you!",
    "You give your fishing rod one final tug and the glowing butterflyfish comes wriggling to the surface!",
    'Kenzsii says, "My sugar cane rod bends alarmingly as the fish at the end of my line jerks."',
    "Kenzsii squints at you.",
  ]

  it 'squelches other fishers' do
    others.each { expect(it).to match(TSquelchSpec::Fishing_Squelch) }
  end

  it 'leaves your own fishing and other chatter alone' do
    mine.each { expect(it).not_to match(TSquelchSpec::Fishing_Squelch) }
  end
end
