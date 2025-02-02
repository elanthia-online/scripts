require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "regular simucoin item" do
    [
      %{birth certificate parchment},    # Character Birthday Adjustment Parchment
      %{cultural registration document}, # Character Culture Reset
      %{brass and gold sphere},          # Chronomage transport sphere
      %{Chronomage rush ticket},         # Chronomage Rush Ticket
      %{squat pale grey crystal bottle}, # Spell Up Pills (10)
      %{sun-etched gold ring},           # Gold Ring - Unnavvable (30 days)
    ].each do |simucoin_item_name|
      it "recognizes #{simucoin_item_name} as a regular simucoin item" do
        simucoin_item = GameObjFactory.item_from_name(simucoin_item_name)
        expect(simucoin_item.type).to include "simucoin:regular"
        expect(simucoin_item.type).to_not include "scroll"
        expect(simucoin_item.type).to_not include "magic"
        expect(simucoin_item.type).to_not include "uncommon"
        expect(simucoin_item.type).to_not include "jewelry"
        expect(simucoin_item.sellable).to be nil
      end
    end
  end

  describe "duskruin simucoin item" do
    [
      %{parchment stamped voucher},        # Duskruin Arena - 1 voucher
      %{bronze stamped voucher booklet},   # Duskruin Arena - 10 vouchers
      %{silver stamped voucher booklet},   # Duskruin Arena - 25 vouchers
      %{gold stamped voucher booklet},     # Duskruin Arena - 150 vouchers
      %{platinum stamped voucher booklet}, # Duskruin Arena - 100 vouchers
      %{sanguine stamped voucher booklet}, # Duskruin Arena - 250 vouchers
    ].each do |simucoin_item_name|
      it "recognizes #{simucoin_item_name} as a duskruin simucoin item" do
        simucoin_item = GameObjFactory.item_from_name(simucoin_item_name)
        expect(simucoin_item.type).to include "simucoin:duskruin"
        expect(simucoin_item.type).to_not include "scroll"
        expect(simucoin_item.type).to_not include "magic"
        expect(simucoin_item.type).to_not include "uncommon"
        expect(simucoin_item.type).to_not include "jewelry"
        expect(simucoin_item.sellable).to be nil
      end
    end
  end

  describe "reim simucoin item" do
    [
      %{small glowing orb},         # Settlement of Reim - 1 access token
      %{glowing orb},               # Settlement of Reim - 10 access tokens
      %{large glowing orb},         # Settlement of Reim - 50 access tokens
      %{pair of prismatic goggles}, # Settlement of Reim - Reim googles
    ].each do |simucoin_item_name|
      it "recognizes #{simucoin_item_name} as a reim simucoin item" do
        simucoin_item = GameObjFactory.item_from_name(simucoin_item_name)
        expect(simucoin_item.type).to include "simucoin:reim"
        expect(simucoin_item.type).to_not include "scroll"
        expect(simucoin_item.type).to_not include "magic"
        expect(simucoin_item.type).to_not include "uncommon"
        expect(simucoin_item.type).to_not include "jewelry"
        expect(simucoin_item.sellable).to be nil
      end
    end
  end

  describe "f2p simucoin item" do
    [
      %{bright flame-shaped token}, # Initial Element Attunement
      %{tiny fox-shaped token},     # Spell Reset - Familiar Gate (930)
      %{account transfer form},     # Bank Account Transfer
      %{bronze sword token},        # Gear Pass - Bronze
    ].each do |simucoin_item_name|
      it "recognizes #{simucoin_item_name} as a f2p simucoin item" do
        simucoin_item = GameObjFactory.item_from_name(simucoin_item_name)
        expect(simucoin_item.type).to include "simucoin:f2p"
        expect(simucoin_item.type).to_not include "scroll"
        expect(simucoin_item.type).to_not include "magic"
        expect(simucoin_item.type).to_not include "uncommon"
        expect(simucoin_item.type).to_not include "jewelry"
        expect(simucoin_item.sellable).to be nil
      end
    end
  end
end
