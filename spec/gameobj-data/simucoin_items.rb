require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "regular simucoin item" do
    [
      %{birth certificate parchment},    # Character Birthday Adjustment Parchment
      %{cultural registration document}, # Character Culture Reset
      %{brass and gold sphere},          # Chronomage transport sphere
      %{Chronomage rush ticket},         # Chronomage Rush Ticket
    ].each do |simucoin_item|
      it "recognizes #{simucoin_item} as a regular simucoin item" do
        manna_bread = GameObjFactory.item_from_name(simucoin_item)
        expect(manna_bread.type).to eq "simucoin:regular"
        expect(manna_bread.sellable).to be nil
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
    ].each do |simucoin_item|
      it "recognizes #{simucoin_item} as a duskruin simucoin item" do
        manna_bread = GameObjFactory.item_from_name(simucoin_item)
        expect(manna_bread.type).to eq "simucoin:duskruin"
        expect(manna_bread.sellable).to be nil
      end
    end
  end

  describe "f2p simucoin item" do
    [
      %{bright flame-shaped token}, # Initial Element Attunement
      %{tiny fox-shaped token},     # Spell Reset - Familiar Gate (930)
      %{account transfer form},     # Bank Account Transfer
    ].each do |simucoin_item|
      it "recognizes #{simucoin_item} as a f2p simucoin item" do
        manna_bread = GameObjFactory.item_from_name(simucoin_item)
        expect(manna_bread.type).to eq "simucoin:f2p"
        expect(manna_bread.sellable).to be nil
      end
    end
  end
end
