migrate :gemshop, :lm_trap, :magic do
  insert(:name, %{small dark crystal})
  insert(:name, %{small amethyst sphere})
  insert(:name, %{small dark red sphere})
  insert(:name, %{miniature emerald sphere})
  insert(:name, %{small icy blue sphere})
  insert(:name, %{small light violet sphere})
  insert(:name, %{small dark reddish-brown sphere})
  insert(:name, %{tiny stone grey sphere})
  insert(:name, %{tiny wavering sphere})
end

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

migrate :lm_trap, :pawnshop do
  insert(:name, %{clear glass vial of light yellow acid})
  insert(:name, %{green-tinted vial filled with thick acrid smoke})
  insert(:name, %{thick glass vial filled with murky red liquid})
end

migrate :pawnshop do
  insert(:exclude, %{small dark crystal})
  insert(:exclude, %{dark crystal})

  insert(:name, %{pair of small steel jaws})
  insert(:name, %{slender steel needle})
  insert(:name, %{green-tinted vial})
  insert(:name, %{thick glass vial})
  insert(:name, %{clear glass vial})
end
