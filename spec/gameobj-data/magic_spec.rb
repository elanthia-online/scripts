require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "magic items" do
    describe "common magic items" do
      [
        %{black crystal},
        %{blue crystal},
        %{bronze square},
        %{cracked clay disc},
        %{crystalline prism},
        %{deathstone granules},
        %{dull gold coin},
        %{gold-framed clear crystal lens},
        %{granite triangle},
        %{handful of fine firestone dust},
        %{heavy moonstone cube},
        %{heavy quartz orb},
        %{powdered iron filings},
        %{small statue},
        %{solid moonstone cube},
        %{white crystal},
      ].each do |magic_item_name|
        it "recognizes #{magic_item_name} as magic" do
          magic_item = GameObjFactory.item_from_name(magic_item_name)
          expect(magic_item.type).to include "magic"
          expect(magic_item.sellable).to eq "pawnshop"
        end
      end
    end

    describe "common magical jewelry" do
      [
        %{crystal amulet},
        %{ruby amulet},
      ].each do |magic_item_name|
        it "recognizes #{magic_item_name} as magic" do
          magic_item = GameObjFactory.item_from_name(magic_item_name)
          expect(magic_item.type).to include "magic"
          expect(magic_item.type).to_not include "jewelry"
          expect(magic_item.sellable).to eq "pawnshop"
        end
      end

      describe "gold rings" do
        [
          %{gold ring},

          %{braided gold ring},
          %{bright gold ring},
          %{dingy gold ring},
          %{dirt-caked gold ring},
          %{dull gold ring},
          %{exquisite gold ring},
          %{faded gold ring},
          %{flawless gold ring},
          %{inlaid gold ring},
          %{intricate gold ring},
          %{large gold ring},
          %{narrow gold ring},
          %{ornate gold ring},
          %{plain gold ring},
          %{polished gold ring},
          %{scratched gold ring},
          %{shiny gold ring},
          %{small gold ring},
          %{thick gold ring},
          %{thin gold ring},
          %{twisted gold ring},
          %{wide gold ring},
        ].each do |magic_item_name|
          it "recognizes #{magic_item_name} as magic" do
            magic_item = GameObjFactory.item_from_name(magic_item_name)
            expect(magic_item.type).to include "magic"
            expect(magic_item.type).to_not include "jewelry"
            expect(magic_item.sellable).to eq "pawnshop"
          end
        end
      end
    end

    describe "magical potions and other drinkables" do
      [
        %{grot t'kel potion},
        %{sky-blue potion},
        %{sea-green potion},
        %{incandescent crystalline vial},
        %{impure potion},
        %{pure potion},
        %{small glowing vial},
        %{white flask},
        %{grot t'kel potion},
        %{dirtokh potion},
        %{mirtokh potion},
        %{ayveneh potion},
      ].each do |magic_item_name|
        it "recognizes #{magic_item_name} as magic" do
          magic_item = GameObjFactory.item_from_name(magic_item_name)
          expect(magic_item.type).to eq "magic"
          #expect(magic_item.sellable).to eq "pawnshop"
        end
      end
    end

    describe "magic items created through alchemy" do
      [
        %{jagged glossy black shard},
        %{dimly glowing enruned bone talisman},
      ].each do |magic_item_name|
        it "recognizes #{magic_item_name} as magic" do
          magic_item = GameObjFactory.item_from_name(magic_item_name)
          expect(magic_item.type).to include "magic"
          expect(magic_item.sellable).to eq "consignment"
        end
      end
    end

    describe "magic item drops specific to certain creatures" do
      [
        %{shiny vor'taz horn},
        %{elementally tranquil core},
      ].each do |magic_item_name|
        it "recognizes #{magic_item_name} as magic" do
          magic_item = GameObjFactory.item_from_name(magic_item_name)
          expect(magic_item.type).to include "magic"
          expect(magic_item.type).to_not include "skin"
        end
      end
    end

    describe "randomized magic item drops from the treasure system" do
      [
        %{gritty demon figurine},
        %{glazed clay Imaera miniature},
        %{glittering steel orb},
        %{diamond-set Tonis sculpture},
        %{silver-inlaid elven maiden statue},
        %{dark maoral lizard statuette},
      ].each do |magic_item_name|
        it "recognizes #{magic_item_name} as magic" do
          magic_item = GameObjFactory.item_from_name(magic_item_name)
          expect(magic_item.type).to include "magic"
          expect(magic_item.sellable).to include "gemshop"
          expect(magic_item.sellable).to include "pawnshop"
        end
      end
    end

    describe "magic foods from EG" do
      [
        %{split-tipped putrid green tongue},
        %{pallid slimy tongue},
        %{dark red minotaur tongue},
        %{rancid black liver},
      ].each do |magic_item_name|
        it "recognizes #{magic_item_name} as magic" do
          magic_item = GameObjFactory.item_from_name(magic_item_name)
          expect(magic_item.type).to include "magic"
          expect(magic_item.type).to include "food"
          expect(magic_item.type).to_not include "skin"
        end
      end
    end
  end

  describe "wands" do
    describe "common wands" do
      [
        %{aquamarine wand},
        %{clear glass wand},
        %{crystal wand},
        %{golden wand},
        %{green coral wand},
        %{iron wand},
        %{metal wand},
        %{oaken wand},
        %{pale thanot wand},
        %{polished bloodwood wand},
        %{silver wand},
        %{slender blue wand},
        %{smooth amber wand},
        %{smooth bone wand},
        %{twisted wand},
      ].each do |wand_name|
        it "recognizes #{wand_name} as a wand" do
          wand = GameObjFactory.item_from_name(wand_name)
          expect(wand.type).to include "wand"
          expect(wand.sellable).to eq "pawnshop"
        end
      end
    end

    describe "randomized wand drops from the treasure system" do
      [
        %{elegant bronze baton},
        %{twisted bronze rod},
      ].each do |wand_name|
        it "recognizes #{wand_name} as a wand" do
          wand = GameObjFactory.item_from_name(wand_name)
          expect(wand.type).to include "wand"
          expect(wand.sellable).to include "gemshop"
          expect(wand.sellable).to include "pawnshop"
        end
      end
    end
  end

  describe "scrolls" do
    scroll_nouns = %w[palimpsest paper papyrus parchment scroll vellum]
    scroll_descriptors = [
      %{aged},
      %{ancient},
      %{arcane},
      %{blood-stained},
      %{burnt},
      %{charred},
      %{crumbling},
      %{crumpled},
      %{dark},
      %{faded},
      %{faded glyph-covered},
      %{forest green},
      %{glittering},
      %{glowing},
      %{golden},
      %{illuminated},
      %{light},
      %{luminous},
      %{moist wrinkled},
      %{neatly inked},
      %{obscure},
      %{old},
      %{piece of aged},
      %{piece of ancient},
      %{piece of blood-stained},
      %{piece of burnt},
      %{piece of crumbling},
      %{piece of faded},
      %{piece of glittering},
      %{piece of golden},
      %{piece of neatly inked},
      %{piece of obscure},
      %{piece of scorched},
      %{piece of shimmering},
      %{piece of tattered},
      %{resplendent},
      %{scorched},
      %{scrap of ancient},
      %{scrap of arcane},
      %{scrap of burnt},
      %{scrap of glittering},
      %{scrap of luminous},
      %{scrap of neatly inked},
      %{scrap of shimmering},
      %{scrap of wrinkled},
      %{sheaf of blood-stained},
      %{sheaf of burnt},
      %{sheaf of golden},
      %{sheaf of light},
      %{sheaf of neatly inked},
      %{sheaf of obscure},
      %{sheaf of old},
      %{sheaf of pure white},
      %{sheaf of scorched},
      %{sheaf of silvery},
      %{sheaf of torn},
      %{sheet of ancient},
      %{sheet of burnt},
      %{sheet of charred},
      %{sheet of illuminated},
      %{sheet of light},
      %{sheet of neatly inked},
      %{sheet of resplendent},
      %{sheet of scorched},
      %{sheet of smeared},
      %{sheet of tattered},
      %{sheet of torn},
      %{sheet of wrinkled},
      %{sheet of yellowed},
      %{shimmering},
      %{silvery},
      %{smeared},
      %{tattered},
      %{torn},
      %{wrinkled},
      %{yellowed},
    ]
    scroll_nouns.product(scroll_descriptors).each do |noun, desc|
      scroll_name = "#{desc} #{noun}"

      it "recognizes #{scroll_name} as a scroll" do
        scroll = GameObjFactory.item_from_name(scroll_name)
        expect(scroll.type).to eq "scroll"
        expect(scroll.sellable).to eq "pawnshop"
      end
    end
  end
end
