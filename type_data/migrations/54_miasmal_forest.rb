migrate :undead, :aggressive_npc do
  insert(:name, %{lesser fetid corpse})
  insert(:name, %{greater fetid corpse})
end

migrate :undead, :aggressive_npc, :noncorporeal do
  insert(:name, %{luminous spectre})
  insert(:name, %{spectral black warhorse})
end
