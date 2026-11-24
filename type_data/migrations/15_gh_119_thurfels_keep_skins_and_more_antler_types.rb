# Thurfel's Keep skins
migrate :skin, :furrier do
  insert(:name, %{long fiery red spine})
  insert(:name, %{faintly glowing worm skin})
end

# Banded rattlesnake skins
migrate :skin, :furrier do
  insert(:name, %{two-tip rattlesnake rattle})
  insert(:name, %{three-tip rattlesnake rattle})
  insert(:name, %{four-tip rattlesnake rattle})
  insert(:name, %{five-tip rattlesnake rattle})
end


# Great stag antlers can go up to seven tines
migrate :skin do
  insert(:name, %{wide rack of seven-tined antlers})
end

# Great stag antlers were in the skins list but missing from the furrier sellable list
migrate :furrier do
  insert(:name, %{pair of (?:spike|forked|three-tined) antlers})
  insert(:name, %{(?:wide )?rack of (three|four|five|six|seven)\-tined antlers})
end
