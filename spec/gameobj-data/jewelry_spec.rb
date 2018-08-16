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
        goblet
        headband
        medallion
        neckchain
        necklace
        pendant
        pin
        platter
        ring
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
