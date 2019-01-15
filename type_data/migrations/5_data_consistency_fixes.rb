migrate :aggressive_npc do
  insert(:name, "Agresh bear")
  insert(:name, "Agresh troll chieftain")
  insert(:name, "Agresh troll scout")
  insert(:name, "Agresh troll warrior")
  insert(:name, "Arachne acolyte")
  insert(:name, "Arachne priest")
  insert(:name, "Arachne priestess")
  insert(:name, "Arachne servant")
  insert(:name, "frostborne lich")
  insert(:name, "Grutik savage")
  insert(:name, "Grutik shaman")
  insert(:name, "infernal lich")
  insert(:name, "murky soul siphon")
  insert(:name, "Neartofar troll")
  insert(:name, "necrotic snake")
  insert(:name, "spectre")
  insert(:name, "wild dog")
end

migrate :undead do
  insert(:name, "spectre")
end
