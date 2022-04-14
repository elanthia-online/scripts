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
  insert(:exclude, %{bundle of brindlecat hides})
end
