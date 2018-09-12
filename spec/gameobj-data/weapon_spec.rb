require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "weapons" do
    describe "one-handed edged" do
      [
        %{backsword},
        %{broadsword},
        %{broad axe},
        %{cleaver},
        %{dagger},
        %{estoc},
        %{epee},
        %{falchion},
        %{handaxe},
        %{kaskara},
        %{khopesh},
        %{kris},
        %{langsax},
        %{limb-cleaver},
        %{longsword},
        %{machete},
        %{main gauche},
        %{moon axe},
        %{rapier},
        %{sabre},
        %{sapara},
        %{scimitar},
        %{short sword},
        %{scramasax},
        %{wakizashi},
        %{waraxe},
        %{warblade},
        %{whip-blade},

        %{mithglin miner's axe},
        %{drakar field-axe},
        %{bronze-tipped drakar foil},
        %{gold-tipped gornar half-moon},
        %{ora hatchet},
        %{bone-hilted mithril butcher knife},
        %{archaic faenor poignard},
        %{chipped feras shamshir},
        %{faenor-edged vultite riding sword},
        %{burgundy mithglin waraxe},
        %{scorched gornar warblade},
        %{ancient faenor yataghan},
      ].each do |weapon_name|
        it "recognizes #{weapon_name} as weapon" do
          weapon = GameObjFactory.item_from_name(weapon_name)
          expect(weapon.type).to include "weapon"
          expect(weapon.sellable).to eq "pawnshop"
        end
      end
    end

    describe "one-handed blunt" do
      [
        %{ball & chain},
        %{ball and chain},
        %{club},
        %{crowbill},
        %{cudgel},
        %{holy water sprinkler},
        %{mace},
        %{morning star},
        %{spikestar},
        %{war hammer},
        %{whip},

        %{a quad-flanged faenor bulawa},
      ].each do |weapon_name|
        it "recognizes #{weapon_name} as weapon" do
          weapon = GameObjFactory.item_from_name(weapon_name)
          expect(weapon.type).to include "weapon"
          expect(weapon.sellable).to eq "pawnshop"
        end
      end
    end

    describe "two-handed" do
      [
        %{adze},
        %{battle axe},
        %{battlesword},
        %{bastard sword},
        %{claidhmore},
        %{espadon},
        %{flail},
        %{flamberge},
        %{great axe},
        %{greatsword},
        %{military fork},
        %{military pick},
        %{katana},
        %{maul},
        %{quarter staff},
        %{quarterstaff},
        %{short-staff},
        %{twohanded sword},
        %{war mattock},

        %{bearded axe},
        %{teak-hafted gornar scaling fork},
        %{cracked mithril-spiked sledgehammer},
      ].each do |weapon_name|
        it "recognizes #{weapon_name} as weapon" do
          weapon = GameObjFactory.item_from_name(weapon_name)
          expect(weapon.type).to include "weapon"
          expect(weapon.sellable).to eq "pawnshop"
        end
      end
    end

    describe "polearms" do
      [
        %{awl-pike},
        %{halberd},
        %{Hammer of Kai},
        %{harpoon},
        %{lance},
        %{jeddart-axe},
        %{naginata},
        %{pilum},
        %{pitch fork},
        %{pitchfork},
        %{spear},
        %{trident},
        %{voulge},

        %{faenor bardiche},
        %{grey ora glaive},
        %{indigo ora pole-axe},
        %{glistening mithril scythe},
        %{rowan-handled feras warlance},
      ].each do |weapon_name|
        it "recognizes #{weapon_name} as weapon" do
          weapon = GameObjFactory.item_from_name(weapon_name)
          expect(weapon.type).to include "weapon"
          expect(weapon.sellable).to eq "pawnshop"
        end
      end
    end

    describe "brawling and UAC" do
      [
        %{blackjack},
        %{bludgeon},
        %{cestus},
        %{fist-scythe},
        %{hook-knife},
        %{jackblade},
        %{katar},
        %{knuckle-blade},
        %{knuckle-duster},
        %{paingrip},
        %{razorpaw},
        %{sai},
        %{tiger-claw},
        %{troll-claw},
        %{yierka-spur},
      ].each do |weapon_name|
        it "recognizes #{weapon_name} as weapon" do
          weapon = GameObjFactory.item_from_name(weapon_name)
          expect(weapon.type).to include "weapon"
          expect(weapon.sellable).to eq "pawnshop"
        end
      end
    end

    describe "ranged and thrown" do
      [
        %{composite bow},
        %{short bow},
        %{long bow},
        %{yumi},

        %{light crossbow},
        %{heavy crossbow},

        %{bola},
        %{dart},
        %{discus},
        %{javelin},
        %{net},
        %{quoit},
      ].each do |weapon_name|
        it "recognizes #{weapon_name} as weapon" do
          weapon = GameObjFactory.item_from_name(weapon_name)
          expect(weapon.type).to include "weapon"
          expect(weapon.sellable).to eq "pawnshop"
        end
      end
    end

    describe "runestaves" do
      [
        %{runestaff},
        %{crook},
      ].each do |weapon_name|
        it "recognizes #{weapon_name} as weapon" do
          weapon = GameObjFactory.item_from_name(weapon_name)
          expect(weapon.type).to include "weapon"
          expect(weapon.sellable).to eq "pawnshop"
        end
      end
    end

    describe "special weapons" do
      [
        %{elemental bow},
        %{elemental bow of acid},
        %{elemental bow of lightning},
        %{elemental bow of fire},
        %{elemental bow of ice},
        %{elemental bow of vibration},

        %{ice pick},
      ].each do |weapon_name|
        it "recognizes #{weapon_name} as weapon" do
          weapon = GameObjFactory.item_from_name(weapon_name)
          expect(weapon.type).to include "weapon"
          expect(weapon.sellable).to be nil
        end
      end
    end
  end

  describe "ammo" do
    [
      %{arrow},
      %{bundle of arrows},
      %{bolt},
      %{bundle of bolts},
      %{discuses},
      %{quoits},
    ].each do |ammo_name|
      it "recognizes #{ammo_name} as ammo" do
        ammo = GameObjFactory.item_from_name(ammo_name)
        expect(ammo.type).to include "ammo"
        expect(ammo.sellable).to be nil
      end
    end

    [
      %{discus},
      %{quoit},
    ].each do |ammo_name|
      it "recognizes #{ammo_name} as ammo" do
        ammo = GameObjFactory.item_from_name(ammo_name)
        expect(ammo.type).to include "ammo"
        expect(ammo.sellable).to eq "pawnshop"
      end
    end
  end
end
