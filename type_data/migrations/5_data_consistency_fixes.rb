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

migrate :gem do
  delete(:noun, %{soulstone})
  insert(:name, %{fiery viridian soulstone})
  insert(:name, %{dull white soulstone})
  insert(:name, %{cinnabar crystal})
  insert(:name, %{silvery galena})
end

migrate :reagent, :consignment do
  insert(:name, %{cluster of ayanad crystals})
  insert(:name, %{cluster of s'ayanad crystals})
  insert(:name, %{cluster of t'ayanad crystals})
  insert(:name, %{cracked soulstone})
end

migrate :consignment do
  insert(:name, %{swirling grey potion})
end

migrate :gemshop do
  insert(:name, %{thin-rayed black diamond starburst})
  insert(:name, %{urglaes fang})
  insert(:name, %{cinnabar crystal})
  insert(:name, %{silvery galena})

  insert(:noun, %{plinite})
end

migrate :uncommon do
  insert(:exclude, %{princess-cut alexandrite stone})
end

migrate :pawnshop do
  insert(:exclude, %{shard of dragonmist crystal})
  insert(:exclude, %{cinnabar crystal})
  insert(:exclude, %{chalky yellow cube})
  insert(:exclude, %{(?:scratched|corroded|polished|shiny|tarnished|dented|rusty|bent) (?:ring|medallion|earring|anklet|bracelet|fork|plate|coin|cup|nail|spoon|doorknob|horseshoe)$})
  insert(:exclude, %{steel shield})
  insert(:exclude, %{scratched steel helm})
end

migrate :magic do
  insert(:exclude, %{cinnabar crystal})
end

migrate :food do
  insert(:exclude, %{flower-shaped tart})
  insert(:exclude, %{musk ox tart})
end
