migrate :gemshop do
  insert(:name, %{dark crystal})
  insert(:name, %{amethyst sphere})
  insert(:name, %{dark red sphere})
  insert(:name, %{emerald sphere})
  insert(:name, %{icy blue sphere})
  insert(:name, %{light violet sphere})
  insert(:name, %{reddish-brown sphere})
  insert(:name, %{stone grey sphere})
  insert(:name, %{wavering sphere})
end

migrate :pawnshop do
  insert(:exclude, %{dark crystal})

  insert(:name, %{pair of small steel jaws})
  insert(:name, %{slender steel needle})
  insert(:name, %{green-tinted vial})
  insert(:name, %{thick glass vial})
  insert(:name, %{clear glass vial})
end
