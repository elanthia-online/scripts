require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "clothing" do
    describe "randomized treasure system drop nouns" do
      describe "clothing sellable at the pawnshop" do
        [
          %{backpack},
          %{bag},
          %{bandana},
          %{belt},
          %{blouse},
          %{bodice},
          %{bonnet},
          %{boots},
          %{bow},
          %{breeches},
          %{cap},
          %{cape},
          %{chemise},
          %{cloak},
          %{coat},
          %{dress},
          %{frock},
          %{gloves},
          %{gown},
          %{greatcloak},
          %{harness},
          %{hat},
          %{hood},
          %{jacket},
          %{kerchief},
          %{kilt},
          %{kirtle},
          %{knapsack},
          %{leggings},
          %{longcloak},
          %{longcoat},
          %{mantle},
          %{overcoat},
          %{pack},
          %{pants},
          %{pouch},
          %{purse},
          %{quiver},
          %{ribbon},
          %{robe},
          %{robes},
          %{sack},
          %{sandals},
          %{sash},
          %{satchel},
          %{scabbard},
          %{scarf},
          %{shawl},
          %{sheath},
          %{shirt},
          %{shoes},
          %{skirt},
          %{slippers},
          %{snood},
          %{socks},
          %{surcoat},
          %{tabard},
          %{trousers},
          %{tunic},
          %{vest},
        ].each do |clothing_name|
          it "recognizes #{clothing_name} as clothing" do
            clothing = GameObjFactory.item_from_name(clothing_name)
            expect(clothing.type).to include "clothing"
            expect(clothing.sellable.to_s).to eq "pawnshop"
          end
        end
      end

      describe "clothing sellable at the gem shop and the pawn shop" do
        [
          %{armband},

          %{fine ecru armband},
          %{stained teal armband},
          %{stone grey armband},
        ].each do |clothing_name|
          it "recognizes #{clothing_name} as clothing" do
            clothing = GameObjFactory.item_from_name(clothing_name)
            expect(clothing.type).to include "clothing"
            expect(clothing.sellable.split(",")).to contain_exactly("gemshop", "pawnshop")
          end
        end
      end
    end

    describe "clothing not usually found in randomized treasure" do
      [
        [%{ankle-boots},   %{pair of white suede ankle-boots}],
        [%{ankle-sheath},  %{plain black leather ankle-sheath},                 %{with tiny brass buckles}],
        [%{apotla},        %{rustic cocoa suede apotla},                        %{adorned with tawny owl feathers}],
        [%{apotl},         %{sleek black feathered apotl}],
        [%{apron},         %{colorful twine-stitched apron},                    %{of patchwork fabric}],
        [%{arm-wraps},     %{set of layered brown leather arm-wraps}],
        [%{ataniki},       %{twilight blue damask ataniki},                     %{lined with moonlight silver velvet}],
        [%{atiki},         %{deep green silk atiki}],
        [%{back-scabbard}, %{boiled dark red leather back-scabbard},            %{trimmed with polished brass}],
        [%{baldric},       %{sturdy vruul skin baldric},                        %{set with a vaalin toggle}],
        [%{bandolier},     %{pale blue leather bandolier},                      %{trimmed with faenor thread}],
        [%{belts},         %{trio of coraesine belts}],
        [%{beret},         %{gold whip-stitched scarlet satin beret}],
        [%{biretta},       %{argent and ivory silk biretta}],
        [%{bliaut},        %{silver-shot white samite bliaut}],
        [%{bowtie},        %{smoky plum brocade bowtie}],
        [%{breechcloth},   %{long golden silk breechcloth},                     %{reinforced with a thick muslin lining}],
        [%{buckskins},     %{pair of dun buckskins},                            %{with a patch on one knee}],
        [%{burnoose},      %{heavy yierka-hide burnoose}],
        [%{caban},         %{silver-worked dark green caban},                   %{with buttoned sleeves}],
        [%{calf-boots},    %{some soft black suede calf-boots}],
        [%{capelet},       %{white-feathered capelet},                          %{with a curvilinear asp fetish pin}],
        [%{carryall},      %{patchwork snakeskin carryall},                     %{with a corded sinew drawstring}],
        [%{chaperon},      %{storm grey velvet chaperon},                       %{with pewter-hued embroidery}],
        [%{chasuble},      %{flowing taupe chasuble},                           %{with a gilt-embroidered cowl collar}],
        [%{chopines},      %{pair of rigid bronzed raw silk chopines}],
        [%{cincher},       %{mottled black viper skin cincher}],
        [%{cope},          %{long niveous moire cope},                          %{edged in sapphire-hued embroidery}],
        [%{corset},        %{onyx-traced pewter flyrsilk corset}],
        [%{cotehardie},    %{short and fitted dark cerulean cotehardie}],
        [%{cravat},        %{perforated ivory leather cravat}],
        [%{dolman},        %{emerald silk dolman},                              %{with layered floor-length sleeves}],
        [%{eyepatch},      %{skull-stamped black leather eyepatch}],
        [%{face-veil},     %{crimson silk face-veil}],
        [%{gauntlet},      %{leather-lined steel plate gauntlet}],
        [%{greatcoat},     %{bronze-traced henna leather greatcoat},            %{with narrow lapels}],
        [%{greatkilt},     %{green and claret wool greatkilt},                  %{pinned with a copper lion}],
        [%{guard},         %{sturdy brown leather wrist guard},                 %{etched with a dragonfly}],
        [%{habit},         %{coarse brown wool habit}],
        [%{hair-wrap},     %{tightly wound black cotton hair-wrap}],
        [%{half-bodice},   %{pale linen half-bodice},                           %{with viridian knotwork embroidery}],
        [%{half-boots},    %{pair of cuffed charcoal leather half-boots}],
        [%{half-cape},     %{hooded pale apricot half-cape}],
        [%{half-cloak},    %{umber gauze half-cloak}],
        [%{half-gloves},   %{some onyx-clawed dark leather half-gloves}],
        [%{half-mask},     %{shadowy grey suede half-mask}],
        [%{handwarmer},    %{flora-burnt dark emerald velvet handwarmer}],
        [%{headdress},     %{headdress},                                        %{of emerald and ruby tailfeathers}],
        [%{headscarf},     %{silver-dagged royal blue headscarf}],
        [%{headwrap},      %{bright red cotton headwrap}],
        [%{henin},         %{pale gossamer-veiled henin}],
        [%{hip-basket},    %{braided sweetgrass hip-basket}],
        [%{hip-belt},      %{sapphire and silver hip-belt}],
        [%{hip-jacket},    %{brushed ebon suede hip-jacket},                    %{with mithglin buttons}],
        [%{hip-pouch},     %{oversized black leather hip-pouch}],
        [%{hip-quiver},    %{silver silk-lined brown leather hip-quiver}],
        [%{hip-satchel},   %{sturdy sorrel leather hip-satchel}],
        [%{hip-scarf},     %{triangular turquoise silk hip-scarf},              %{edged with bronze bells}],
        [%{hosen},          %{some golden hosen},                               %{of satin silk}],
        [%{hose},          %{pair of sheer argent hose}],
        [%{houppelande},   %{dark mahogany cotton houppelande},                 %{with fawn pinstripes}],
        [%{isiqiri},       %{dark bronze silk isiqiri}],
        [%{kanjiqi},       %{shadowed green silk kanjiqi}],
        [%{kanjir},        %{some russet silk kanjir},                          %{with a shell-carved dream agate accent}],
        [%{kit},           %{bloodstained leather survival kit}],
        [%{knee-boots},    %{some hunter green suede knee-boots}],
        [%{knee-breeches}, %{pair of fitted black leather knee-breeches}],
        [%{leg-wraps},     %{pair of raw linen leg-wraps},                      %{secured with leather cords}],
        [%{loincloth},     %{dark leather loincloth},                           %{with an elongated front panel}],
        [%{manteau},       %{fawn wool manteau},                                %{with a gossamer lace costume hood}],
        [%{mantilla},      %{ebon-lined viridian silk mantilla}],
        [%{mask},          %{weeping clown mask}],
        [%{mittens},       %{some luxurious mink fur mittens}],
        [%{mitter},        %{conical golden silk mitter}],
        [%{moccasins},     %{pair of vine-laced soft black deerskin moccasins}],
        [%{muff},          %{richly hued muff},                                 %{of plush firecat pelts}],
        [%{nanjir},        %{some elegant dark brown silk nanjir}],
        [%{neck-kerchief}, %{red-trimmed black suede neck-kerchief},            %{strung with rubies}],
        [%{neckpouch},     %{diminutive brocade neckpouch},                     %{cinched with a leather thong}],
        [%{nightdress},    %{bright red flannel nightdress}],
        [%{nightgown},     %{lavender flannel nightgown}],
        [%{nightshirt},    %{roomy plaid flannel nightshirt}],
        [%{overdress},     %{inky black satin overdress},                       %{beaded with dark jewel droplets}],
        [%{overgown},      %{ivory silk overgown},                              %{worked with obsidian blossoms}],
        [%{over-robe},     %{sleeveless bright scarlet over-robe},              %{beaded with gold agates}],
        [%{overskirt},     %{translucent silver overskirt},                     %{with contrasting onyx hems}],
        [%{pantaloons},    %{some billowy black linen pantaloons}],
        [%{pelisse},       %{raven-colored pelisse},                            %{shifting with hints of intense lapis}],
        [%{pelisson},      %{layered powder blue pelisson},                     %{lined with white fur}],
        [%{petticoat},     %{grey silk scallop-hemmed petticoat}],
        [%{reticule},      %{lace-covered dim black linen reticule}],
        [%{rucksack},      %{battered leather rucksack}],
        [%{ruff},          %{tall ebon organza ruff},                           %{adorned with metallic copper pleating}],
        [%{saephua},       %{royal violet velvet saephua},                      %{speckled with silver stars}],
        [%{sark},          %{cream-colored linen sark}],
        [%{scarves},       %{pair of pale sea blue scarves}],
        [%{shoulder-wrap}, %{fluffy red macaw feather shoulder-wrap}],
        [%{skirts},        %{some layered cotton and silk skirts}],
        [%{skullcap},      %{faded leather skullcap}],
        [%{sporran},        %{elegant black scaled sporran}],
        [%{stockings},     %{pair of pure white stockings}],
        [%{stole},         %{plush ribbed blue-grey chinchilla stole}],
        [%{stomacher},     %{side-buttoned crimson leather stomacher},          %{overlaying a gown of ruched saffron silk}],
        [%{sundress},      %{iris-hued sendal sundress},                        %{edged with a spray of pearls}],
        [%{surcote},       %{rich cranberry gauze surcote},                     %{belted with copper leaves}],
        [%{surplice},      %{henna-hued marbrinus surplice},                    %{edged in bronze threading}],
        [%{sweater},       %{ivory cable knit sweater},                         %{crafted from heavy wool}],
        [%{sword-belt},    %{twice wrapped sharkskin sword-belt}],
        [%{thigh-boots},   %{some thin-soled dark leather thigh-boots}],
        [%{thigh-quiver},  %{feather-tied dark leather thigh-quiver}],
        [%{thigh-sheath},  %{tooled vruul-skin thigh-sheath}],
        [%{tote},          %{gold-threaded brocade tote},                       %{with a sturdy cord drawstring}],
        [%{trews},         %{some high-waisted pomegranate leather trews}],
        [%{tricorn},       %{silk-lined dark lapis suede tricorn},              %{set with silver studs}],
        [%{turban},        %{loosely-wrapped veiled turban}],
        [%{undergown},     %{full-length satin undergown},                      %{boasting a deep rose hue}],
        [%{underrobe},     %{loose midnight black underrobe},                   %{with heavily ruched sleeves}],
        [%{vatanura},      %{gold and jade green silk vatanura}],
        [%{veil},          %{lace-edged white silk veil}],
        [%{vestment},      %{hooded crimson satin vestment},                    %{trimmed in gold threading}],
        [%{waist-cincher}, %{silver-boned malachite suede waist-cincher}],
        [%{waistcoat},     %{ivory cambric waistcoat},                          %{fettered by birch toggles}],
        [%{waist-sash},    %{wide goat-hide waist-sash}],
        [%{wrap-skirt},    %{sheer blued spidersilk wrap-skirt},                %{with a fel-beaded hem}],
        [%{wrap},          %{stunning fox fur wrap},                            %{with gold nugget toggles}],
        [%{wrist-purse},   %{sunflower-clasped silken wrist-purse}],
        [%{wrist-sheath},  %{gold-stitched green suede wrist-sheath}],
        [%{yatane},        %{some distressed leather yatane}],
      ].each do |(noun, name, after_name)|
        full_clothing_name = "#{noun} (#{[name, after_name].compact.join(" ")})"

        it "recognizes #{full_clothing_name} as clothing" do
          clothing = GameObjFactory.item_from_name(name, noun, after_name)
          expect(clothing.type).to include "clothing"
        end

        it "recognizes #{full_clothing_name} is NOT sellable at the pawnshop" do
          clothing = GameObjFactory.item_from_name(name, noun, after_name)
          expect(clothing.sellable.to_s).to_not include "pawnshop"
        end
      end
    end

    describe "clothing exclusions" do
      describe "sellable" do
        [
          %{composite bow},
          %{short bow},
          %{long bow},
        ].each do |item_name|
          it "recognizes #{item_name} is NOT clothing" do
            item = GameObjFactory.item_from_name(item_name)
            expect(item.type.to_s).to_not include "clothing"
          end
        end
      end

      describe "non-sellable" do
        [
          %{elemental bow},
          %{elemental bow of acid},
          %{elemental bow of lightning},
          %{elemental bow of fire},
          %{elemental bow of ice},
          %{elemental bow of vibration},

          %{bone vest},
          %{dirty brown robes},
          %{leather sandals},
          %{leather skull cap},
          %{some flowing robes},
          %{some heavy leather boots},
          %{some leather boots},
          %{some leather sandals},
          %{some tattered white robes},
          %{tattered plaid flannel shirt},
          %{weathered plaid flannel cap},
          %{woven cloak},

          %{Adventurer's Guild voucher pack},
          %{Elanthian Guilds voucher pack},
        ].each do |item_name|
          it "recognizes #{item_name} is NOT clothing" do
            item = GameObjFactory.item_from_name(item_name)
            expect(item.type.to_s).to_not include "clothing"
            expect(item.sellable.to_s).to_not include "pawnshop"
          end
        end
      end
    end
  end
end

