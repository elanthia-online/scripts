migrate :uncommon do
  insert(:exclude, %{[\w\s]+ disk})
end
