require 'lich/gameobj'
require 'spec/factories'

describe GameObj do
  describe "junk" do
    [
      %{smooth stone},
      %{spirit shard},
      %{small block of salt},
      %{table leg},
      %{some tree bark},
      %{piece of iron},
      %{moldy bone},
      %{chipped brick},
      %{some tattered cloth},
      %{steel shield},
      %{scratched steel helm},
    ].each do |junk_name|
      it "recognizes #{junk_name} as junk" do
        junk = GameObjFactory.item_from_name(junk_name)
        expect(junk.type).to eq "junk"
        expect(junk.sellable).to be nil
      end
    end

    describe "junk specific to certain creatures" do
      [
        %{hollow smooth black glaes},
      ].each do |junk_name|
        it "recognizes critter dropped #{junk_name} as junk" do
          junk = GameObjFactory.item_from_name(junk_name)
          expect(junk.type).to eq "junk"
          expect(junk.sellable).to be nil
        end
      end
    end

    describe "randomized junk names from treasure system" do
      junk_nouns = %w[coin cup doorknob fork horseshoe nail spoon]
      junk_descriptors = %w[bent corroded dented polished rusty scratched shiny tarnished]

      junk_nouns.product(junk_descriptors).each do |noun, desc|
        junk_name = "#{desc} #{noun}"

        it "recognizes #{junk_name} as junk" do
          junk = GameObjFactory.item_from_name(junk_name)
          expect(junk.type).to eq "junk"
          expect(junk.sellable).to be nil
        end
      end

      junk_jewelry = %w[anklet bracelet earring medallion plate ring]
      junk_jewelry.product(junk_descriptors).each do |noun, desc|
        junk_name = "#{desc} #{noun}"

        it "recognizes #{junk_name} as junk" do
          junk = GameObjFactory.item_from_name(junk_name)
          expect(junk.type).to eq "junk"
          expect(junk.sellable).to be nil
        end
      end
    end
  end
end
