create_table "ascension:jewel", keys: [:noun]
create_table "ascension:quest", keys: [:name]

migrate "ascension:jewel" do
  insert(:noun, %[jewel])
end

migrate "ascension:quest", "uncommon" do
  insert(:name, %{silver-veined black draconic idol})
end
