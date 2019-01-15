require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "skins" do
    describe "with singular base nouns" do
      [
        %{agresh bear claw},
        %{aivren gizzard},
        %{ant larva},
        %{antlers},
        %{ant pincer},
        %{arctic manticore mane},
        %{arctic titan toe},
        %{ash hag nose},
        %{basilisk crest},
        %{bat wing},
        %{bear claw},
        %{bear hide},
        %{bear paw},
        %{bighorn sheepskin},
        %{black boar hide},
        %{black leopard paw},
        %{black urgh hide},
        %{blood red eagle feather},
        %{boar tusk},
        %{bobcat claw},
        %{brown bear skin},
        %{brown boar skin},
        %{brown gak hide},
        %{brown spinner leg},
        %{caedera skin},
        %{cave nipper skin},
        %{centaur hide},
        %{centaur ranger hide},
        %{cerebralite tentacle},
        %{chimera stinger},
        %{cobra skin},
        %{cockatrice feather},
        %{cockatrice plume},
        %{cougar tail},
        %{coyote tail},
        %{cracked troll jawbone},
        %{crocodile snout},
        %{crooked crone finger},
        %{crooked witch nose},
        %{curved gold-flecked claw},
        %{cyclops eye},
        %{daggerbeak wing},
        %{decaying troll eye},
        %{direbear fang},
        %{dirge skin},
        %{dobrem snout},
        %{eagle talon},
        %{elongated triton spine},
        %{faceted crystal crab shell},
        %{faeroth fang},
        %{fenghai fur},
        %{fire ant pincer},
        %{fire cat claw},
        %{fire giant mane},
        %{fire rat tail},
        %{fog beetle carapace},
        %{frozen scalp},
        %{gak hide},
        %{gak pelt},
        %{ghoul finger},
        %{ghoul master claw},
        %{ghoul nail},
        %{ghoul scraping},
        %{giant scalp},
        %{giant skin},
        %{giant toe},
        %{glistening black eye},
        %{gnome scalp},
        %{goat hoof},
        %{goblin fang},
        %{goblin skin},
        %{golem bone},
        %{greasy troll scalp},
        %{griffin pelt},
        %{grifflet pelt},
        %{grizzly bear hide},
        %{heavy grey tusk},
        %{hisskra crest},
        %{hisskra skin},
        %{hisskra tooth},
        %{hobgoblin scalp},
        %{hobgoblin shaman ear},
        %{hornet stinger},
        %{ice hound ear},
        %{ice troll scalp},
        %{iridescent triton hide},
        %{jagged rift crawler tooth},
        %{kappa fin},
        %{kiramon mandible},
        %{kiramon tongue},
        %{kobold ear},
        %{kobold skin},
        %{krynch shinbone},
        %{leaper hide},
        %{leopard skin},
        %{lynx pelt},
        %{madrinol skin},
        %{mammoth arachnid mandible},
        %{mammoth tusk},
        %{mangy kobold scalp},
        %{manticore tail},
        %{marmot pelt},
        %{martial eagle talon},
        %{massive troll king hide},
        %{minotaur hide},
        %{minotaur hoof},
        %{minotaur horn},
        %{mist wraith eye},
        %{mongrel hobgoblin snout},
        %{monkey paw},
        %{moor hound paw},
        %{mossy beard},
        %{mottled faeroth crest},
        %{mountain lion skin},
        %{multicolored siren lizard skin},
        %{multi-faceted tomb spider eye},
        %{mummy's shroud},
        %{myklian scale},
        %{night golem finger},
        %{night hound hide},
        %{ogre nose},
        %{ogre tooth},
        %{ogre tusk},
        %{orange shelfae scale},
        %{orc beard},
        %{orc claw},
        %{orc ear},
        %{orc hide},
        %{orc knuckle},
        %{orc scalp},
        %{pair of caribou antlers},
        %{pale crab pincer},
        %{pale white feather},
        %{panther pelt},
        %{plains lion skin},
        %{polar bear skin},
        %{pulsating firethorn},
        %{puma hide},
        %{puma paw},
        %{pure white feather},
        %{pyrothag hide},
        %{raptor feathers},
        %{rat pelt},
        %{rattlesnake rattle},
        %{red eye},
        %{red orc scalp},
        %{relnak sail},
        %{rimed lich finger bone},
        %{roa'ter skin},
        %{rodent fang},
        %{rolton ear},
        %{rolton horn},
        %{rolton pelt},
        %{rotted canine},
        %{rotting rolton pelt},
        %{ruff of raptor feathers},
        %{ruff of vulture feathers},
        %{salamander skin},
        %{scaly burgee shell},
        %{scorched lich finger bone},
        %{scorpion stinger},
        %{scraggly orc scalp},
        %{scrap of troll skin},
        %{seeker eye},
        %{sheer white spider mandible},
        %{shelfae crest},
        %{shelfae scale},
        %{shimmering wasp wing},
        %{silverback orc knuckle},
        %{silver mane},
        %{silver-tipped horseshoe},
        %{silvery hoof},
        %{silvery tail},
        %{skeletal giant bone},
        %{skeletal warhorse jaw},
        %{skeleton bone},
        %{skeleton skull},
        %{snake fang},
        %{snake skin},
        %{snowcat pelt},
        %{snowy cockatrice tailfeather},
        %{spectre nail},
        %{spectre skin},
        %{spider leg},
        %{spotted gnarp horn},
        %{spotted leaper pelt},
        %{spotted leopard pelt},
        %{squirrel tail},
        %{stone-grey lizard tail},
        %{stone heart},
        %{striped relnak sail},
        %{swamp troll scalp},
        %{tawny brindlecat hide},
        %{tegursh claw},
        %{tegu tailspike},
        %{thrak hide},
        %{thrak tail},
        %{tiger incisor},
        %{trali hide},
        %{trali scalp},
        %{tree viper fang},
        %{troll beard},
        %{troll ear},
        %{troll eye},
        %{troll eyeball},
        %{troll fang},
        %{troll heart},
        %{troll hide},
        %{troll knuckle},
        %{troll scalp},
        %{troll skin},
        %{troll thumb},
        %{troll toe},
        %{troll tongue},
        %{tsark skin},
        %{tufted hawk-owl ear},
        %{tundra giant tooth},
        %{urgh hide},
        %{ursian tusk},
        %{veaba claw},
        %{velnalin hide},
        %{velnalin horn},
        %{vesperti claw},
        %{viper fang},
        %{viper skin},
        %{vor'taz horn},
        %{vruul skin},
        %{waern fur},
        %{warcat whisker},
        %{war griffin talon},
        %{warthog snout},
        %{wasp stinger},
        %{water moccasin skin},
        %{weasel pelt},
        %{werebear paw},
        %{whiptail stinger},
        %{white puma hide},
        %{wight claw},
        %{wight mane},
        %{wight scalp},
        %{wight skin},
        %{wight skull},
        %{wolverine pelt},
        %{wolverine tail},
        %{worm skin},
        %{wraith talon},
        %{yellowed boar tusk},
        %{yellowed canine},
        %{zombie scalp},
      ].each do |skin_name|
        it "recognizes single #{skin_name} as a skin" do
          skin = GameObjFactory.item_from_name(skin_name)
          expect(skin.type).to eq "skin"
          expect(skin.sellable.to_s).to eq "furrier"
        end

        pluralized_skin_name = if skin_name.end_with? "s"
                                skin_name
                              else
                                "#{skin_name}s"
                              end

        it "recognizes bundle of #{pluralized_skin_name} as a skin" do
          skin = GameObjFactory.item_from_name("bundle of #{pluralized_skin_name}")
          expect(skin.type).to include "skin"
          expect(skin.sellable.to_s).to include "furrier"
        end
      end
    end

    describe "with plural base nouns" do
      [
        %{blood-stained bark},
      ].each do |base_skin_name|
        single_skin_name = "some #{base_skin_name}"

        it "recognizes single #{single_skin_name} as a skin" do
          skin = GameObjFactory.item_from_name(single_skin_name)
          expect(skin.type).to eq "skin"
          expect(skin.sellable.to_s).to eq "furrier"
        end

        pluralized_skin_name = if base_skin_name.end_with? "s"
                                base_skin_name
                              else
                                "#{base_skin_name}s"
                              end

        it "recognizes bundle of #{pluralized_skin_name} as a skin" do
          skin = GameObjFactory.item_from_name("bundle of #{pluralized_skin_name}")
          expect(skin.type).to include "skin"
          expect(skin.sellable.to_s).to include "furrier"
        end
      end
    end

    describe "great stag antlers" do
      [
        %{pair of spike antlers},
        %{pair of forked antlers},
        %{pair of three-tined antlers},
        %{rack of four-tined antlers},
        %{rack of five-tined antlers},
        %{wide rack of six-tined antlers},
      ].each do |skin_name|
        it "recognizes #{skin_name} as a skin" do
          skin = GameObjFactory.item_from_name(skin_name)
          expect(skin.type).to include "skin"
        end
      end
    end

    describe "skins with data issues" do
      xit "recognizes fungal cap from shimmering fungus as a skin" do
        skin = GameObjFactory.item_from_name(%{fungal cap})
        expect(skin.type).to include "skin"
        expect(skin.type).to_not include "clothing"
      end

      describe "Frozen Bramble skins" do
        [
          %{blood-stained leaf},
          %{desiccated stem},
          %{thorn-ridden appendage},
        ].each do |skin_name|
          xit "recognizes #{skin_name} as a skin" do
            skin = GameObjFactory.item_from_name(skin_name)
            expect(skin.type).to include "skin"
            expect(skin.sellable.to_s).to include "furrier"
          end
        end

        [
          %{bleached thorn},
          %{frosted branch},
          %{shriveled cutting},
        ].each do |skin_name|
          it "recognizes #{skin_name} as a skin" do
            skin = GameObjFactory.item_from_name(skin_name)
            expect(skin.type).to include "skin"
          end

          xit "recognizes #{skin_name} as sellable at the furrier" do
            skin = GameObjFactory.item_from_name(skin_name)
            expect(skin.sellable.to_s).to include "furrier"
          end
        end
      end
    end
  end

  describe "things that aren't skins" do
    describe "that are sellable at the furrier" do
      [
        %{scintillating fishscale},
        %{lump of black ambergris},
        %{lump of grey ambergris},
      ].each do |sellable_name|
        it "recognizes #{sellable_name} is NOT a skin" do
          item = GameObjFactory.item_from_name(sellable_name)
          expect(item.type).to be_nil
        end

        it "recognizes #{sellable_name} as sellable at the furrier" do
          item = GameObjFactory.item_from_name(sellable_name)
          expect(item.sellable.to_s).to include "furrier"
        end
      end
    end

    describe "horns that aren't skins" do
      [
        %{carved rowan horn banded with silvery mithril},
        %{drinking horn},
      ].each do |horn_name|
        it "recognizes #{horn_name} is NOT a skin" do
          horn = GameObjFactory.item_from_name(horn_name)
          expect(horn.type.to_s).to_not include "skin"
          # TODO: sellable category?
        end
      end
    end
  end
end
