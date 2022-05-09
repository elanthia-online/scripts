migrate :aggressive_npc do
  insert(:name, %{triton assassin})
  insert(:name, %{triton brawler})
  insert(:name, %{triton fanatic})
  insert(:name, %{triton warden})
  insert(:name, %{triton warlock})
end

migrate :undead, :aggressive_npc do
  insert(:name, %{ethereal triton psionicist})
  insert(:name, %{spectral triton protector})
end

migrate :skin, :furrier do
  insert(:name, %{curved black claw})
  insert(:name, %{darkened triton hide})
  insert(:name, %{thick triton spine})
end
