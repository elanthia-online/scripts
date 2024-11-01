migrate :aggressive_npc do
  insert(:name, %{shan bard})
  insert(:name, %{shan bardess})
  insert(:name, %{shan empath})
  insert(:name, %{shan rogue})
  insert(:name, %{shan shaman})
  insert(:name, %{shan sorcerer})
  insert(:name, %{shan sorceress})
end

migrate :valuable, :gemshop do
  insert(:name, %{scintillating fishscale})
end
