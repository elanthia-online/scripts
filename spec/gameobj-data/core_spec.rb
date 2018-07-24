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
        "aggressive npc",     # npc_spec
        "alchemy equipment",  # alchemy
        "alchemy product",    # alchemy
        "ammo",               # arms_and_armor
        "armor",              # arms_and_armor
        "bandit",             # npc_spec
        "box",                # picking
        "collectible",        # collectible
        "clothing",           # clothing
        "cursed",             # item_property
        "ebongate",           # festival
        "escort",             # npc
        "food",               # misc
        "gem",                # gems_and_jewelry
        "grimswarm",          # npc
        "herb",               # herb
        "instrument",         # misc
        "jar",                # misc
        "jewelry",            # gems_and_jewelry
        "junk",               # junk
        "lm tool",            # picking
        "lm trap",            # picking
        "lockpick",           # picking
        "magic",              # magic
        "note",               # misc
        "passive npc",        # npc
        "plinite",            # gems_and_jewelry
        "quest",              # festival
        "reagent",            # alchemy
        "scarab",             # gems_and_jewelry
        "scroll",             # magic
        "skin",               # skin
        "spirit beast talismans", # alchemy
        "toy",                # misc
        "uncommon",           # item_property
        "undead",             # npc
        "valuable",           # gems_and_jewelry
        "wand",               # magic
        "weapon"              # arms_and_armor
      )
    end
  end
end
