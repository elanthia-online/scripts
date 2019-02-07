require 'lich/gameobj'

describe GameObj do
  it "can load data from the XML file" do
    expect(GameObj.load_data).to be_truthy
    expect(GameObj.type_data).to_not be_nil
    expect(GameObj.type_data).to_not be_empty
  end

  context "after the XML data has been loaded" do
    before { GameObj.load_data }

    it "has the expected types" do
      expect(GameObj.type_data.keys).to contain_exactly(
        "aggressive npc",
        "alchemy equipment",
        "alchemy product",
        "ammo",
        "armor",
        "bandit",
        "box",
        "clothing",
        "collectible",
        "cursed",
        "ebongate",
        "escort",
        "event:duskruin",
        "food",
        "gem",
        "grimswarm",
        "herb",
        "instrument",
        "jar",
        "jewelry",
        "junk",
        "lm tool",
        "lm trap",
        "lockpick",
        "magic",
        "note",
        "passive npc",
        "plinite",
        "quest",
        "reagent",
        "realm:reim",
        "scarab",
        "scroll",
        "skin",
        "spirit beast talismans",
        "toy",
        "uncommon",
        "undead",
        "valuable",
        "wand",
        "weapon"
      )
    end
  end
end
