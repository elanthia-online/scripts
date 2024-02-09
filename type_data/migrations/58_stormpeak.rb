migrate :aggressive_npc do
  insert(:name, %{water hound})
  insert(:name, %{vapor hound})
  insert(:name, %{storm hound})
  insert(:name, %{lightning fiend})
  insert(:name, %{titan stormcaller})
  insert(:name, %{tempest tyrant})
  insert(:name, %{Veiki herald})
end

migrate :undead, :aggressive_npc, :noncorporeal do
  insert(:name, %{swirling spectre})
end
