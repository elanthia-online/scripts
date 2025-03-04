create_table "lockandkey:bauble", keys: [:name]
create_table "lockandkey:key", keys: [:name]
create_table "lockandkey:lock", keys: [:name]
create_table "lockandkey:rune", keys: [:name]
create_table "lockandkey:misc", keys: [:name]

migrate "lockandkey:bauble" do
  insert(:name, %{radiant golden bauble})
  insert(:name, %{vibrant golden bauble})
end

migrate "lockandkey:key" do
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
end

migrate "lockandkey:lock" do
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

migrate "lockandkey:misc" do
  insert(:name, %{glowing torn page})
end
