migrate :aggressive_npc do
  insert(:name, %[lithe veiled sentinel])
  insert(:name, %[pale scaled shaper])
  insert(:name, %[deathsworn fanatic])
  insert(:name, %[white sidewinder])
end

migrate :aggressive_npc, :undead do
  insert(:name, %[shambling lurk])
  insert(:name, %[patchwork flesh monstrosity])
end

migrate :gem, :gemshop do
  insert(:name, %[oblong blue goldstone])
  insert(:name, %[dull grey crystal])
  insert(:name, %[pink salt crystal])
end

migrate :skin, :furrier do
  insert(:name, %[sidewinder scale])
end

migrate :magic, :pawnshop do
  insert(:exclude, %[pink salt crystal])
  insert(:exclude, %[dull grey crystal])
end
