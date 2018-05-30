require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "globally available" do
    describe "gems" do
      [
        %{almandine garnet},
        %{aquamarine gem},
        %{banded agate},
        %{banded sardonyx stone},
        %{black opal},
        %{black pearl},
        %{black tourmaline},
        %{blue cordierite},
        %{blue lace agate},
        %{blue sapphire},
        %{blue spinel},
        %{blue topaz},
        %{blue tourmaline},
        %{bright chrysoberyl gem},
        %{bright violet feystone},
        %{brown zircon},
        %{clear sapphire},
        %{clear topaz},
        %{clear tourmaline},
        %{clear zircon},
        %{cloud agate},
        %{dark red-green bloodstone},
        %{deep purple amethyst},
        %{dwarf-cut diamond},
        %{fire agate},
        %{fire opal},
        %{golden beryl gem},
        %{golden topaz},
        %{green alexandrite stone},
        %{green aventurine stone},
        %{green chrysoprase gem},
        %{green garnet},
        %{green malachite stone},
        %{green sapphire},
        %{green tourmaline},
        %{green zircon},
        %{grey pearl},
        %{iridescent labradorite stone},
        %{large piece of mica},
        %{light pink morganite stone},
        %{moss agate},
        %{mottled agate},
        %{olivine faenor-bloom},
        %{petrified aivren egg},
        %{piece of black jasper},
        %{piece of black marble},
        %{piece of black onyx},
        %{piece of blue quartz},
        %{piece of blue ridge coral},
        %{piece of brown jade},
        %{piece of carnelian quartz},
        %{piece of cat's eye quartz},
        %{piece of citrine quartz},
        %{piece of golden amber},
        %{piece of green jade},
        %{piece of green marble},
        %{piece of obsidian},
        %{piece of onyx},
        %{piece of petrified thanot},
        %{piece of pink marble},
        %{piece of red jasper},
        %{piece of rose quartz},
        %{piece of spiderweb obsidian},
        %{piece of white jade},
        %{piece of white marble},
        %{piece of yellow jasper},
        %{pink pearl},
        %{pink rhodocrosite stone},
        %{pink sapphire},
        %{pink spinel},
        %{pink topaz},
        %{pink tourmaline},
        %{polished black coral},
        %{polished blue coral},
        %{polished jet stone},
        %{polished pink coral},
        %{polished red coral},
        %{quartz crystal},
        %{quartz crystal},
        %{red spinel},
        %{rock crystal},
        %{shard of rainbow quartz},
        %{shimmertine shard},
        %{smoky topaz},
        %{star diopside},
        %{star ruby},
        %{star sapphire},
        %{turquoise stone},
        %{umber sard},
        %{uncut diamond},
        %{uncut emerald},
        %{uncut ruby},
        %{violet sapphire},
        %{violet spinel},
        %{white opal},
        %{white pearl},
        %{yellow sapphire},
        %{yellow zircon},
      ].each do |gem|
        it "recognizes #{gem} as a gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).sellable).to include "gemshop"
        end
      end

      it "recognizes blue lapis lazuli as a gem" do
        lapis_obj = GameObjFactory.item_from_name("blue lapis lazuli", "lapis")
        expect(lapis_obj.type).to include "gem"
        expect(lapis_obj.type).to_not include "valuable"
        expect(lapis_obj.sellable).to include "gemshop"
      end
    end

    describe "valuables" do
      [
        %{piece of petrified haon},
        %{piece of rosespar},
      ].each do |valuable|
        it "recognizes #{valuable} as a valuable" do
          expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
          expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
        end
      end
    end
  end

  describe "Elven Nations" do
    describe "gems" do
      [
        %{azure blazestar},
        %{blue shimmarglin sapphire},
        %{brilliant lilac glimaerstone},
        %{cerulean glimaerstone},
        %{clear glimaerstone},
        %{crimson blazestar},
        %{deep red carbuncle},
        %{dragon's-tear diamond},
        %{dragon's-tear emerald},
        %{dragon's-tear ruby},
        %{dragonseye sapphire},
        %{emerald blazestar},
        %{fiery jacinth},
        %{golden blazestar},
        %{golden glimaerstone},
        %{green errisian topaz},
        %{green glimaerstone},
        %{green ora-bloom},
        %{lavender shimmarglin sapphire},
        %{moonglae opal},
        %{orange imperial topaz},
        %{orange spessartine garnet},
        %{pale blue moonstone},
        %{pale green moonstone},
        %{pale water sapphire},
        %{pale yellow heliodor},
        %{peach glimaerstone},
        %{periwinkle feystone},
        %{piece of banded onyx},
        %{piece of white chalcedony},
        %{scarlet despanal},
        %{silvery moonstone},
        %{small purple geode},
        %{smoky glimaerstone},
        %{spiderweb turquoise},
        %{sylvarraend ruby},
        %{tigereye agate},
        %{ultramarine glimaerstone},
        %{uncut maernstrike diamond},
        %{yellow hyacinth},
      ].each do |gem|
        it "recognizes #{gem} as a gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).sellable).to include "gemshop"
        end
      end
    end

    describe "valuables" do
      describe "gold dust from Gossamer Valley" do
        [
          %{dram of gold dust},
          %{handful of gold dust},
          %{pinch of gold dust},
        ].each do |valuable|
          it "recognizes #{valuable} as a valuable" do
            expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
            expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
            expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
          end
        end
      end
    end
  end

  describe "Icemule and Pinefar" do
    describe "gems" do
      [
        %{blood red garnet},
        %{blue-white frost opal},
        %{clear blue gem},
        %{frost agate},
        %{golden rhimar-bloom},
        %{large yellow diamond},
        %{piece of polished ivory},
        %{piece of yellow jade},
        %{shard of tigerfang crystal},
        %{snowflake zircon},
      ].each do |gem|
        it "recognizes #{gem} as a gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).sellable).to include "gemshop"
        end
      end
    end

    describe "valuables" do
      [
        %{gold nugget},
        %{large gold nugget},
        %{large platinum nugget},
        %{platinum nugget},
      ].each do |valuable|
        it "recognizes #{valuable} as a valuable" do
          expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
          expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
        end
      end
    end
  end

  describe "The Rift" do
    describe "gems" do
      [
        %{aster opal},
        %{blue star-shaped riftshard},
        %{brilliant wyrm's-tooth amethyst},
        %{deep blue thunderstone},
        %{dragon's-fang quartz},
        %{eye-of-koar emerald},
        %{faceted black diamond},
        %{faceted midnight blue riftstone},
        %{glossy black doomstone},
        %{metallic black pearl},
        %{milky quartz eye},
        %{multi-colored wyrdshard},
        %{obsidian eye},
        %{pale violet riftstone},
        %{piece of black riftstone},
        %{radiant opalescent thunderstone},
        %{sanguine wyrm's-eye garnet},
        %{shard of dragonmist crystal},
        %{shard of oblivion quartz},
        %{smoky grey thunderstone},
        %{swirling aetherstone},
        %{swirling purple thunderstone},
        %{tiny black and blue spherine},
        %{tiny green and grey spherine},
        %{tiny red and blue spherine},
        %{tiny white and black spherine},
        %{transparent spherine},
      ].each do |gem|
        it "recognizes #{gem} as a gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).sellable).to include "gemshop"
        end
      end
    end

    describe "valuables" do
      [
        %{chalky yellow cube},

        %{bronze fang},
        %{copper fang},
        %{gold fang},
        %{iron fang},
        %{mithril fang},
        %{platinum fang},
        %{silver fang},
        %{steel fang},
        %{golden firemote orb},
        %{murky shadowglass orb},

        %{deep blue sapphire talon},
        %{fiery ruby talon},
        %{glistening onyx talon},
        %{sparkling emerald talon},

        %{small crystal-spoked wheel},
        %{dark-spoked crystalline wheel},
      ].each do |valuable|
        it "recognizes #{valuable} as a valuable" do
          expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "skin"
          expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
        end
      end

      describe "valuables with data issues" do
        [
          %{urglaes fang},
        ].each do |valuable|
          it "recognizes #{valuable} as a valuable" do
            expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
            expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
          end

          xit "recognizes #{valuable} as sellable at the gemshop" do
            expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
          end
        end
      end
    end
  end

  describe "Teras Isle" do
    describe "gems" do
      [
        %{asterfire quartz},
        %{black deathstone},
        %{black dreamstone},
        %{black moonstone},
        %{blue diamond},
        %{blue dreamstone},
        %{blue moonstone},
        %{blue peridot},
        %{blue starstone},
        %{cats-eye moonstone},
        %{chameleon agate},
        %{dragonfire emerald},
        %{dragonfire opal},
        %{dragonfire quartz},
        %{dragonsbreath sapphire},
        %{fiery red gem},
        %{fiery viridian soulstone},
        %{firestone},
        %{golden moonstone},
        %{green dreamstone},
        %{green peridot},
        %{green starstone},
        %{grey moonstone},
        %{leopard quartz},
        %{opaline moonstone},
        %{pink dreamstone},
        %{pink peridot},
        %{red dreamstone},
        %{red starstone},
        %{red sunstone},
        %{small blue geode},
        %{small green geode},
        %{small red geode},
        %{star emerald},
        %{white dreamstone},
        %{white starstone},
        %{white sunstone},
        %{yellow dreamstone},
        %{yellow sunstone},
      ].each do |gem|
        it "recognizes #{gem} as a gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).sellable).to include "gemshop"
        end
      end
    end

    describe "valuables" do
      [%{glaesine crystal}].each do |valuable|
        it "recognizes #{valuable} as a valuable" do
          expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
          expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
        end
      end
    end
  end

  describe "Four Winds Isle" do
    describe "gems" do
      [
        %{bright orange butterfly saewehna},
        %{iridescent azure butterfly saewehna},
        %{jewel-toned dragonfly saewehna},
        %{nacreous blue waterweb},
        %{pale gold firefly saewehna},
        %{russet and cream moth saewehna},
        %{silver firefly saewehna},
        %{silvery mint green moth saewehna},
        %{vibrant hummingbird saewehna},
      ].each do |gem|
        it "recognizes #{gem} as a gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).sellable).to include "gemshop"
        end
      end
    end
  end

  describe "krag dwellers gems" do
    ["brilliant purple opal"].each do |gem|
      it "recognizes #{gem} as a gem" do
        expect(GameObjFactory.item_from_name(gem).type).to include "gem"
      end
    end
  end

  describe "Zul Logoth" do
    describe "gems" do
      [
        %{ametrine gem},
        %{argent vultite-bloom},
        %{black sphene},
        %{boulder opal},
        %{bright bluerock},
        %{brown sphene},
        %{deep blue eostone},
        %{piece of azurite},
        %{piece of corestone},
        %{piece of grey chalcedony},
        %{tangerine quartz},
        %{white sphene},
        %{yellow sphene},
      ].each do |gem|
        it "recognizes #{gem} as a gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).sellable).to include "gemshop"
        end
      end

      describe "gems with data issues" do
        [
          %{silvery galena},
          %{cinnabar crystal},
        ].each do |gem|
          xit "recognizes #{gem} as a gem" do
            expect(GameObjFactory.item_from_name(gem).type).to include "gem"
            expect(GameObjFactory.item_from_name(gem).type).to_not include "magic"
            expect(GameObjFactory.item_from_name(gem).sellable).to include "gemshop"
          end
        end
      end
    end
  end

  describe "Solhaven and River's Rest" do
    describe "gems" do
      [
        %{brilliant fire pearl},
        %{deep blue mermaid's-tear sapphire},
        %{iridescent pearl},
        %{iridescent piece of mother-of-pearl},
        %{kezmonihoney beryl},
        %{piece of cat's paw coral},
        %{piece of flower coral},
        %{selanthan bloodjewel},
        %{uncut star-of-tamzyrr diamond},
      ].each do |gem|
        it "recognizes #{gem} as a gem" do
          expect(GameObjFactory.item_from_name(gem).type).to include "gem"
          expect(GameObjFactory.item_from_name(gem).sellable).to include "gemshop"
        end
      end
    end

    describe "valuables" do
      [
        %{amethyst clam shell},
        %{black helmet shell},
        %{black-spined conch shell},
        %{blue-banded coquina shell},
        %{bright noble pectin shell},
        %{candystick tellin shell},
        %{crown conch shell},
        %{crown-of-charl shell},
        %{dovesnail shell},
        %{egg cowrie shell},
        %{fluted limpet shell},
        %{king helmet shell},
        %{lavender nassa shell},
        %{lynx cowrie shell},
        %{opaque spiral shell},
        %{pink-banded coquina shell},
        %{polished green abalone shell},
        %{polished red abalone shell},
        %{polished shark tooth},
        %{purple-cap cowrie shell},
        %{red helmet shell},
        %{ruby-lined nassa shell},
        %{snake-head cowrie shell},
        %{solhaven bay scallop shell},
        %{sparkling silvery conch shell},
        %{speckled conch shell},
        %{split-back pink conch shell},
        %{tiger cowrie shell},
        %{tiger-striped nautilus shell},
        %{yellow helmet shell},
      ].each do |valuable|
        it "recognizes #{valuable} as a valuable" do
          expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "skin"
          expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
        end
      end
    end
  end

  describe "valuable things which are not gems" do
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
      %{petrified tiger tooth},
      %{petrified mammoth tusk},
    ].each do |valuable|
      it "recognizes #{valuable} as a valuable" do
        expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
        expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
        expect(GameObjFactory.item_from_name(valuable).type).to_not include "skin"
        expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
      end
    end

    describe "valuables with data issues" do
      [
        %{thin-rayed black diamond starburst},
      ].each do |valuable|
        it "recognizes #{valuable} as a valuable" do
          expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
          expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
        end

        xit "recognizes #{valuable} as sellable at the gemshop" do
          expect(GameObjFactory.item_from_name(valuable).sellable).to include "gemshop"
        end
      end

      describe "items with conflicting categories" do
        [
          %{piece of petrified maoral},
        ].each do |valuable|
          xit "recognizes #{valuable} as a valuable" do
            expect(GameObjFactory.item_from_name(valuable).type).to include "valuable"
            expect(GameObjFactory.item_from_name(valuable).type).to_not include "gem"
          end
        end
      end
    end
  end

  describe "scarabs" do
    [
      %{blood red teardrop-etched scarab},
      %{etched translucent scarab},
      %{glimmering opalescent scarab},
      %{sea-green glaes scarab},
      %{sky-blue glaes scarab},
      %{spiked onyx scarab},
    ].each do |scarab|
      it "recognizes #{scarab} as a scarab" do
        expect(GameObjFactory.item_from_name(scarab).type).to include "scarab"
        expect(GameObjFactory.item_from_name(scarab).sellable).to include "gemshop"
      end
    end
  end

  describe "plinite" do
    %w[
      blackened
      grey
      brown
      green
      orange
      red
      purple
    ].each do |color|
      plinite = "shard of #{color} plinite"

      it "recognizes a #{plinite} as a plinite" do
        expect(GameObjFactory.item_from_name(plinite).type).to include "plinite"
        expect(GameObjFactory.item_from_name(plinite).type).to include "valuable"
        expect(GameObjFactory.item_from_name(plinite).type).to_not include "gem"
      end

      xit "recognizes a #{plinite} as sellable at the gemshop" do
        expect(GameObjFactory.item_from_name(plinite).sellable).to include "gemshop"
      end
    end
  end

  describe "things that aren't gems" do
    describe "junk" do
      it "smooth stones" do
        expect(GameObjFactory.item_from_name(%{smooth stone}).type).to_not include "gem"
        expect(GameObjFactory.item_from_name(%{smooth stone}).type).to_not include "valuable"
      end
    end

    describe "skins" do
      [
        %{scaly burgee shell},
        %{faceted crystal crab shell},
      ].each do |skin|
        it "knows a #{skin} is a skin and not a gem" do
          expect(GameObjFactory.item_from_name(skin).type).to include "skin"
          expect(GameObjFactory.item_from_name(skin).type).to_not include "gem"
        end
      end
    end

    describe "soulstones" do
      [
        %{gleaming multicolored soulstone},
        %{elemental soulstone},
      ].each do |soulstone|
        it "#{soulstone} is quest items not a gem" do
          expect(GameObjFactory.item_from_name(soulstone).type).to include "quest"
          expect(GameObjFactory.item_from_name(soulstone).type).to_not include "gem"
        end
      end
    end
  end
end
