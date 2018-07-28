require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "cursed items" do
    [
      %{glossy black doomstone},
      %{shard of oblivion quartz},
      %{urglaes fang},
    ].each do |cursed_item_name|
      it "recognizes #{cursed_item_name} as cursed" do
        cursed_item = GameObjFactory.item_from_name(cursed_item_name)
        expect(cursed_item.type).to include "cursed"
      end
    end

    [
      %{black ora}
    ].each do |material|
      [
        %{a lump of #{material}},
        %{a #{material} item},
      ].each do |cursed_item_name|
        it "recognizes #{cursed_item_name} as cursed" do
          cursed_item = GameObjFactory.item_from_name(cursed_item_name)
          expect(cursed_item.type).to include "cursed"
        end
      end
    end
  end

  describe "uncommon materials" do
    uncommon_materials = %w[
      adamantine
      alexandrite
      alum
      bronze
      carmiln
      coraesine
      deringo
      drakar
      drake
      eahnor
      eonake
      faenor
      faewood
      feras
      fireleaf
      glaes
      glowbark
      golvern
      gornar
      hoarbeam
      illthorn
      imflass
      invar
      ipantor
      iron
      ironwood
      kakore
      kelyn
      krodera
      kroderine
      laje
      lor
      mein
      mesille
      mithglin
      mithril
      modwir
      mossbark
      obsidian
      ora
      orase
      razern
      rhimar
      rolaren
      rowan
      ruic
      sephwir
      urglaes
      urnon
      vaalin
      vaalorn
      veil
      veil iron
      veniom
      villswood
      vultite
      widowwood
      witchwood
      wyrwood
      yew
      zelnorn
      zorchar
    ]

    uncommon_materials.each do |material|
      [
        %{a lump of #{material}},
        %{a #{material} item},
      ].each do |cursed_item_name|
        it "recognizes #{cursed_item_name} as uncommon" do
          cursed_item = GameObjFactory.item_from_name(cursed_item_name)
          expect(cursed_item.type).to include "uncommon"
        end
      end
    end

    describe "uncommon material exceptions" do
      [
=begin
        ^(?:piece of snowflake obsidian|
        some lustrous grooved obsidian|
        piece of iron|
        slender mithril wand|
        twisted modwir short\-staff|
        flame-singed modwir tree|

(?:\w+ )?iron wand|
black iron cauldron|
rust-colored laje spoke|

small bronze egg\-shaped geode|
arrowhead of two-toned alexandrite|
bronze\-hazed beige mekret cabochon|
cloudy alexandrite shard)$
=end
      ].each do |common_item_name|
        it "recognizes #{common_item_name} is NOT uncommon" do
          common_item = GameObjFactory.item_from_name(common_item_name)
          expect(common_item.type).to_not include "uncommon"
        end
      end

      describe "common gems and valuables" do
        [
=begin
bronze fang|
iron fang|
mithril fang|
silver fang|
steel fang|
urglaes fang|

(?:mithril|faenor|rhimar|ora|vultite)\-bloom$|

green alexandrite stone|
piece of snowflake obsidian|
piece of spiderweb obsidian|
some lustrous grooved obsidian
obsidian eye|
=end
        ].each do |common_item_name|
          it "recognizes #{common_item_name} is NOT uncommon" do
            common_item = GameObjFactory.item_from_name(common_item_name)
            expect(common_item.type).to_not include "uncommon"
          end
        end
      end
    end
  end
end

__END__

\bAdventurer's Guild badge$|

\b(?:pin|necklace|crown|talisman|pendant|ring|tiara|anklet|earring|earrings|clasp|bracelet|medallion|amulet|chalice|stickpin|brooch|badge|circlet|buckle|neckchain|band|earcuff|bracer|bowl|torc|ewer|barrette|flagon|urn|tray|cup|platter|stein)$|


