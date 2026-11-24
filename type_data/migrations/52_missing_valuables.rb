migrate :gemshop do
  insert(:name, %{piece of petrified thanot})
end

migrate :gem do
  insert(:name, %{piece of petrified maoral})
  insert(:name, %{piece of petrified thanot})
  insert(:name, %{piece of rosespar})
end

migrate :valuable do
  delete(:name, %{piece of rosespar})
end
