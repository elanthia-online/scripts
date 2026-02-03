migrate :gemshop do
  insert(:exclude, %{praying white ora figurine})
end

migrate :gemshop, :valuable do
  insert(:name, %{rough slab of gold})
end
