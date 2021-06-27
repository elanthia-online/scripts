migrate :skin, :furrier do
  insert(:name, %{ruffed black griffin pelt})
  insert(:name, %{soft blue griffin feather})
  insert(:name, %{ruffed tawny griffin pelt})
  insert(:name, %{pale troll tongue})
  insert(:name, %{scraggly swamp troll scalp})
  insert(:name, %{brown boar hide})
  insert(:name, %{moor eagle talon})
end

migrate :skin, :furrier do
  delete(:name, %{brown boar skin})
end
