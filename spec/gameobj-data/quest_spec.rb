require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "quest" do
    describe "Elemental Confluence soulstones" do
      [
        %{elemental soulstone},
        %{gleaming multicolored soulstone},
      ].each do |quest_item_name|
        it "recognizes #{quest_item_name} as a quest item" do
          expect(GameObjFactory.item_from_name(quest_item_name).type).to eq "quest"
        end
      end
    end
  end
end
