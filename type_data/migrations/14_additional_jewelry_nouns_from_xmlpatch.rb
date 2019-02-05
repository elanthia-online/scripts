migrate :jewelry do
  create_key(:name)
  insert(:name, %i{^(?!some).*\bplate$})

  insert(:noun, %{flask})
  insert(:noun, %{jug})
  insert(:noun, %{pitcher})
  insert(:noun, %{scepter})

  insert(:exclude, %{white flask})
end

migrate :gemshop do
  insert(:noun, %{scepter})
end
