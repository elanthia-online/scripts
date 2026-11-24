migrate :uncommon do
  insert(:exclude, %{[\w\s]+ (?:disk|coffin)})
end
