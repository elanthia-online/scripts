migrate :skin, :furrier do
  create_key(:exclude)
  insert(:name, %{gold-flecked claw})
  insert(:exclude, %{gold-flecked claw})
  insert(:exclude, %{bundle of curved gold-flecked claws})

  insert(:name, %{red firebird feather})
  insert(:exclude, %{red firebird feather})
  insert(:exclude, %{bundle of soft red firebird feathers})

  insert(:name, %{triton spine})
  insert(:exclude, %{triton spine})
  insert(:exclude, %{bundle of elongated triton spines})

  insert(:name, %{triton hide})
  insert(:exclude, %{triton hide})
  insert(:exclude, %{bundle of iridescent triton hides})

  insert(:name, %{brindlecat hide})
  insert(:exclude, %{brindlecat hide})
  insert(:exclude, %{bundle of tawny brindlecat hides})

  insert(:name, %{hobgoblin snout})
  insert(:exclude, %{hobgoblin snout})
  insert(:exclude, %{bundle of mongrel hobgoblin snout})

  insert(:name, %{acolyte ear})
  insert(:exclude, %{acolyte ear})
  insert(:exclude, %{bundle of hobgoblin acolyte ear})

  insert(:name, %{black eye})
  insert(:exclude, %{black eye})
  insert(:exclude, %{bundle of glistening black eye})
end
