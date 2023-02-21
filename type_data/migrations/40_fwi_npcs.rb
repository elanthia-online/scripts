migrate :skin, :furrier do
  insert(:name, %{cyan jungle toad hide})
  insert(:name, %{green jungle toad hide})
  insert(:name, %{lemur tail})
  insert(:name, %{diaphanous mosquito wing})
  insert(:name, %{bristly tapir snout})
  insert(:name, %{tapir snout})
  insert(:name, %{dark brown forest ape pelt})
  insert(:name, %{forest ape pelt})
end

migrate :aggressive_npc do
  insert(:name, %{enormous mosquito})
  insert(:name, %{huge jungle toad})
  insert(:name, %{jungle feyling})
  insert(:name, %{large ring-tailed lemur})
  insert(:name, %{bristly black tapir})
  insert(:name, %{hulking forest ape})
  insert(:name, %{cloud sprite meddler})
  insert(:name, %{cloud sprite bully})
end

migrate :valuable, :pawnshop do
  insert(:name, %{petrified sprite figurine})
end

migrate :magic, :gemshop do
  insert(:exclude, %{petrified sprite figurine})
end

