migrate :skin, :furrier do
  insert(:name, %{leathery bat wing})
end

migrate :skin, :furrier do
  delete(:name, %{leathery bat wings})
end
