require 'lich/gameobj'

module GameObjFactory
  def self.npc_from_name(npc_name)
    GameObj.new_npc("fake_id", npc_name.split.last, npc_name)
  end

  def self.item_from_name(item_name, item_noun=item_name.split.last, after_name=nil)
    GameObj.new_loot("fake_item_id", item_noun, item_name).tap do |loot|
      loot.after_name = after_name if after_name
    end
  end
end
