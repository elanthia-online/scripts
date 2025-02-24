create_table "lockandkey", keys: [:name]

migrate "lockandkey", "uncommon" do
  insert(:name, %{vibrant rainbow-hued key}) 
  insert(:name, %{vibrant rainbow-hued lock}) 
end
