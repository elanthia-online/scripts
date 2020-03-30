migrate :undead, :passive_npc do
  insert(:name, %{sacristan spirit})
end

migrate :undead do
  insert(:name, %{moaning spirit})
end
