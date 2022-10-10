migrate :gem, :gemshop do
  insert(:name, %{petrified toadstool})
  insert(:name, %{some silvery galena})
end

migrate :junk do
  insert(:name, %{crude roa'ter-toothed necklace})
end

migrate :jewelry, :gemshop, :pawnshop do
  insert(:exclude, %{crude roa'ter-toothed necklace})
end

