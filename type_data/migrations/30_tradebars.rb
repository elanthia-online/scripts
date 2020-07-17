migrate :gemshop, :valuable do
  insert(:name, %{copper tradebar})
  insert(:name, %{bronze tradebar})
  insert(:name, %{silver tradebar})
  insert(:name, %{gold tradebar})
  insert(:name, %{platinum tradebar})
  insert(:name, %{small copper tradebar})
  insert(:name, %{small bronze tradebar})
  insert(:name, %{small silver tradebar})
  insert(:name, %{small gold tradebar})
  insert(:name, %{small platinum tradebar})
  insert(:name, %{large copper tradebar})
  insert(:name, %{large bronze tradebar})
  insert(:name, %{large silver tradebar})
  insert(:name, %{large gold tradebar})
  insert(:name, %{large platinum tradebar})
end

migrate :uncommon do
  insert(:exclude, %{bronze tradebar})
  insert(:exclude, %{small bronze tradebar})
  insert(:exclude, %{large bronze tradebar})
  insert(:exclude, %{bronze square})
end
