require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "sellable" do
    describe "things without types that are sellable at the gem shop" do
      [
        %{flask},
        %{jug},
        %{pitcher},
        %{plate},
      ].each do |item|
        it "recognizes #{item} as sellable at the gem shop" do
          expect(GameObjFactory.item_from_name(item).type).to be_nil
          expect(GameObjFactory.item_from_name(item).sellable).to include "gemshop"
        end
      end
    end
  end
end
