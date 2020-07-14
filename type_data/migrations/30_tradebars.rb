migrate :valuable, :gemshop do
  insert(:name, %{(?:small |large )?(?:copper|bronze|silver|gold|platinum) tradebar})
end

migrate :uncommon do
  insert(:exclude, %{(?:small |large )?bronze tradebar})
  insert(:exclude, %{bronze square})
end
