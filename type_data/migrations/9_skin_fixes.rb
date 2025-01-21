migrate :skin, :furrier do
  insert(:name, %{ruffed black griffin pelt})
  insert(:name, %{soft blue griffin feather})
  insert(:name, %{ruffed tawny griffin pelt})
  insert(:name, %{pale troll tongue})
  insert(:name, %{scraggly swamp troll scalp})
  insert(:name, %{brown boar hide})
  insert(:name, %{moor eagle talon})
  insert(:name, %{mountain snowcat pelt})
  insert(:name, %{(?:crooked )?witch nose})     # from wind witch
end

migrate :skin, :furrier do
  delete(:name, %{brown boar skin})
end
