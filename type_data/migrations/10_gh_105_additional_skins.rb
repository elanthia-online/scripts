# https://github.com/elanthia-online/scripts/issues/105

migrate :skin, :furrier do
  insert(:name, %{ruffed white griffin pelt})
  insert(:name, %{soft grifflet pelt})
  insert(:name, %{dark panther pelt})
  insert(:name, %{pra'eda canine})
  delete(:name, %{ash hag nose})
  insert(:name, %{hag nose})
end
