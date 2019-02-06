require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "Duskruin" do
    describe "gems" do
      [
        %{flame-banded gold chameleon agate},
        %{thin shard of iridescent fire agate},
        %{gently sloped green moss agate},
        %{round of gnat-filled amber},
        %{slice of gold-blended ametrine},
        %{fragment of lilac-toned amethyst},
        %{brilliant teal-laced azurite},
        %{scintillating scarlet red blazestar},
        %{inky-cored vivid carmine bloodjewel},
        %{cluster of gingery golden chrysoberyl},
        %{clouded maize-colored citrine},
        %{pale metallic silver mistvein diamond},
        %{square-cut deep pink diamond},
        %{sharply cut salorisa pink diamond},
        %{large blood red diamond},
        %{flawless argent-white diamond},
        %{pale-edged powder blue dreamstone},
        %{smooth black umber-suffused dreamstone},
        %{heart-shaped aqua green emerald},
        %{black-rayed celadon star emerald},
        %{multi-faceted sky blue feystone},
        %{six-pointed rich sanguine garnet},
        %{beryl green crystal-filled geode},
        %{pristine smoky violet glimaerstone},
        %{teardrop of mauve petrified haon},
        %{dainty orb of primrose yellow heliodor},
        %{cushion-cut ember orange hyacinth},
        %{bronze-tinged lambent yellow jacinth},
        %{slim bar of woodland green jade},
        %{pyrite-capped vibrant blue lapis lazuli},
        %{small disk of velvety green malachite},
        %{silver-washed celestial blue moonstone},
        %{cyan-haloed creamy ivory moonstone},
        %{pearlescent raven black opal},
        %{pellucid blue-green ora-bloom},
        %{oversized shadowy purple pearl},
        %{glimmering magnolia white pearl},
        %{tiny prism of wintry blue peridot},
        %{trilliant-cut yellow-green peridot},
        %{triangular pastel rainbow quartz},
        %{hazy shard of faint pink rose quartz},
        %{cube of sheer blossom pink rosespar},
        %{wheel-incised incarnadine ruby},
        %{coin-sized seafoam white sandsilver},
        %{silver-swept blue mistvein sapphire},
        %{honey-tinted indigo water sapphire},
        %{dark-veined apple green turquoise},
      ].each do |gem_name|
        it "recognizes #{gem_name} as a Duskruin gem" do
          expect(GameObjFactory.item_from_name(gem_name).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem_name).type).to include "event:duskruin"
        end
      end
    end

    describe "moonshards" do
      [
        %{jagged white sunstone shard},
        %{broken white opal sphere},
        %{white dreamstone sliver},
        %{thin platinum strip},
        %{black opal fragment},
        %{blood red garnet chunk},
        %{coarse grey moonstone shard},
        %{thin iron strip},
        %{cracked ur-barath stone},
        %{broken fire opal chunk},
        %{splintered fire agate shard},
        %{thin kakore strip},
        %{lopsided golden moonstone sphere},
        %{sharp golden topaz shard},
        %{golden glimaerstone nugget},
        %{reticulated crystal-edged golvern segment},
      ].each do |moonshard|
        it "recognizes #{moonshard} as a Duskruin quest item" do
          expect(GameObjFactory.item_from_name(moonshard).type).to include "quest"
          expect(GameObjFactory.item_from_name(moonshard).type).to include "event:duskruin"
        end
      end
    end
  end
end
