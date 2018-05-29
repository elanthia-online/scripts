require 'lich/gameobj'

module GameObjFactory
  def self.npc_from_name(npc_name)
    GameObj.new_npc("fake_id", npc_name.split.last, npc_name)
  end

  def self.item_from_name(item_name, item_noun=item_name.split.last)
    GameObj.new_loot("fake_item_id", item_noun, item_name)
  end
end
