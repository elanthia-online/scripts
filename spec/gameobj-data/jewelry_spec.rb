require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "jewelry" do
    describe "sellable" do
      %w[
        amulet
        anklet
        band
        barrette
        bowl
        bracelet
        bracer
        brooch
        buckle
        chalice
        circlet
        clasp
        crown
        cup
        earcuff
        earring
        earrings
        ewer
        flagon
        flask
        goblet
        headband
        jug
        medallion
        neckchain
        necklace
        pendant
        pin
        pitcher
        plate
        platter
        ring
        scepter
        stein
        stickpin
        talisman
        tiara
        torc
        tray
        urn
      ].each do |jewelry_name|
        it "recognizes #{jewelry_name} as sellable jewelry" do
          jewelry = GameObjFactory.item_from_name(jewelry_name)
          expect(jewelry.type).to eq "jewelry"
          expect(jewelry.sellable.to_s).to include "gemshop"
        end
      end

      describe "randomized treasure system drops", slow: true do
        # only have data for wearables so far
        # TODO: armband
        jewelry_nouns = %w[
          band
          barrette
          bracelet
          bracer
          brooch
          buckle
          circlet
          clasp
          crown
          earcuff
          earring
          headband
          medallion
          neckchain
          necklace
          pendant
          pin
          platter
          ring
          stickpin
          talisman
          tiara
          torc
        ]

        it "recognizes randomized jewelry made primarily from metal" do
          jewelry_metals = [
            %{copper},
            %{eonake},
            %{gold},
            %{gold alloy},
            %{imflass},
            %{mithril},
            %{mithril alloy},
            %{ora},
            %{pewter},
            %{platinum},
            %{silver},
            %{silver alloy},
            %{sterling silver},
          ]

          jewelry_metal_modifiers = [
            %{agate-inset},
            %{bejewelled},
            %{beryl-inset},
            %{bone-inlaid},
            %{brushed},
            %{chased},
            %{coral inset},
            %{coral studded},
            %{cut emerald},
            %{cut firestone},
            %{delicate},
            %{diamond-set},
            %{elegant},
            %{emerald-set},
            %{engraved},
            %{enruned},
            %{etched},
            %{filigreed},
            %{fine},
            %{garnet-set},
            %{gem-encrusted},
            %{glittering},
            %{glyph-etched},
            %{hammered},
            %{ivory-inlaid},
            %{jade-inlaid},
            %{lapis-inlaid},
            %{malachite-set},
            %{onyx-inlaid},
            %{opal-inset},
            %{ruby-inset},
            %{rune-etched},
            %{sapphire-set},
            %{snake-etched},
            %{tooled},
            %{topaz-inset},
            %{turquoise-set},
          ]

          metal_jewelry = jewelry_metal_modifiers.product(jewelry_metals, jewelry_nouns).each do |combo|
            jewelry_name = combo.join(" ")

            jewelry = GameObjFactory.item_from_name(jewelry_name)
            expect(jewelry.type).to include "jewelry"
            expect(jewelry.sellable.to_s).to include "gemshop"
          end
        end

        it "recognizes randomized jewelry made primarily of gemstone" do
          jewelry_gem_materials = [
            %{alexandrite},
            %{amber},
            %{amethyst},
            %{aquamarine},
            %{beryl},
            %{black opal},
            %{black pearl},
            %{bloodjewel},
            %{bloodstone},
            %{blue diamond},
            %{blue dreamstone},
            %{blue sapphire},
            %{blue starstone},
            %{blue tourmaline},
            %{chrysoberyl},
            %{deathstone},
            %{diamond},
            %{dragonfire opal},
            %{dreamstone},
            %{emerald},
            %{fire opal},
            %{fire pearl},
            %{firestone},
            %{garnet},
            %{golden topaz},
            %{green garnet},
            %{green spinel},
            %{lapis lazuli},
            %{peridot},
            %{pink dreamstone},
            %{pink sapphire},
            %{pink topaz},
            %{pink tourmaline},
            %{red dreamstone},
            %{red spinel},
            %{red sunstone},
            %{ruby},
            %{smoky topaz},
            %{star emerald},
            %{star ruby},
            %{star sapphire},
            %{white starstone},
            %{white sunstone},
          ]

          jewelry_gem_modifiers = [
            %{beveled},
            %{bone-inlaid},
            %{brilliant},
            %{bronze and},
            %{carved},
            %{chiseled},
            %{copper and},
            %{coral and},
            %{cushion-cut},
            %{delicate},
            %{elegant},
            %{engraved},
            %{enruned},
            %{faceted},
            %{fine},
            %{flame-cut},
            %{gleaming},
            %{glittering},
            %{glyph-etched},
            %{gold and},
            %{gold filigree},
            %{heart-cut},
            %{ivory and},
            %{ivory-inlaid},
            %{jade and},
            %{jade-inlaid},
            %{long-cut},
            %{malachite and},
            %{marquise-cut},
            %{mithril and},
            %{onyx and},
            %{onyx-inlaid},
            %{opal and},
            %{oval-cut},
            %{pear-cut},
            %{pearl and},
            %{petal-cut},
            %{pewter and},
            %{plain},
            %{polished},
            %{princess-cut},
            %{radiant-cut},
            %{rune-etched},
            %{serpentine},
            %{silver and},
            %{simple},
            %{sparkling},
            %{square-cut},
            %{star-cut},
            %{step-cut},
            %{tear-cut},
            %{tooled},
            %{trilliant-cut},
          ]

          gem_jewelry = jewelry_gem_modifiers.product(jewelry_gem_materials, jewelry_nouns).each do |combo|
            jewelry_name = combo.join(" ")

              jewelry = GameObjFactory.item_from_name(jewelry_name)
              expect(jewelry.type).to include "jewelry"
              expect(jewelry.sellable.to_s).to include "gemshop"
          end
        end

        it "regognizes randomized jewelry made of a gem and metal combo" do
          jewelry_combo_gems = [
            %{alexandrite},
            %{amber},
            %{amethyst},
            %{aquamarine},
            %{black opal},
            %{black pearl},
            %{bloodjewel},
            %{bloodstone},
            %{blue diamond},
            %{blue sapphire},
            %{chrysoberyl},
            %{coral},
            %{cut emerald},
            %{cut firestone},
            %{deathstone},
            %{dreamstone},
            %{faceted ruby},
            %{fire opal},
            %{fire pearl},
            %{golden topaz},
            %{green garnet},
            %{green spinel},
            %{lapis lazuli},
            %{malachite},
            %{moonstone},
            %{moss agate},
            %{onyx},
            %{opal},
            %{pearl},
            %{peridot},
            %{pink pearl},
            %{pink topaz},
            %{red garnet},
            %{smoky topaz},
            %{soulstone},
            %{star ruby},
            %{star sapphire},
            %{starstone},
            %{tourmaline},
            %{turquoise},
            %{white opal},
          ]

          jewelry_combo_adjectives = [
            %{inset},
            %{studded},
          ]

          jewelry_combo_metals = %w[
            bronze
            copper
            gold
            eonake
            mithril
            ora
            pewter
            platinum
            silver
          ]

          jewelry_combo_gems.product(jewelry_combo_adjectives, jewelry_combo_metals, jewelry_nouns).each do |combo|
            jewelry_name = combo.join(" ")

            jewelry = GameObjFactory.item_from_name(jewelry_name)
            expect(jewelry.type).to include "jewelry"
            expect(jewelry.sellable.to_s).to include "gemshop"
          end
        end
      end
    end

    describe "non-sellable" do
      %w[
        badge
      ].each do |jewelry_name|
        it "recognizes #{jewelry_name} as non-sellable jewelry" do
          jewelry = GameObjFactory.item_from_name(jewelry_name)
          expect(jewelry.type).to include "jewelry"
          expect(jewelry.sellable.to_s).to_not include "gemshop"
        end
      end
    end
  end
end
