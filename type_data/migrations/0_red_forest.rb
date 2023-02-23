migrate :aggressive_npc do
  insert(:name, "winged viper")
  insert(:name, "Ilvari pixie")
  insert(:name, "Ilvari sprite")
  insert(:name, "direbear")
  insert(:name, "monstrous direwolf")
  insert(:name, "treekin warrior")
  insert(:name, "treekin druid")
  insert(:name, "treekin sapling")
end

migrate :undead, :aggressive_npc do
  insert(:name, "warped tree spirit")  
end

migrate :passive_npc do
  insert(:exclude, "warped tree spirit")  
end

migrate :skin, :furrier do
  insert(:name, "direbear fang")
  insert(:name, "heavy grey tusk")
  insert(:name, "red eye")
  insert(:name, "mossy beard")
  insert(:name, "(?:some )?blood-stained bark")
  insert(:name, "pure white feather")
end
