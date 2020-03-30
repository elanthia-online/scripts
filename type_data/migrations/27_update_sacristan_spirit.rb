migrate :undead do
  insert(:name, %{sacristan spirit})
end

migrate :passive_npc do
  insert(:exclude, %{sacristan spirit$})
end
