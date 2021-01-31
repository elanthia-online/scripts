migrate :skin, :furrier do
  insert(:name, %{cyan jungle toad hide})
  insert(:name, %{green jungle toad hide})
  insert(:name, %{lemur tail})
  insert(:name, %{diaphanous mosquito wing})
end

migrate :aggressive_npc do
  insert(:name, %{enormous mosquito})
  insert(:name, %{huge jungle toad})
  insert(:name, %{jungle feyling})
  insert(:name, %{large ring-tailed lemur})
end
