migrate :gem, :gemshop do
  insert(:name, %{heart of smooth black glaes})
end

migrate :junk do
  insert(:name, %{hollow smooth black glaes})
end

migrate :uncommon do
  insert(:exclude, %{heart of smooth black glaes})
  insert(:exclude, %{hollow smooth black glaes})
end
