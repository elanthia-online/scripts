require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "alchemy" do
    describe "reagents" do
      [
        %{some powdered almandine garnet},
        %{some powdered aquamarine gem},
        %{some powdered azurite},
        %{some powdered black jasper},
        %{some powdered black opal},
        %{some powdered black pearl},
        %{some powdered black sphene},
        %{some powdered black tourmaline},
        %{some powdered blood red garnet},
        %{some powdered blue diamond},
        %{some powdered blue lapis lazuli},
        %{some powdered blue peridot},
        %{some powdered blue sapphire},
        %{some powdered blue spinel},
        %{some powdered blue starstone},
        %{some powdered blue tourmaline},
        %{some powdered bright bluerock},
        %{some powdered bright chrysoberyl gem},
        %{some powdered brilliant fire pearl},
        %{some powdered brown jade},
        %{some powdered brown sphene},
        %{some powdered cats-eye moonstone},
        %{some powdered citrine quartz},
        %{some powdered clear glimaerstone},
        %{some powdered clear sapphire},
        %{some powdered clear topaz},
        %{some powdered clear tourmaline},
        %{some powdered clear zircon},
        %{some powdered cloud agate},
        %{some powdered dark red-green bloodstone},
        %{some powdered deep blue eostone},
        %{some powdered deep purple amethyst},
        %{some powdered dragonfire opal},
        %{some powdered dragonseye sapphire},
        %{some powdered dragon's-tear diamond},
        %{some powdered emerald blazestar},
        %{some powdered faceted crystal crab shell},
        %{some powdered fiery jacinth},
        %{some powdered fire agate},
        %{some powdered fire opal},
        %{some powdered glossy black doomstone},
        %{some powdered golden beryl gem},
        %{some powdered golden moonstone},
        %{some powdered golden topaz},
        %{some powdered gold nugget},
        %{some powdered green garnet},
        %{some powdered green jade},
        %{some powdered green malachite stone},
        %{some powdered green peridot},
        %{some powdered green sapphire},
        %{some powdered green sphene},
        %{some powdered green starstone},
        %{some powdered green tourmaline},
        %{some powdered grey chalcedony},
        %{some powdered grey pearl},
        %{some powdered iridescent labradorite stone},
        %{some powdered iridescent piece of mother-of-pearl},
        %{some powdered Kezmonian honey beryl},
        %{some powdered large yellow diamond},
        %{some powdered moonglae opal},
        %{some powdered olivine feanor-bloom},
        %{some powdered orange imperial topaz},
        %{some powdered orange spessartine garnet},
        %{some powdered pale blue moonstone},
        %{some powdered pale green moonstone},
        %{some powdered pale water sapphire},
        %{some powdered pearl nautilus shell},
        %{some powdered piece of golden amber},
        %{some powdered pink dreamstone},
        %{some powdered pink pearl},
        %{some powdered pink rhodochrosite stone},
        %{some powdered pink sapphire},
        %{some powdered pink topaz},
        %{some powdered rainbow quartz},
        %{some powdered rock crystal},
        %{some powdered rose quartz},
        %{some powdered ruby-lined nassa shell},
        %{some powdered scaly burgee shell},
        %{some powdered sea urchin shell},
        %{some powdered shimmarglin sapphire},
        %{some powdered shimmertine shard},
        %{some powdered smoky glimaerstone},
        %{some powdered smoky topaz},
        %{some powdered snake-head cowrie shell},
        %{some powdered some polished blue coral},
        %{some powdered some polished pink coral},
        %{some powdered some polished red coral},
        %{some powdered sparkling silvery conch shell},
        %{some powdered spiderweb turquoise},
        %{some powdered star ruby},
        %{some powdered star sapphire},
        %{some powdered turquoise stone},
        %{some powdered uncut diamond},
        %{some powdered uncut emerald},
        %{some powdered uncut maernstrike diamond},
        %{some powdered uncut ruby},
        %{some powdered uncut star-of-Tamzyrr diamond},
        %{some powdered violet sapphire},
        %{some powdered white chalcedony},
        %{some powdered white clam shell},
        %{some powdered white jade},
        %{some powdered white marble},
        %{some powdered white opal},
        %{some powdered white pearl},
        %{some powdered white starstone},
        %{some powdered white sunstone},
        %{some powdered yellow hyacinth},
        %{some powdered yellow sapphire},

      ].each do |reagent|
        it "recognizes #{reagent} as a reagent" do
          expect(GameObjFactory.item_from_name(reagent).type).to include "reagent"
          expect(GameObjFactory.item_from_name(reagent).type).to_not include "gem"
          expect(GameObjFactory.item_from_name(reagent).type).to_not include "skin"
          # not listed in sellable data
        end
      end

      [
        %{ayanad crystal},
        %{cluster of ayanad crystals},
        %{cluster of s'ayanad crystals},
        %{cluster of t'ayanad crystals},
        %{cracked soulstone},
        %{crimson troll king bezoar},
        %{crystal core},
        %{crystalline globe},
        %{elemental core},
        %{emerald stone giant bezoar},
        %{glimmering blue essence shard},
        %{glimmering blue mote of essence},
        %{glowing violet essence shard},
        %{glowing violet mote of essence},
        %{inky necrotic core},
        %{large troll tooth},
        %{n'ayanad crystal},
        %{perfect myklian belly scale},
        %{pristine nymph's hair},
        %{pristine siren's hair},
        %{pristine sprite's hair},
        %{radiant crimson essence shard},
        %{radiant crimson mote of essence},
        %{saffron gremlock bezoar},
        %{s'ayanad crystal},
        %{small troll tooth},
        %{some essence of air},
        %{some essence of earth},
        %{some essence of fire},
        %{some essence of water},
        %{essence of greater earth},
        %{essence of greater air},
        %{essence of greater fire},
        %{essence of greater water},
        %{some glimmering blue essence dust},
        %{some glowing violet essence dust},
        %{some radiant crimson essence dust},
        %{t'ayanad crystal},
        %{tiny golden seed},
        %{vial of farlook vitreous humor},
        %{violet Ithzir bezoar},
      ].each do |reagent|
        it "recognizes #{reagent} as a reagent" do
          expect(GameObjFactory.item_from_name(reagent).type).to include "reagent"
          expect(GameObjFactory.item_from_name(reagent).type).to_not include "gem"
          expect(GameObjFactory.item_from_name(reagent).type).to_not include "skin"

          expect(GameObjFactory.item_from_name(reagent).sellable).to include "consignment"
        end
      end
    end

    describe "products" do
      %w[minor lesser greater full].product([
        %{mana},
        %{mana regeneration},
        %{mana-well},
      ]).each do |strength, flavor|
        potion = "#{strength} #{flavor} potion"

        it "recognizes a #{potion} as an alchemy product" do
          expect(GameObjFactory.item_from_name(potion).type).to include "alchemy product"
        end
      end

      [
        %{glowing moonstone talisman},
        %{mottled malachite talisman},
        %{dark murky potion},
        %{clear potion},
        %{hazy glass vial},
        %{glowing brilliant silver potion},
        %{silvery potion},
        %{diaphanous eight-sided crystal},
        %{dark translucent crystal},
        %{swirling grey potion},
      ].each do |alchemy_product|
        it "recognizes #{alchemy_product} as an alchemy product" do
          expect(GameObjFactory.item_from_name(alchemy_product).type).to include "alchemy product"
          expect(GameObjFactory.item_from_name(alchemy_product).sellable).to include "consignment"
        end
      end
    end

    describe "equipment" do
      [
        %{sapphire lens},
        %{emerald lens},
        %{diamond lens},
        %{ruby lens},
        %{amethyst lens},
        %{shadowglass lens},
        %{small crystal flask},
        %{clouded glass vial},
        %{warped glass vial},
        %{chipped glass vial},
        %{tapered glass vial},
        %{smoky glass vial},
        %{thick glass vial},
        %{slender glass vial},
        %{black iron cauldron},
        %{ivory porcelain mortar},
      ].each do |alchemy_equipment|
        it "recognizes #{alchemy_equipment} as alchemy equipment" do
          expect(GameObjFactory.item_from_name(alchemy_equipment).type).to include "alchemy equipment"
        end
      end
    end
  end
end

