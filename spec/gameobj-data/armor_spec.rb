require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  junk_armor_drops = [
    %{some dirty brown robes},
    %{some flowing robes},
    %{some tattered white robes},
  ]

  describe "armor" do

    describe "randomized treasure system drops" do
      spikes = [
        %{},
        %{spiked },
      ]

      shield_metals = [
        %{eahnor},
        %{faenor},
        %{golvern},
        %{imflass},
        %{mithglin},
        %{mithril},
        %{ora},
        %{rolaren},
        %{vaalorn},
        %{veil iron},
        %{vultite},
      ]

      armor_materials  = [
        %{},
        %{glaes },
      ] + shield_metals.map { |m| "#{m} " }

      armor_accessory_materials  = [
        %{glaes },
      ] + shield_metals.map { |m| "#{m} " }

      metallic_adjectives = [
          %{},
          %{blackened },
          %{embossed },
          %{etched },
          %{gleaming },
          %{old },
          %{ornate },
          %{polished },
          %{scratched },
          %{thick },
        ]

      describe "robes" do
        robe_adjectives = [
          %{},
          %{cinched },
          %{elegant },
          %{flowing },
          %{fringed },
          %{gold-lined },
          %{hooded },
          %{long },
          %{soft },
        ]

        materials = [
          %{},
          %{cotton },
          %{fleece },
          %{linen },
          %{satin },
          %{silk },
          %{velvet },
          %{woolen },
        ]

        colors = [
          %{},
          %{blue },
          %{brown },
          %{grey },
          %{orange },
          %{purple },
          %{red },
          %{white },
        ]

        robe_adjectives.product(colors, materials).each do |(adjective, color, material)|
          armor_name = %{some #{adjective}#{color}#{material}robes}
          next if junk_armor_drops.include?(armor_name)

          it "recognizes #{armor_name} as armor" do
            armor = GameObjFactory.item_from_name(armor_name)
            expect(armor.type).to include "armor"
            expect(armor.sellable).to eq "pawnshop"
          end
        end
      end

      describe "chest armor with leather material" do
        leather_adjectives = [
          %{},
          %{burnished },
          %{embossed },
          %{golden },
          %{old },
          %{polished },
          %{scarred },
          %{scorched },
          %{thick },
          %{tooled },
        ]

        [
          %{light leather},
          %{full leather},
          %{reinforced leather},
          %{double leather},
          %{cuirbouilli leather},
        ].product(leather_adjectives, spikes).each do |(base, adj, spike)|
          armor_name = "some #{adj}#{spike}#{base}"

          it "recognizes #{armor_name} as armor" do
            armor = GameObjFactory.item_from_name(armor_name)
            expect(armor.type).to include "armor"
            expect(armor.sellable).to eq "pawnshop"
          end
        end

        [
          %{leather breastplate},
        ].product(leather_adjectives, spikes).each do |(base, adj, spike)|
          armor_name = "#{adj}#{spike}#{base}"

          it "recognizes #{armor_name} as armor" do
            armor = GameObjFactory.item_from_name(armor_name)
            expect(armor.type).to include "armor"
            expect(armor.sellable).to eq "pawnshop"
          end
        end
      end

      describe "chest armors with metal material" do
        [
          %{chain hauberk},
          %{metal breastplate},
          %{augmented breastplate},
        ].product(metallic_adjectives, spikes, armor_materials).each do |(base, adj, spike, material)|
          armor_name = "#{adj}#{spike}#{material}#{base}"

          it "recognizes #{armor_name} as armor" do
            armor = GameObjFactory.item_from_name(armor_name)
            expect(armor.type).to include "armor"
            expect(armor.sellable).to eq "pawnshop"
          end
        end

        [
          %{studded leather},
          %{brigandine armor},
          %{chain mail},
          %{double chain},
          %{augmented chain},
          %{half plate},
          %{full plate},
        ].product(metallic_adjectives, spikes, armor_materials).each do |(base, adj, spike, material)|
          armor_name = "some #{adj}#{spike}#{material}#{base}"

          it "recognizes #{armor_name} as armor" do
            armor = GameObjFactory.item_from_name(armor_name)
            expect(armor.type).to include "armor"
            expect(armor.sellable).to eq "pawnshop"
          end
        end
      end

      describe "shields" do
        shield_nouns = [
          %{aegis},
          %{buckler},
          %{greatshield},
          %{shield},
        ]

        describe "made of metal" do
          shield_nouns.product(metallic_adjectives, spikes, shield_metals).each do |(noun, adj, spike, material)|
            shield_name = "#{adj}#{spike}#{material} #{noun}"

            it "recognizes #{shield_name} as armor" do
              shield = GameObjFactory.item_from_name(shield_name)
              expect(shield.type).to include "armor"
              expect(shield.sellable).to eq "pawnshop"
            end
          end
        end

        describe "made of wood or non-metallic material" do
          wooden_adjectives = [
            %{},
            %{burnished },
            %{carved },
            %{embossed },
            %{nicked },
            %{old },
            %{ornate },
            %{scratched },
            %{thick },
          ]

          shield_woods = [
            %{carmiln},
            %{deringo},
            %{faewood},
            %{fireleaf},
            %{glaes}, # glaes uses the same adjectives as wood
            %{glowbark},
            %{kakore},
            %{mesille},
            %{mossbark},
            %{villswood},
          ]

          shield_nouns.product(wooden_adjectives, spikes, shield_woods).each do |(noun, adj, spike, material)|
            shield_name = "#{adj}#{spike}#{material} #{noun}"

            it "recognizes #{shield_name} as armor" do
              shield = GameObjFactory.item_from_name(shield_name)
              expect(shield.type).to include "armor"
              expect(shield.sellable).to eq "pawnshop"
            end
          end
        end
      end

      describe "armor accessories" do
        [
          %{arm greaves},
          %{leg greaves},
        ].product(metallic_adjectives, spikes, armor_accessory_materials).each do |(base, adj, spike, material)|
          armor_name = "some #{adj}#{spike}#{material}#{base}"

          it "recognizes #{armor_name} as armor" do
            armor = GameObjFactory.item_from_name(armor_name)
            expect(armor.type).to include "armor"
            expect(armor.sellable).to eq "pawnshop"
          end
        end

        [
          %{aventail},
          %{greathelm},
          %{helm},
        ].product(metallic_adjectives, spikes, armor_accessory_materials).each do |(base, adj, spike, material)|
          armor_name = "#{adj}#{spike}#{material}#{base}"

          it "recognizes #{armor_name} as armor" do
            armor = GameObjFactory.item_from_name(armor_name)
            expect(armor.type).to include "armor"
            expect(armor.sellable).to eq "pawnshop"
          end
        end

        [
          %{aventail},
        ].product(metallic_adjectives, armor_accessory_materials).each do |(base, adj, material)|
          armor_name = "#{adj}#{material}#{base}"

          it "recognizes #{armor_name} as armor" do
            armor = GameObjFactory.item_from_name(armor_name)
            expect(armor.type).to include "armor"
            expect(armor.sellable).to eq "pawnshop"
          end
        end
      end
    end

    [
      %{doublet},
      %{some armor},
      %{some leather},
      %{some leathers},
      %{some leather armor},
      %{some chain armor},
      %{leather breastplate},
      %{metal breastplate},
      %{some plate armor},
      %{some full plate},
      %{some half plate},

      %{mantlet},
    ].each do |armor_name|
      it "recognizes #{armor_name} as armor" do
        armor = GameObjFactory.item_from_name(armor_name)
        expect(armor.type).to eq "armor"
        expect(armor.sellable).to eq "pawnshop"
      end
    end
  end

  describe "things that are not armor" do
    junk_armor_drops.each do |item_name|
      it "recognizes #{item_name} is NOT armor" do
        item = GameObjFactory.item_from_name(item_name)
        expect(item.type.to_s).to_not include "armor"
        expect(item.sellable.to_s).to_not include "pawnshop"
      end
    end
  end
end
