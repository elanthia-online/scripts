require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "passive NPCs" do
    describe "familiars" do
      [
        "blue wolf",
        "grey-headed hawk",
        "rock falcon",
        "sleek charcoal cat",
        "sleek red-tailed hawk",
        "speckled green frog",
        "spotted bull frog",
        "tiny black mouse",
      ].each do |familiar|
        it "recognizes #{familiar} as a passive NPC" do
          expect(GameObjFactory.npc_from_name(familiar).type).to include "passive npc"
        end
      end
    end

    describe "spirit servants" do
      [
        "acrimonious marsh spirit",
        "angry forest spirit",
        "capricious lake spirit",
        "cheerful forest spirit",
        "cunning luck spirit",
        "delighted lake spirit",
        "delusive solar spirit",
        "desolate woodland spirit",
        "disconsolate marsh spirit",
        "disgruntled luck spirit",
        "dismal mountain spirit",
        "dolorous mountain spirit",
        "downtrodden solar spirit",
        "enraged lake spirit",
        "erratic glacier spirit",
        "erratic marsh spirit",
        "erratic river spirit",
        "erratic solar spirit",
        "expressive mountain spirit",
        "fidgety luck spirit",
        "fierce marsh spirit",
        "fluctuant lake spirit",
        "friendly woodland spirit",
        "frisky forest spirit",
        "frolicsome marsh spirit",
        "gleeful woodland spirit",
        "goofy solar spirit",
        "grim mountain spirit",
        "irate luck spirit",
        "jubilant marsh spirit",
        "lively luck spirit",
        "lonely glacier spirit",
        "outgoing luck spirit",
        "perturbed luck spirit",
        "playful solar spirit",
        "puckish island spirit",
        "quirky marsh spirit",
        "quirky mountain spirit",
        "recalcitrant forest spirit",
        "reluctant solar spirit",
        "sad forest spirit",
        "somber glacier spirit",
        "somber solar spirit",
        "sprightly forest spirit",
        "sullen mountain spirit",
        "tremulous marsh spirit",
        "troublesome forest spirit",
        "unstable lake spirit",
        "upset mountain spirit",
        "vacillating marsh spirit",
        "vengeful luck spirit",
        "volatile luck spirit",
        "volatile marsh spirit",
        "wary woodland spirit",
        "whimsical luck spirit",
        "wrathful lake spirit",
        "wretched forest spirit",
        "wretched glacier spirit",
      ].each do |spirit|
        it "recognizes #{spirit} as a passive NPC" do
          expect(GameObjFactory.npc_from_name(spirit).type).to include "passive npc"
        end
      end

      it "knows that tree spirits and moaning spirits are not passive spirit servants" do
        [
          "moaning spirit",
          "tree spirit",
        ].each do |spirit|
          expect(GameObjFactory.npc_from_name(spirit).type).to_not include "passive npc"
        end
      end
    end

    describe "escorts" do
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
            dignitary
            magistrate
            merchant
            official
            scribe
            traveller
        ].each do |noun|
          escort_name = "#{race} #{noun}"
          it "recognizes #{escort_name} as a passive NPC" do
            expect(GameObjFactory.npc_from_name(escort_name).type).to include "passive npc"
          end

          it "recognizes #{escort_name} as an escort" do
            expect(GameObjFactory.npc_from_name(escort_name).type).to include "escort"
          end
        end
      end
    end

    describe "other misc passive NPCs" do
      [
        "blind ferryman",
        "city guardsman",
        "dirty rat",
        "drunken sailor",
        "dusty miner",
        "Dwarven deputy",
        "dwarven recruiter",
        "elven captain",
        "hazel-eyed dwarven priestess",
        "middle-aged human priestess",
        "overgrown snail",
        "peddler Gertie",
        "peglegged cat",
        "pelican",
        "pretty flowery hooker",
        "South Gate guard",
        "stooped old woman",
        "street urchin",
        "tunnel sweeper",
        "wizened gnome",
        "yellow canary",
        "Fleet Captain",
      ].each do |npc|
        it "recognizes #{npc} as a passive NPC" do
          expect(GameObjFactory.npc_from_name(npc).type).to include "passive npc"
        end
      end
    end
  end
end
