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
end
