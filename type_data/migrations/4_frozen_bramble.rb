migrate :skin, :furrier do
  insert(:name, %{bleached thorn})
  insert(:name, %{blood-stained leaf})
  insert(:name, %{desiccated stem})
  insert(:name, %{frosted branch})
  insert(:name, %{shriveled cutting})
  insert(:name, %{thorn-ridden appendage})
end

migrate :aggressive_npc, :undead do
  insert(:name, %{blackened decaying tumbleweed})
  insert(:name, %{dark frosty plant})
  insert(:name, %{large thorned shrub})
  insert(:name, %{shriveled icy creeper})
  insert(:name, %{writhing frost-glazed vine})
  insert(:name, %{writhing icy bush})
end
