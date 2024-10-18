create_table "ascension:jewel", keys: [:noun, :exclude]

migrate "ascension:jewel" do
  insert(:noun, %[jewel])
end
