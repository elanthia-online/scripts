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
    uncommon_materials = [
      %{adamantine},
      %{alexandrite},
      %{alum},
      %{bronze},
      %{carmiln},
      %{coraesine},
      %{deringo},
      %{drakar},
      %{drake},
      %{eahnor},
      %{eonake},
      %{faenor},
      %{faewood},
      %{feras},
      %{fireleaf},
      %{glaes},
      %{glowbark},
      %{golvern},
      %{gornar},
      %{hoarbeam},
      %{illthorn},
      %{imflass},
      %{invar},
      %{ipantor},
      %{ironwood},
      %{kakore},
      %{kelyn},
      %{krodera},
      %{kroderine},
      %{laje},
      %{lor},
      %{mein},
      %{mesille},
      %{mithglin},
      %{mithril},
      %{modwir},
      %{mossbark},
      %{obsidian},
      %{ora},
      %{orase},
      %{razern},
      %{rhimar},
      %{rolaren},
      %{rowan},
      %{ruic},
      %{sephwir},
      %{urglaes},
      %{urnon},
      %{vaalin},
      %{vaalorn},
      %{veil iron},
      %{veniom},
      %{villswood},
      %{vultite},
      %{widowwood},
      %{witchwood},
      %{wyrwood},
      %{yew},
      %{zelnorn},
      %{zorchar},
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

    describe "uncommon material exceptions and counter-examples" do
      [
        %{arrowhead of two-toned alexandrite},
        %{black iron cauldron},
        %{white bridal veil},
        %{bronze-hazed beige mekret cabochon},
        %{cloudy alexandrite shard},
        %{flame-singed modwir tree},
        %{iron wand},
        %{handful of iron flakes},
        %{piece of iron},
        %{piece of snowflake obsidian},
        %{rust-colored laje spoke},
        %{slender mithril wand},
        %{small bronze egg-shaped geode},
        %{some lustrous grooved obsidian},
        %{twisted modwir short-staff},
      ].each do |common_item_name|
        it "recognizes #{common_item_name} is NOT uncommon" do
          common_item = GameObjFactory.item_from_name(common_item_name)
          expect(common_item.type.to_s).to_not include "uncommon"
        end
      end

      it "recognizes that an Adventurer's Guild badge is NOT uncommon" do
        uncommon_materials.each do |material|
          common_item_name = "#{material} Adventurer's Guild badge"
          common_item = GameObjFactory.item_from_name(common_item_name)
          expect(common_item.type.to_s).to_not include "uncommon"
        end
      end
    end
  end
end
