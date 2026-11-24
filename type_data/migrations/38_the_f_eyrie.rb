migrate :aggressive_npc do
  insert(:name, %{ash guardian})
  insert(:name, %{blazing red phoenix})
  insert(:name, %{firebird})
end

migrate :skin, :furrier do
  insert(:name, %{soft red firebird feather})
end
