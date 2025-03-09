create_table "ascension:jewel", keys: [:noun, :exclude]
create_table "ascension:quest", keys: [:name]

migrate "ascension:jewel" do
  insert(:noun, %[jewel])
  insert(:exclude, %{iron black jewel})
end

migrate "ascension:quest", :uncommon do
  insert(:name, %{silver-veined black draconic idol})
end

migrate "ascension:quest" do
  insert(:name, %{small cloth bundle})
  insert(:name, %{ancient crumbling gemstone})
  insert(:name, %{tattered parchment note})
  insert(:name, %{tear-shaped iridescent gemstone})
  insert(:name, %{iron black jewel})
end
