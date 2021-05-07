migrate :undead do
  insert(:name, %{sacristan spirit})
end

migrate :passive_npc do
  insert(:exclude, %{sacristan spirit$})
  insert(:exclude, %{ancient moaning spirit})
  insert(:exclude, %{ancient tree spirit})
  insert(:exclude, %{elder tree spirit})
end
