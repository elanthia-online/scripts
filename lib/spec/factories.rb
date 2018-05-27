require 'lich/gameobj'

module GameObjFactory
  def self.npc_from_name(npc_name)
    GameObj.new_npc("fake_id", npc_name.split.last, npc_name)
  end
end
