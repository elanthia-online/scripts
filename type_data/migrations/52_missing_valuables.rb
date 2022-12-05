migrate :gemshop do
  insert(:name, %{piece of petrified thanot})
end

migrate :gem do
  delete(:noun, %{mother\-of\-pearl})
  insert(:name, %{piece of petrified maoral})
  insert(:name, %{piece of petrified thanot})
  insert(:name, %{piece of rosespar})
end

migrate :valuable do
  insert(:noun, %{mother\-of\-pearl})
  delete(:name, %{piece of rosespar})
end
