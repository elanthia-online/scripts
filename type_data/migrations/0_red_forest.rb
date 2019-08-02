migrate :aggressive_npc do
  insert(:name, "winged viper")
  insert(:name, "Illvari pixie")
  insert(:name, "Illvari sprite")
  insert(:name, "direbear")
  insert(:name, "monstrous direwolf")
  insert(:name, "warped tree spirit")
  insert(:name, "treekin warrior")
  insert(:name, "treekin druid")
  insert(:name, "treekin sapling")
end

migrate :skin, :furrier do
  insert(:name, "direbear fang")
  insert(:name, "heavy grey tusk")
  insert(:name, "red eye")
  insert(:name, "mossy beard")
  insert(:name, "(?:some )?blood-stained bark")
  insert(:name, "pure white feather")
end
