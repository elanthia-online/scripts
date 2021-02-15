migrate :aggressive_npc, :undead do
  insert(:name, %{seething pestilent vision})
  insert(:name, %{horrific magna vereri})
  insert(:name, %{voluptuous magna vereri})
end

migrate :aggressive_npc do
  insert(:name, %{athletic dark-eyed incubus})
  insert(:name, %{supple Ivasian inciter})
end
