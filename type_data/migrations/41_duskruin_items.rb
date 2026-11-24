migrate "event:duskruin" do
  insert(:name, %{bright crimson glass sphere})
  insert(:name, %{carved ur-barath totem})
  insert(:name, %{dull black glass sphere})
  insert(:name, %{dull grey rabbit's foot})
  insert(:name, %{rat-shaped vial})
  insert(:name, %{sharp toxin-covered misericord})
  insert(:name, %{sickly green glass sphere})
  insert(:name, %{silky white rabbit's foot})
  insert(:name, %{silver raffle token})
  insert(:name, %{silvery white glass sphere})
  insert(:name, %{vibrant yellow glass sphere})
  insert(:name, %{flat etched stone})
end

migrate :weapon do
  create_key(:exclude)
  insert(:exclude, %{sharp toxin-covered misericord})
end

migrate :wand do
  create_key(:exclude)
  insert(:exclude, %{slender wooden rod})
end

migrate :uncommon do
  insert(:exclude, %{strand of veniom thread})
end

migrate :gem do
  insert(:exclude, %{flat etched stone})
end

migrate :gemshop do
  insert(:exclude, %{flat etched stone})
end
