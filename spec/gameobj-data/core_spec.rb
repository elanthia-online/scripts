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
        "ascension:jewel",
        "ascension:misc",
        "ascension:quest",
        "bandit",
        "boon",
        "box",
        "breakable",
        "clothing",
        "collectible",
        "cursed",
        "customization:death",
        "customization:misc",
        "customization:spellprep",
        "ebongate",
        "escort",
        "event:duskruin",
        "event:ebongate",
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
        "lockandkey:bauble",
        "lockandkey:key",
        "lockandkey:lock",
        "lockandkey:rune",
        "lockandkey:misc",
        "lockpick",
        "manna bread",
        "magic",
        "noncorporeal",
        "note",
        "passive npc",
        "plinite",
        "quest",
        "reagent",
        "realm:reim",
        "scarab",
        "scroll",
        "skin",
        "simucoin:regular",
        "simucoin:briarmooncove",
        "simucoin:deliriummanor",
        "simucoin:duskruin",
        "simucoin:rumorwoods",
        "simucoin:ebongate",
        "simucoin:reim",
        "simucoin:f2p",
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
