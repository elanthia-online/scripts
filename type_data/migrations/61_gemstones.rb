create_table "ascension:jewel", keys: [:noun]

migrate "ascension:jewel" do
  insert(:noun, %[jewel])
end
