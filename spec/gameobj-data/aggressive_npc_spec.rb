require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "aggressive NPCs" do
    describe "grimswarm" do
      [
        "", # no prefix
        "battle-scarred ",
        "grizzled ",
        "haggard ",
        "hulking ",
        "seasoned ",
        "veteran ",
        "weathered ",
      ].each do |prename|
        %w[giant troll orc].each do |race|
          %w[
            acolyte
            adept
            archer
            barbarian
            battlemage
            champion
            cleric
            crusader
            destroyer
            dissembler
            elementalist
            empath
            fighter
            guard
            healer
            hunter
            huntmaster
            huntmistress
            initiate
            mage
            marauder
            paladin
            pillager
            raider
            ranger
            scourge
            scout
            shaman
            skirmisher
            sniper
            soldier
            sorcerer
            sorceress
            spellbinder
            warchief
            warlock
            warmage
            warmonger
            warrior
            witch
            wizard
            wrathbringer
            zealot
          ].each do |profession|
            grimswarm = "#{prename}Grimswarm #{race} #{profession}"

            it "recognizes #{grimswarm} as an aggressive NPC" do
              expect(GameObjFactory.npc_from_name(grimswarm).type).to include "aggressive npc"
            end

            it "recognizes #{grimswarm} as a grimswarm" do
              expect(GameObjFactory.npc_from_name(grimswarm).type).to include "grimswarm"
            end
          end
        end
      end
    end

    describe "bandit" do
      [
        "", # no prefix
        "seasoned ",
      ].each do |prename|
        %w[
          dwarven
          elven
          erithian
          giantman
          gnomish
          half-elven
          half-krolvin
          halfling
          human
        ].each do |race|
          %w[
            bandit
            brigand
            highwayman
            marauder
            mugger
            outlaw
            robber
            rogue
            thief
            thug
          ].each do |profession|
            bandit = "#{prename}#{race} #{profession}"

            it "recognizes #{bandit} as an aggressive NPC" do
              expect(GameObjFactory.npc_from_name(bandit).type).to include "aggressive npc"
            end

            it "recognizes #{bandit} as a bandit" do
              expect(GameObjFactory.npc_from_name(bandit).type).to include "bandit"
            end
          end
        end
      end
    end

    describe "undead" do
      [
        "ancient ghoul master",
        "arch wight",
        "baesrukha",
        "banshee",
        "barghest",
        "blackened decaying tumbleweed",
        "bog wight",
        "bog wraith",
        "bone golem",
        "carceris",
        "crazed zombie",
        "dark apparition",
        "dark frosty plant",
        "darkwoode",
        "death dirge",
        "decaying Citadel guardsman",
        "dybbuk",
        "eidolon",
        "elder ghoul master",
        "elder tree spirit",
        "ethereal mage apprentice",
        "ethereal triton sentry",
        "firephantom",
        "flesh golem",
        "frostborne lich",
        "frozen corpse",
        "gaunt spectral servant",
        "ghost",
        "ghostly mara",
        "ghostly pooka",
        "ghostly warrior",
        "ghost wolf",
        "ghoul master",
        "greater ghoul",
        "greater moor wight",
        "greater vruul",
        "ice skeleton",
        "ice wraith",
        "infernal lich",
        "large thorned shrub",
        "lesser frost shade",
        "lesser ghoul",
        "lesser moor wight",
        "lesser mummy",
        "lesser shade",
        "lesser vruul",
        "lich qyn'arj",
        "lost soul",
        "mist wraith",
        "moaning phantom",
        "moaning spirit",
        "monastic lich",
        "murky soul siphon",
        "naisirc",
        "n'ecare",
        "necrotic snake",
        "nedum vereri",
        "night mare",
        "nightmare steed",
        "nonomino",
        "phantasma",
        "phantasmal bestial swordsman",
        "phantom",
        "putrefied Citadel herald",
        "revenant",
        "rock troll zombie",
        "rotting chimera",
        "rotting Citadel arbalester",
        "rotting corpse",
        "rotting farmhand",
        "rotting krolvin pirate",
        "rotting woodsman",
        "seeker",
        "seraceris",
        "shadow mare",
        "shadow steed",
        "shadowy spectre",
        "shrickhen",
        "shriveled icy creeper",
        "skeletal giant",
        "skeletal ice troll",
        "skeletal lord",
        "skeletal soldier",
        "skeletal warhorse",
        "skeleton",
        "snow spectre",
        "soul golem",
        "spectral fisherman",
        "spectral lord",
        "spectral miner",
        "spectral monk",
        "spectral shade",
        "spectral triton defender",
        "spectral warrior",
        "spectral woodsman",
        "spectre",
        "tomb wight",
        "tree spirit",
        "troll wraith",
        "vaespilon",
        "vourkha",
        "waern",
        "warrior shade",
        "werebear",
        "wind wraith",
        "wolfshade",
        "wood wight",
        "wraith",
        "writhing frost-glazed vine",
        "writhing icy bush",
        "zombie",
        "zombie rolton",
      ].each do |undead|
        it "recognizes #{undead} as an undead aggressive NPC" do
          expect(GameObjFactory.npc_from_name(undead).type).to include "aggressive npc"
          expect(GameObjFactory.npc_from_name(undead).type).to include "undead"
        end
      end

      describe "REIM" do
        [
          %{ethereal barbarian},
          %{ethereal commoner},
          %{ethereal denizen},
          %{ethereal guard},
          %{ethereal guardsman},
          %{ethereal guardswoman},
          %{ethereal inmate},
          %{ethereal knight},
          %{ethereal lunatic},
          %{ethereal madman},
          %{ethereal madwoman},
          %{ethereal peasant},
          %{ethereal pillager},
          %{ethereal prisoner},
          %{ethereal raider},
          %{ethereal scout},
          %{ethereal soldier},
          %{ethereal squire},
          %{ethereal swordsman},
          %{ethereal swordswoman},
          %{ethereal townsman},
          %{ethereal townswoman},
          %{ethereal traveller},
          %{ethereal villager},
          %{ethereal waylayer},
          %{ethereal zealot},

          %{ghostly bandit},
          %{ghostly highwayman},
          %{ghostly highwaywoman},
          %{ghostly marauder},
          %{ghostly waylayer},

          %{unworldly barbarian},
          %{unworldly guest},
          %{unworldly knight},
          %{unworldly maid},
          %{unworldly noble},
          %{unworldly pillager},
          %{unworldly raider},
          %{unworldly royal guard},
          %{unworldly royal knight},
          %{unworldly scout},
          %{unworldly servant},
          %{unworldly slave},
          %{unworldly soldier},
          %{unworldly steward},
          %{unworldly visitor},
          %{unworldly waylayer},
          %{unworldly zealot},

          %{celestial dancer},
          %{celestial juggler},
          %{celestial nomad},
          %{celestial traveller},

          %{Shopkeeper},
          %{Innkeeper},
          %{Bartender},
          %{Patrol Leader},
          %{Bandit Lord},
          %{Bandit Lady},
          %{Gypsy Queen},
          %{Gypsy King},
          %{Guard Captain},
          %{Wall Captain},
          %{Drill Sergeant},
          %{Stable Hostler},
          %{Dungeon Master},
          %{Master Torturer},
          %{Butler},
          %{Cook},
          %{Knight Captain},
          %{Foreign Dignitary},
          %{Royal Prince},
          %{Royal Princess},
          %{Royal Jester},
          %{Royal Emperor},
          %{Royal Empress},

          %{speedy sapper},

          %{Sapper Lord},
          %{Sapper Lady},
          %{Raid Leader},
          %{Dark Knight},
          %{Massive Butcher},
          %{Slender Mercenary},
          %{Darkly Hooded Figure},
          %{Crimson Count},
          %{Kennel Master},
          %{Royal Inquisitor},
          %{Towering Crusader},
          %{Hulking Berserker},
          %{Jester Ser Rets},
          %{Dame Venti},
          %{Corrupted Knight Owrym},
          %{Arch Priest Dlitse},
          %{Dame Elle Zo},
          %{Thane Wedge},
          %{Dark Astrologer Scionae},
        ].each do |undead|
          it "recognizes #{undead} as an aggressive REIM undead npc" do
            expect(GameObjFactory.npc_from_name(undead).type).to include "aggressive npc"
            expect(GameObjFactory.npc_from_name(undead).type).to_not include "passive npc"
            expect(GameObjFactory.npc_from_name(undead).type).to include "undead"
            expect(GameObjFactory.npc_from_name(undead).type).to include "realm:reim"
          end
        end
      end
    end

    describe "living" do
      [
        "Agresh bear",
        "Agresh troll chieftain",
        "Agresh troll scout",
        "Agresh troll warrior",
        "aivren",
        "albino tomb spider",
        "animated slush",
        "Arachne acolyte",
        "Arachne priest",
        "Arachne priestess",
        "Arachne servant",
        "arctic manticore",
        "arctic puma",
        "arctic titan",
        "arctic wolverine",
        "ash hag",
        "banded rattlesnake",
        "bay centaur",
        "bighorn sheep",
        "big ugly kobold",
        "black bear",
        "black boar",
        "black forest ogre",
        "black forest viper",
        "black leopard",
        "black panther",
        "black rolton",
        "black urgh",
        "black-winged daggerbeak",
        "blood eagle",
        "blue myklian",
        "bobcat",
        "bog spectre",
        "bog troll",
        "Bresnahanini rolton",
        "brown boar",
        "brown gak",
        "brown spinner",
        "burly reiver",
        "caedera",
        "caribou",
        "carrion worm",
        "cave bear",
        "cave gnoll",
        "cave gnome",
        "cave lizard",
        "cave nipper",
        "cave troll",
        "cave worm",
        "centaur",
        "cinder wasp",
        "cobra",
        "cockatrice",
        "cold guardian",
        "colossus vulture",
        "cougar",
        "coyote",
        "crested basilisk",
        "crocodile",
        "crystal crab",
        "crystal golem",
        "csetairi",
        "cyclops",
        "darken",
        "darkly inked fetish master",
        "dark orc",
        "dark panther",
        "dark shambler",
        "dark vortece",
        "dark vysan",
        "deranged sentry",
        "dhu goleras",
        "dobrem",
        "dreadnought raptor",
        "dust beetle",
        "earth elemental",
        "emaciated hierophant",
        "enormous rift crawler",
        "fanged goblin",
        "fanged rodent",
        "fanged viper",
        "farlook",
        "fenghai",
        "festering taint",
        "fire ant",
        "fire cat",
        "fire elemental",
        "fire giant",
        "fire guardian",
        "fire mage",
        "fire ogre",
        "fire rat",
        "fire salamander",
        "fire sprite",
        "firethorn shoot",
        "forest ogre",
        "forest trali",
        "forest trali shaman",
        "forest troll",
        "frost giant",
        "giant albino scorpion",
        "giant albino tomb spider",
        "giant ant",
        "giant fog beetle",
        "giant hawk-owl",
        "giant marmot",
        "giant rat",
        "giant veaba",
        "giant weasel",
        "glacial morph",
        "glistening cerebralite",
        "gnarled being",
        "gnoll guard",
        "gnoll jarl",
        "gnoll priest",
        "gnoll ranger",
        "gnoll thief",
        "gnoll worker",
        "goblin",
        "great boar",
        "great brown bear",
        "greater bog troll",
        "greater burrow orc",
        "greater construct",
        "greater earth elemental",
        "greater faeroth",
        "greater ice giant",
        "greater ice spider",
        "greater kappa",
        "greater krynch",
        "greater orc",
        "greater spider",
        "greater water elemental",
        "great stag",
        "green myklian",
        "greenwing hornet",
        "gremlock",
        "grey orc",
        "grifflet",
        "grizzly bear",
        "Grutik savage",
        "Grutik shaman",
        "hill troll",
        "hisskra chieftain",
        "hisskra shaman",
        "hisskra warrior",
        "hobgoblin",
        "hobgoblin shaman",
        "hooded figure",
        "horned vor'taz",
        "huge mein golem",
        "humpbacked puma",
        "hunch-backed dogmatist",
        "hunter troll",
        "ice elemental",
        "ice golem",
        "ice hound",
        "ice troll",
        "Illoke elder",
        "Illoke jarl",
        "Illoke mystic",
        "Illoke shaman",
        "Ithzir adept",
        "Ithzir champion",
        "Ithzir herald",
        "Ithzir initiate",
        "Ithzir janissary",
        "Ithzir scout",
        "Ithzir seer",
        "jungle troll",
        "jungle troll chieftain",
        "ki-lin",
        "kiramon defender",
        "kiramon worker",
        "kobold",
        "kobold shepherd",
        "krag dweller",
        "krag yeti",
        "krolvin corsair",
        "krolvin mercenary",
        "krolvin slaver",
        "krolvin warfarer",
        "krolvin warrior",
        "large ogre",
        "lava golem",
        "lava troll",
        "leaper",
        "lesser burrow orc",
        "lesser construct",
        "lesser faeroth",
        "lesser griffin",
        "lesser ice elemental",
        "lesser ice giant",
        "lesser minotaur",
        "lesser orc",
        "lesser red orc",
        "lesser stone gargoyle",
        "luminous arachnid",
        "magru",
        "major glacei",
        "major spider",
        "mammoth arachnid",
        "manticore",
        "massive black boar",
        "massive grahnk",
        "massive pyrothag",
        "massive troll king",
        "mastodonic leopard",
        "maw spore",
        "mezic",
        "minor glacei",
        "minotaur magus",
        "minotaur warrior",
        "Mistydeep siren",
        "mongrel hobgoblin",
        "mongrel kobold",
        "mongrel troll",
        "mongrel wolfhound",
        "monkey",
        "moor eagle",
        "moor hound",
        "moor witch",
        "mottled thrak",
        "moulis",
        "mountain goat",
        "mountain lion",
        "mountain ogre",
        "mountain rolton",
        "mountain snowcat",
        "mountain troll",
        "mud wasp",
        "muscular supplicant",
        "Neartofar orc",
        "Neartofar troll",
        "night golem",
        "ogre warrior",
        "orange myklian",
        "pale crab",
        "panther",
        "phosphorescent worm",
        "plains lion",
        "plains ogre",
        "plains orc chieftain",
        "plains orc scout",
        "plains orc shaman",
        "plains orc warrior",
        "plumed cockatrice",
        "polar bear",
        "pra'eda",
        "puma",
        "purple myklian",
        "rabid guard dog",
        "rabid squirrel",
        "raider orc",
        "raving lunatic",
        "red bear",
        "red myklian",
        "red-scaled thrak",
        "red tsark",
        "reiver",
        "relnak",
        "ridgeback boar",
        "ridge orc",
        "roa'ter",
        "roa'ter wormling",
        "rolton",
        "sabre-tooth tiger",
        "sand beetle",
        "sand devil",
        "scaly burgee",
        "sea nymph",
        "shan cleric",
        "shan ranger",
        "shan warrior",
        "shan wizard",
        "shelfae chieftain",
        "shelfae soldier",
        "shelfae warlord",
        "Sheruvian harbinger",
        "Sheruvian initiate",
        "Sheruvian monk",
        "shimmering fungus",
        "silverback orc",
        "siren",
        "siren lizard",
        "skayl",
        "slimy little grub",
        "snow crone",
        "snow leopard",
        "snow madrinol",
        "snowy cockatrice",
        "spiked cavern urchin",
        "spotted gak",
        "spotted gnarp",
        "spotted leaper",
        "spotted lynx",
        "spotted velnalin",
        "steel golem",
        "stone gargoyle",
        "stone giant",
        "stone mastiff",
        "stone sentinel",
        "stone troll",
        "storm giant",
        "storm griffin",
        "striped gak",
        "striped relnak",
        "striped warcat",
        "swamp hag",
        "swamp troll",
        "tawny brindlecat",
        "thrak",
        "three-toed tegu",
        "thunder troll",
        "thyril",
        "tomb troll",
        "tomb troll necromancer",
        "tree viper",
        "triton combatant",
        "triton dissembler",
        "triton executioner",
        "triton magus",
        "triton radical",
        "troglodyte",
        "troll chieftain",
        "tundra giant",
        "tusked ursian",
        "undertaker bat",
        "urgh",
        "velnalin",
        "vesperti",
        "veteran reiver",
        "Vvrael destroyer",
        "Vvrael warlock",
        "Vvrael witch",
        "wall guardian",
        "war griffin",
        "warthog",
        "war troll",
        "wasp nest",
        "water elemental",
        "water moccasin",
        "water witch",
        "water wyrd",
        "whiptail",
        "white vysan",
        "wild dog",
        "wild hound",
        "wind witch",
        "wolverine",
        "wood sprite",
        "wooly mammoth",
        "yellow myklian",
        "yeti",
        "young grass snake",
        "young myklian",
      ].each do |creature|
        it "recognizes #{creature} as an aggressive NPC" do
          expect(GameObjFactory.npc_from_name(creature).type).to include "aggressive npc"
          expect(GameObjFactory.npc_from_name(creature).type).to_not include "undead"
        end
      end
    end

    describe "Sanctums of Scales NPCs" do
      describe "living" do
        [
          %[lithe veiled sentinel],
          %[pale scaled shaper],
          %[deathsworn fanatic],
          %[white sidewinder],
        ].each do |creature|
          it "recognizes #{creature} as an aggressive NPC" do
            expect(GameObjFactory.npc_from_name(creature).type).to include "aggressive npc"
            expect(GameObjFactory.npc_from_name(creature).type).to_not include "undead"
          end
        end
      end

      describe "undead" do
        [
          %[shambling lurk],
          %[patchwork flesh monstrosity],
        ].each do |undead|
          it "recognizes #{undead} as an undead aggressive NPC" do
            expect(GameObjFactory.npc_from_name(undead).type).to include "aggressive npc"
            expect(GameObjFactory.npc_from_name(undead).type).to include "undead"
          end
        end
      end
    end
  end
end
