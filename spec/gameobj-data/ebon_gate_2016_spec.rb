require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "Ebon Gate 2016" do
    describe "Ebon Gate necropolis" do
      describe "quest (useful items from puzzle)" do
        necro_puzzle_nouns = %w[skull horn basilisk egg-eater adder rattlesnake]
        necro_puzzle_materials = %w[spinel quartz garnet onyx diopside jasper moonstone turquoise glaesine zircon peridot amethyst]
        necro_puzzle_descriptors = %w[cracked opaque chipped cloudy faceted polished brilliant]

        necro_puzzle_pieces = necro_puzzle_descriptors.product(necro_puzzle_materials, necro_puzzle_nouns) + [
          %w[glowing ruby eye],
        ]

        necro_puzzle_pieces.each do |desc, material, noun|
          quest_item_name = "#{desc} #{material} #{noun}"
          it "recognizes #{quest_item_name} as a quest item" do
            expect(GameObjFactory.item_from_name(quest_item_name).type).to eq "quest"
          end
        end
      end

      describe "junk (red herring items from puzzle)" do
        junk_descriptors = %w[cracked opaque chipped cloudy faceted polished brilliant]
        junk_materials = %w[spinel quartz garnet onyx diopside jasper moonstone turquoise glaesine zircon peridot amethyst]
        junk_nouns = %w[claw fang serpent hoof drake horse]

        junk_nouns.product(junk_descriptors, junk_materials).each do |noun, desc, material|
          junk_name = "#{desc} #{material} #{noun}"

          it "recognizes #{junk_name} as junk" do
            junk = GameObjFactory.item_from_name(junk_name)
            expect(junk.type).to eq "junk"
          end

          it "recognizes #{junk_name} as unsellable" do
            junk = GameObjFactory.item_from_name(junk_name)
            expect(junk.sellable).to be nil
          end
        end
      end
    end

    describe "ebongate" do
      [
        %{black-cored faceted star emerald},
        %{blackened angular bloodstone},
        %{block of beaver brown beryl},
        %{blossom of blushed ivory chalcedony},
        %{blue-swirled snow white garnet},
        %{bright red eyeball-shaped agate},
        %{cloud-shaped smoky grey smoldereye},
        %{copper-leafed pale green emerald},
        %{cracked crimson-flecked soulstone},
        %{crimson vathor-incised bloodjewel},
        %{cushion-cut circular violet sapphire},
        %{deep black silver-flecked starstone},
        %{deep green bug-filled amber},
        %{deep umber paw-shaped stone},
        %{ebon-ringed ruby},
        %{faceted blue-tinged quartz},
        %{faceted mint green sapphire},
        %{faceted ocean blue roestone},
        %{faceted yellow-tinged roestone},
        %{fist-sized sunset orange coral},
        %{flake of green and brown jade},
        %{fractured spiderweb turquoise},
        %{grey-hazed thistle purple jade},
        %{hollow pasty white pearl},
        %{hooked shard of inky deathstone},
        %{hunk of verlok-carved marble},
        %{indigo-cored blue sapphire},
        %{irregular dull grey opal},
        %{kaleidoscopic oblong saewehna},
        %{keen-edged fiery red garnet},
        %{large peridot},
        %{lucid icy blue diamond},
        %{mottled pink and white riftstone},
        %{murky green scale-patterned quartz},
        %{nightshade berry-hued moonstone},
        %{nugget of green-tinged quartz},
        %{pale piece of imp-shaped marble},
        %{piece of perfectly clear topaz},
        %{pitted ghostly white pearl},
        %{polished spike of argent topaz},
        %{polished sunset orange roestone},
        %{polished yellow-tinged sapphire},
        %{princess-cut alexandrite stone},
        %{puce abyran-etched sphene},
        %{purple bruise-hued opal},
        %{purple plum-shaped pearl},
        %{scratched spherical sapphire},
        %{sickle of brittle pink quartz},
        %{sliver of blue-tinged dreamstone},
        %{sliver of green-tinged glimaerstone},
        %{sliver of orange-tinged tourmaline},
        %{sliver of pale violet zircon},
        %{small key of ink blue riftstone},
        %{smooth disk of firestone},
        %{solid orb of zombie-engraved hematite},
        %{speckled rose pink ruby},
        %{sphere of animal-carved ivory},
        %{spherical smoky plum pearl},
        %{spiny hedgehog-shaped gem},
        %{splinter of grey-veined azurite},
        %{splinter of pale dragonmist crystal},
        %{thin-rayed black diamond starburst},
        %{thumb-sized blue-tinged tourmaline},
        %{thumb-sized mint green jade},
        %{thumb-sized sunny yellow dreamstone},
        %{twist of mint green sapphire},
        %{twisted and cracked indigo amethyst},
        %{very small sliver of jasper},
        %{very tiny sea green glimaerstone},
        %{vibrant orange and red sunstone},
        %{wave-edged aquamarine spherine},
        %{some deep green bug-filled amber},
        %{some gnarled pitch black coral},
        %{some pale fine-grained gypsum},
        %{some lustrous grooved obsidian},
      ].each do |valuable|
        it "recognizes #{valuable} as a valuable" do
          expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
          expect(GameObjFactory.item_from_name(valuable).type).to include "ebongate"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "skin"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "uncommon"

          expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
        end
      end
    end
  end

  describe "Ebon Gate 2019" do
    describe "gems" do
      [
        %{blackened feystone core},
        %{dark grey dreamstone fragment},
        %{fossilized thrak tooth},
        %{grooved burnt orange sea star},
        %{limpid dark indigo tidal pearl},
        %{piece of petrified wyrmwood},
        %{prismatic rose-gold fire agate},
        %{radiant lush viridian star emerald},
        %{rich cerulean mermaid's-tear sapphire},
        %{shard of pale grey shadowglass},
        %{spiny fan of lustrous black coral},
        %{stellular dragon's-tear diamond},
        %{teardrop of murky sanguine ruby},
        %{rainbow-hued oval abalone shell},
        %{rust-speckled ivory slipper shell},
        %{burnished sepia moonsnail shell},
        %{pale-spotted rosy sea urchin shell},
        %{misty silver crystalline spiral},
        %{branch of petrified driftwood},
        %{rough-edged matte white soulstone},
        %{honey-washed violet water sapphire},
        %{ebon-cored ruddy almandine garnet},
        %{wedge of ocher and ebony ambergris},
        %{cabochon of milky azure aquamarine},
        %{thin blade of verdant sea glass},
        %{purple-banded razor clam shell},
        %{five-pointed seafoam white sandsilver},
        %{triangular charcoal shark tooth},
        %{wine-tinged calico scallop shell},
      ].each do |gem|
        it "recognizes #{gem} as an Ebon Gate gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).type).to include "ebongate"
          expect(GameObjFactory.item_from_name(gem).type).to_not include "valuable"
          expect(GameObjFactory.item_from_name(gem).type).to_not include "skin"
          expect(GameObjFactory.item_from_name(gem).type).to_not include "uncommon"

          expect(GameObjFactory.item_from_name(gem).sellable).to eq "gemshop"
        end
      end
    end

    describe "quest items" do
      [
        %{smooth grey boulder},
        %{tumbled grey stone},

        %{blocky pine beam},
        %{forged horseshoe nail},
        %{rough oak post},
        %{rough piece of driftwood},
        %{smooth wooden plank},

        %{fistful of iron nails},
        %{square of thin grey shale},
        %{bluish grey slate tile},

        %{painted wood casing},
        %{warped wooden door},
        %{smooth glaesine window pane},

        %{tiny blue mosaic tile},
        %{bright red mosaic tile},
        %{some indigo and silver tiles},
        %{some green and white tiles},

        %{oak-handled diorite chisel},
        %{tumbled grey stone},
        %{smooth grey boulder},
        %{porous lava block},
        %{small eel-carved stone},
      ].each do |quest_item|
        it "recognizes #{quest_item} as an Ebon Gate quest item" do
          expect(GameObjFactory.item_from_name(quest_item).type).to include "ebongate"
          expect(GameObjFactory.item_from_name(quest_item).type).to include "quest"

          expect(GameObjFactory.item_from_name(quest_item).sellable.to_s).to be_empty

          expect(GameObjFactory.item_from_name(quest_item).type).to_not include "clothing"
          expect(GameObjFactory.item_from_name(quest_item).type).to_not include "gem"
          expect(GameObjFactory.item_from_name(quest_item).type).to_not include "valuable"
        end
      end

      [
        [%{waterproof bag}, %{of powdered lime}],
        [%{waterproof sack}, %{of mortar}],
        [%{small vial}, %{of black tar}],
      ].each do |(item_name, after_name)|
        it "recognizes #{item_name} #{after_name} as an Ebon Gate quest item" do
          quest_item = GameObjFactory.item_from_name(item_name, after_name)
          expect(quest_item.type).to include "ebongate"
          expect(quest_item.type).to include "quest"

          expect(quest_item.sellable.to_s).to be_empty

          expect(quest_item.type).to_not include "clothing"
          expect(quest_item.type).to_not include "gem"
          expect(quest_item.type).to_not include "valuable"
        end
      end
    end

    describe "junk" do
      junk_nouns = [
        %{iron doorknob},
        %{iron horseshoe},
        %{stone brick},
        %{table leg},
      ]
      junk_descriptors = %w[
        dirt-caked
        dirty
        encrusted
        gritty
        marred
        misshapen
        murky
        sand-caked
        scorched
        slimy
      ]

      junk_nouns.product(junk_descriptors).each do |noun, desc|
        junk_name = "#{desc} #{noun}"

        it "recognizes #{junk_name} as EG-flavored junk" do
          junk = GameObjFactory.item_from_name(junk_name)
          expect(junk.type).to eq "junk"
          expect(junk.sellable).to be nil
        end
      end
    end

    describe "other items" do
      [
        %{short-handled rusted steel shovel},
        %{eel-etched raffle token},
        %{some indigo-black seashells},
      ].each do |quest_item|
        it "recognizes #{quest_item} as an Ebon Gate item" do
          expect(GameObjFactory.item_from_name(quest_item).type).to eq "ebongate"
        end
      end
    end
  end

  describe "Ebon Gate 2020" do
    describe "gems" do
      [
        %{sickle-shaped opaque white soulstone},
      ].each do |gem|
        it "recognizes #{gem} as an Ebon Gate gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).type).to include "ebongate"
          expect(GameObjFactory.item_from_name(gem).type).to_not include "valuable"
          expect(GameObjFactory.item_from_name(gem).type).to_not include "skin"
          expect(GameObjFactory.item_from_name(gem).type).to_not include "uncommon"

          expect(GameObjFactory.item_from_name(gem).sellable).to eq "gemshop"
        end
      end
    end

    describe "quest items" do
      [
        %{pair of dark tin species},
        %{pair of dented pewter species},
        %{pair of scratched gold species},
        %{pair of tarnished steel species},
        %{pair of thin copper species},
      ].each do |quest_item_name|
        it "recognizes #{quest_item_name} as an Ebon Gate quest item" do
          expect(GameObjFactory.item_from_name(quest_item_name).type).to include "ebongate"
          expect(GameObjFactory.item_from_name(quest_item_name).type).to include "quest"
        end
      end
    end
  end
end
