require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "weapons" do
    describe "one-handed edged" do
      [
        %{backsword},
        %{mortuary sword},
        %{riding sword},
        %{sidesword},

        %{broadsword},
        %{carp's-tongue},
        %{carp's tongue},
        %{flyssa},
        %{goliah},
        %{katzbalger},
        %{machera},
        %{palache},
        %{schiavona},
        %{seax},
        %{spadroon},
        %{spatha},
        %{talon sword},
        %{xiphos},

        %{dagger},
        %{alfange},
        %{basilard},
        %{bodice dagger},
        %{bodkin},
        %{boot dagger},
        %{bracelet dagger},
        %{butcher knife},
        %{cinquedea},
        %{crescent dagger},
        %{dirk},
        %{fantail dagger},
        %{forked dagger},
        %{gimlet knife},
        %{hunting dagger},
        %{kidney dagger},
        %{knife},
        %{kozuka},
        %{misericord},
        %{parazonium},
        %{pavade},
        %{poignard},
        %{pugio},
        %{push dagger},
        %{scramasax},
        %{sgian achlais},
        %{sgian dubh},
        %{sidearm-of-Onar},
        %{spike},
        %{stiletto},
        %{tanto},
        %{trail knife},
        %{trailknife},

        %{estoc},
        %{koncerz},

        %{falchion},
        %{badelaire},
        %{craquemarte},
        %{falcata},
        %{khopesh},
        %{kiss-of-Ivas},
        %{machete},
        %{takouba},
        %{warblade},

        %{handaxe},
        %{balta},
        %{boarding axe},
        %{broad axe},
        %{cleaver},
        %{crescent axe},
        %{double-bit axe},
        %{field-axe},
        %{francisca},
        %{hatchet},
        %{hunting hatchet},
        %{ice axe},
        %{limb-cleaver},
        %{logging axe},
        %{meat cleaver},
        %{miner's axe},
        %{moon axe},
        %{ono},
        %{raiding axe},
        %{sparte},
        %{splitting axe},
        %{throwing axe},
        %{taper},
        %{tomahawk},
        %{toporok},
        %{waraxe},

        %{longsword},
        %{arming sword},
        %{kaskara},
        %{langsax},
        %{langseax},
        %{sheering sword},
        %{tachi},

        %{main gauche},
        %{parrying dagger},
        %{shield-sword},
        %{sword-breaker},

        %{rapier},
        %{bilbo},
        %{colichemarde},
        %{epee},
        %{fleuret},
        %{foil},
        %{schlager},
        %{tizona},
        %{tock},
        %{tocke},
        %{tuck},
        %{verdun},

        %{scimitar},
        %{Charl's-tail},
        %{cutlass},
        %{kama},
        %{kilij},
        %{palache},
        %{sabre},
        %{sapara},
        %{shamshir},
        %{yataghan},

        %{short sword},
        %{antler sword},
        %{backslasher},
        %{braquemar},
        %{baselard},
        %{chereb},
        %{coustille},
        %{gladius},
        %{kris},
        %{kukri},
        %{Niima's-embrace},
        %{sica},
        %{wakizashi},

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
        %{purple rolaren-studded shillelagh},
        %{maple-hafted vaalorn fauchard},
        %{saw-toothed zorchar cutlass},
        %{perfect steel-hilted steel short-sword},
        %{thanot-hafted glaes-spiked tetsubo},
        %{engraved ruic arbalest},
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
        %{ball and chain},
        %{ball & chain},
        %{binnol},
        %{goupillon},
        %{mace and chain},

        %{crowbill},
        %{skull-piercer},

        %{cudgel},
        %{baculus},
        %{club},
        %{jo stick},
        %{lisan},
        %{periperiu},
        %{shillelagh},
        %{tambara},
        %{truncheon},
        %{war club},

        %{mace},
        %{bulawa},
        %{dhara},
        %{flanged mace},
        %{knee-breaker},
        %{massuelle},
        %{mattina},
        %{ox mace},
        %{pernat},
        %{quadrelle},
        %{ridgemace},
        %{studded mace},

        %{morning star},
        %{spiked mace},
        %{holy water sprinkler},
        %{spikestar},

        %{war hammer},
        %{hammerbeak},
        %{hoolurge},
        %{horseman's hammer},
        %{skull-crusher},
        %{taavish},

        %{whip},
        %{bullwhip},
        %{cat o' nine tails},
        %{signal whip},
        %{single-tail whip},
        %{slaver's whip},
        %{training whip},

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
        %{bastard sword},
        %{espadon},
        %{warsword},

        %{battle axe},
        %{adze},
        %{balestarius},
        %{battle-axe},
        %{bearded axe},
        %{doloire},
        %{executioner's axe},
        %{great axe},
        %{greataxe},
        %{kheten},
        %{roa'ter axe},
        %{tabar},
        %{woodsman's axe},


        %{claidhmore},

        %{flail},
        %{military flail},
        %{spiked-staff},


        %{flamberge},
        %{wave-bladed sword},
        %{sword-of-Phoen},

        %{maul},
        %{footman's hammer},
        %{sledgehammer},
        %{tetsubo},

        %{military pick},
        %{bisacuta},
        %{mining pick},

        %{katana},

        %{quarterstaff},
        %{bo stick},
        %{quarter staff},
        %{short-staff},
        %{staff},
        %{walking staff},
        %{warstaff},
        %{yoribo},

        %{twohanded sword},
        %{battlesword},
        %{beheading sword},
        %{bidenhander},
        %{falx},
        %{executioner's sword},
        %{greatsword},
        %{no-dachi},
        %{zweihander},

        %{war mattock},
        %{mattock},
        %{oncin},
        %{pickaxe},
        %{sabar},

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
        %{ahlspiess},
        %{breach pike},
        %{chest-ripper},
        %{korseke},
        %{military fork},
        %{ranseur},
        %{runka},
        %{scaling fork},
        %{spetum},

        %{halberd},
        %{bardiche},
        %{bill},
        %{brandestoc},
        %{croc},
        %{falcastra},
        %{fauchard},
        %{glaive},
        %{godendag},
        %{guisarme},
        %{half moon},
        %{half-moon},
        %{hippe},
        %{pole axe},
        %{pole-axe},
        %{scorpion},
        %{scythe},

        %{Hammer of Kai},
        %{longhammer},
        %{polehammer},
        %{spiked-hammer},

        %{jeddart-axe},
        %{beaked axe},
        %{nagimaki},
        %{poleaxe},
        %{voulge},

        %{lance},
        %{framea},
        %{pike},
        %{sarissa},
        %{sudis},
        %{warlance},

        %{naginata},
        %{bladestaff},
        %{swordstaff},

        %{pilum},
        %{shield-breaker},
        %{shield-sunderer},

        %{spear},
        %{angon},
        %{boar spear},
        %{cateia},
        %{dory},
        %{falarica},
        %{gaesum},
        %{harpoon},
        %{partisan},
        %{partizan},
        %{pill},
        %{spontoon},
        %{yari},

        %{trident},
        %{fuscina},
        %{magari-yari},
        %{pitch fork},
        %{pitchfork},
        %{zinnor},

        %{faenor bardiche},
        %{grey ora glaive},
        %{indigo ora pole-axe},
        %{glistening mithril scythe},
        %{rowan-handled feras warlance},
        %{barbed mithril-tipped pike},
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
        %{sap},

        %{cestus},

        %{fist-scythe},
        %{hand-hook},
        %{hook},
        %{hook-claw},

        %{hook-knife},
        %{pit-knife},
        %{sabiet},

        %{jackblade},
        %{slash-jack},

        %{katar},
        %{gauntlet-sword},
        %{kunai},
        %{manople},
        %{paiscush},
        %{pata},
        %{slasher},

        %{knuckle-blade},
        %{slash-fist},

        %{knuckle-duster},
        %{knuckle-guard},

        %{paingrip},
        %{grab-stabber},

        %{razorpaw},
        %{slap-slasher},

        %{sai},
        %{jitte},

        %{tiger-claw},
        %{barbed claw},
        %{thrak-bite},

        %{troll-claw},
        %{bladed claw},
        %{wight-claw},

        %{yierka-spur},
        %{spike-fist},
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
        %{arbalest},

        %{bola},
        %{bolas},
        %{boleadoras},
        %{weighted-cord},

        %{dart},

        %{discus},
        %{throwing disc},

        %{net},

        %{quoit},
        %{battle-quoit},
        %{bladed-disc},
        %{bladed-ring},
        %{bladed wheel},
        %{chakram},
        %{war-quoit},

        %{javelin},
        %{contus},
        %{jaculum},
        %{nage-yari},
        %{pelta},
        %{shail},
        %{spiculum},
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
        %{crosier},
        %{pastoral staff},
        %{rune staff},
        %{staff},
        %{staff-of-Lumnis},
        %{walking stick},
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
