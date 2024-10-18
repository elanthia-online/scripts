create_table "jewel", keys: [:noun, :exclude]

migrate :jewel do
  insert(:noun, %[jewel])
end
