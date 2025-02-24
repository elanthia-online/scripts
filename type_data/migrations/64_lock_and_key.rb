create_table "lockandkey", keys: [:name]

migrate "lockandkey", "uncommon" do
  insert(:name, %{radiant blood red key})
  insert(:name, %{radiant forest green key})
  insert(:name, %{radiant frosty white key})
  insert(:name, %{radiant rainbow-hued key})
  insert(:name, %{radiant royal blue key})

  insert(:name, %{vibrant blood red key})
  insert(:name, %{vibrant forest green key})
  insert(:name, %{vibrant frosty white key})
  insert(:name, %{vibrant rainbow-hued key})
  insert(:name, %{vibrant royal blue key})

  insert(:name, %{radiant blood red lock})
  insert(:name, %{radiant forest green lock})
  insert(:name, %{radiant frosty white lock})
  insert(:name, %{radiant rainbow-hued lock})
  insert(:name, %{radiant royal blue lock})

  insert(:name, %{vibrant blood red lock})
  insert(:name, %{vibrant forest green lock})
  insert(:name, %{vibrant frosty white lock})
  insert(:name, %{vibrant rainbow-hued lock})
  insert(:name, %{vibrant royal blue lock})
end
