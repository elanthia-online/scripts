require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "food" do
    [
      %{dark red minotaur tongue},
      %{fresh cinnamon doughnut},
      %{frosted cherry cookie},
      %{layer of onion skin},
      %{moldy chocolate cupcake},
      %{pallid slimy tongue},
      %{rancid black liver},
      %{split-tipped putrid green tongue},
    ].each do |food_name|
      it "recognizes #{food_name} as a food" do
        food = GameObjFactory.item_from_name(food_name)
        expect(food.type).to include "food"
      end
    end
  end

  describe "instruments" do
    [
      %{cymbals},
      %{tambourine},
      %{fife},
      %{flute},
      %{piccolo},
      %{ayr},
      %{cittern},
      %{lute},
      %{mandolin},
      %{theorbo},
      %{dulcimer},
      %{harp},
      %{lyre},
      %{psaltery},
      %{zither},
      %{bagpipes},
      %{cornemuse},
      %{enshai},
      %{cornett},
      %{crumhorn},
      %{lysard},
      %{shawm},
    ].each do |instrument_name|
      it "recognizes #{instrument_name} as a instrument" do
        instrument = GameObjFactory.item_from_name(instrument_name)
        expect(instrument.type).to eq "instrument"
      end
    end
  end

  describe "jars" do
    [
      %{a blue-hued speckled glass bottle},
      %{a brass-rimmed scarlet glass jar},
      %{a bronze-rimmed mulberry glass jar},
      %{a gold-rimmed vermilion glass jar},
      %{a hazy heptagonal jar},
      %{a kelyn-rimmed goldenrod glass jar},
      %{a mottled ten-sided glass jar},
      %{an amber glass beaker},
      %{an antiqued black sea glass bottle},
      %{an azure glass beaker},
      %{a nearly square glass jar},
      %{an opalescent glass jar},
      %{an opalescent violet glass bottle},
      %{a perfectly cubical glass jar},
      %{a poppy red glass beaker},
      %{a slightly bulbous glass jar},
      %{a sooty glass beaker},
      %{a spherical glass jar},
      %{a translucent pentagonal jar},
      %{a translucent white sea glass bottle},
      %{a twisted triangular jar},
    ].each do |jar_name|
      it "recognizes #{jar_name} as a jar" do
        jar = GameObjFactory.item_from_name(jar_name)
        expect(jar.type).to eq "jar"
      end
    end

    describe "things that are not jars" do
      [
        %{glass bottle},
      ].each do |item_name|
        it "recognizes #{item_name} is NOT a jar" do
          jar = GameObjFactory.item_from_name(item_name)
          expect(jar.type.to_s).to_not include "jar"
        end
      end
    end
  end

  describe "notes" do
    [
      %{City-States promissory note},
      %{Icemule promissory note},
      %{Mist Harbor promissory note},
      %{Torren promissory note},
      %{Vornavis promissory note},
      %{Wehnimer's promissory note},

      %{bloodstained promissory note},
      %{damp promissory note},
      %{dirty promissory note},
      %{old promissory note},
      %{smudged promissory note},
      %{stained promissory note},

      %{mining chit},
    ].each do |note_name|
      it "recognizes #{note_name} as a note" do
        note = GameObjFactory.item_from_name(note_name)
        expect(note.type).to eq "note"
      end
    end
  end

  describe "spirit beast talismans" do
    [
      %{painted clay talisman},
      %{colorful clay talisman},
      %{rippled clay talisman},
      %{charred clay talisman},
    ].each do |talisman_name|
      it "recognizes #{talisman_name} as a spirit beast talisman" do
        talisman = GameObjFactory.item_from_name(talisman_name)
        expect(talisman.type).to eq "spirit beast talismans"
      end
    end
  end

  describe "toys" do
    [
      %{toy zombie},
      %{zombie toy},
    ].each do |toy_name|
      it "recognizes #{toy_name} as a toy" do
        toy = GameObjFactory.item_from_name(toy_name)
        expect(toy.type).to eq "toy"
      end
    end
  end

  describe "Simucoin items" do
    [
      %{Adventurer's Guild voucher pack},
      %{Elanthian Guilds voucher pack},
    ].each do |item_name|
      it "recognizes #{item_name} is NOT sellable" do
        item = GameObjFactory.item_from_name(item_name)
        expect(item.sellable).to eq nil
      end
    end
  end
end
