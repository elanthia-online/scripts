load "scripts/rofl-puzzles.lic"

module RofL
  describe Statue do
    it "has a map entry for each known position" do
      expect(Statue::POSITION_MAP.keys).to match_array(Statue::KNOWN_POSITIONS)
    end

    it "each map position movement moves to a known position" do
      Statue::POSITION_MAP.each do |(starting_position, movements)|
        movements.each do |(new_position, _)|
        expect(Statue::KNOWN_POSITIONS).to include(new_position)
      end
      end
    end

    it "knows that no movement is required if the starting position matches the ending position" do
      Statue::KNOWN_POSITIONS.each do |position|
        expect(Statue.find_path(position, position)).to eq([])
      end
    end

    it "can find a path one position away from the middle" do
      expect(Statue.find_path("middle", "centered behind")).to eq(["push"])
      expect(Statue.find_path("middle", "centered in front")).to eq(["pull"])
      expect(Statue.find_path("middle", "left")).to eq(["nudge"])
      expect(Statue.find_path("middle", "right")).to eq(["prod"])
    end

    it "can move from the middle to the corners" do
      expect(Statue.find_path("middle", "left-front corner")).to eq(["nudge", "pull"])
      expect(Statue.find_path("middle", "left-rear corner")).to eq(["nudge", "push"])
      expect(Statue.find_path("middle", "right-front corner")).to eq(["prod", "pull"])
      expect(Statue.find_path("middle", "right-rear corner")).to eq(["prod", "push"])
    end

    it "can move from the middle to the in-between positions in the front and back" do
      expect(Statue.find_path("middle", "left-front")).to eq(["pull", "nudge"])
      expect(Statue.find_path("middle", "left-rear")).to eq(["push", "nudge"])
      expect(Statue.find_path("middle", "right-front")).to eq(["pull", "prod"])
      expect(Statue.find_path("middle", "right-rear")).to eq(["push", "prod"])
    end

    it "returns nil for invalid starting/ending positions" do
      expect(Statue.find_path("middle", "non-existent position")).to eq(nil)
      expect(Statue.find_path("non-existent position", "middle")).to eq(nil)
    end

    it "can solve a puzzle" do
      altar_text = "A collection of statuary are situated near the altar: a snarling and menacing jackal statue to the right-rear of the altar; a coiled and ready-to-strike cobra casting to the right of the altar; a lithe shark-fanged nymph sculpture to the right-rear of the altar; and a flame-wreathed and sneering goddess effigy in the middle of the worshipping space."
      bowl_text = "An altar sits in the center of a worshipping space, a scrying bowl sitting atop its surface.  Arranged near the altar are a collection of statuary: a jackal statue to the right-rear of the altar; a cobra statue to the right of the altar; a nymph statue to the right-rear of the altar; and a goddess statue centered behind the altar."

      expect(Statue.determine_solution(altar_text, bowl_text)).to eq(["push effigy"])
    end
  end
end
