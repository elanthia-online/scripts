migrate :jewelry do
  insert(:exclude, %{smooth stone talisman})
end

migrate :alchemy_product do
  insert(:name, %{smooth stone talisman})
end

migrate :herb do
  insert(:name, %{tincture of tkaro})
end
