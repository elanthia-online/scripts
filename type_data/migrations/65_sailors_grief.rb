migrate :aggressive_npc do
  insert(:name, %{brackish bilge mass})
  insert(:name, %{fulminating stormborn primordial})
  insert(:name, %{gigantic lightning whelk})
  insert(:name, %{grey-plumed steelwing harpy})
  insert(:name, %{hapless charmed corsair})
  insert(:name, %{kelp-tangled coral golem})
  insert(:name, %{scaly needle-toothed trenchling})
end

migrate :undead, :aggressive_npc do
  insert(:name, %{garish revenant buccaneer})
  insert(:name, %{milky-eyed drowned mariner})
  insert(:name, %{pallid fog-cloaked kelpie})
end

migrate :undead, :aggressive_npc, :noncorporeal do
  insert(:name, %{tenebrific wraith shark})
end
