migrate :armor do
  create_key(:exclude)

  insert(:exclude, %{some dirty brown robes})
  insert(:exclude, %{some flowing robes})
  insert(:exclude, %{some tattered white robes})
end

migrate :clothing do
  insert(:exclude, %{some dirty brown robes})
  insert(:exclude, %{some tattered white robes})
  insert(:exclude, %{some tattered white robes})
  insert(:exclude, %{woven cloak})
  insert(:exclude, %{tattered plaid flannel shirt})
  insert(:exclude, %{weathered plaid flannel cap})
  insert(:exclude, %{some heavy leather boots})
end

migrate :pawnshop do
  insert(:exclude, %{bone vest})
  insert(:exclude, %{dirty brown robes})
  insert(:exclude, %{leather sandals})
  insert(:exclude, %{leather skull cap})
  insert(:exclude, %{some dirty brown robes})
  insert(:exclude, %{some flowing robes})
  insert(:exclude, %{some heavy leather boots})
  insert(:exclude, %{some leather boots})
  insert(:exclude, %{some leather sandals})
  insert(:exclude, %{some tattered white robes})
  insert(:exclude, %{tattered plaid flannel shirt})
  insert(:exclude, %{weathered plaid flannel cap})
  insert(:exclude, %{woven cloak})
end
