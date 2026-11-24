migrate :aggressive_npc do
  insert(:name, %[lithe veiled sentinel])
  insert(:name, %[pale scaled shaper])
  insert(:name, %[deathsworn fanatic])
  insert(:name, %[white sidewinder])
  insert(:name, %{sand-hued desert sidewinder})
end

migrate :aggressive_npc, :undead do
  insert(:name, %[shambling lurk])
  insert(:name, %[patchwork flesh monstrosity])
  insert(:name, %[ancient flesh monstrosity])
end

migrate :gem, :gemshop do
  insert(:name, %[oblong blue goldstone])
  insert(:name, %[dull grey crystal])
  insert(:name, %[pink salt crystal])
  insert(:name, %[twisted iron spiral])
end

migrate :gemshop do
  insert(:name, %[age-darkened ivory crescent])
  insert(:name, %[blackish blue idocrase])
  insert(:name, %[cloudy alexandrite shard])
  insert(:name, %[faceted blood red sandruby])
  insert(:name, %[fossilized bessho lizard spur])
  insert(:name, %[formation of rainbowed bismuth])
  insert(:name, %[piece of striated fluorite])
  insert(:name, %[radiant green cinderstone])
  insert(:name, %[square of shale rock])
  insert(:name, %[swirled lightning glass shard])
  insert(:name, %[variegated violet tanzanite])
end

migrate :skin, :furrier do
  insert(:name, %[sidewinder scale])
end

migrate :magic, :pawnshop do
  insert(:exclude, %[pink salt crystal])
  insert(:exclude, %[dull grey crystal])
end
