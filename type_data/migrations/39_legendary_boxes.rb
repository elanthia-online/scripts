migrate :box do
  create_key(:name) # https://github.com/elanthia-online/scripts/issues/389
  insert(:name, %{filigreed rolaren reliquary})
end
