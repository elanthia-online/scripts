#Moonsedge Creatures
migrate :undead, :aggressive_npc do
  insert(:name, %{ashen patrician vampire})
  insert(:name, %{cadaverous tatterdemalion ghast})
  insert(:name, %{horned basalt grotesque})
  insert(:name, %{infernal death knight})
  insert(:name, %{smouldering skeletal dreadsteed})
end

migrate :undead, :aggressive_npc,:noncorporeal do
  insert(:name, %{flickering mist-wreathed banshee})
  insert(:name, %{gaudy phantasmic conjurer})
end

migrate :boon do
  insert(:exclude, %{flickering mist-wreathed banshee})
end

migrate :skin, :furrier do
  create_key(:exclude)
  
  insert(:name, %{flame-scarred dreadsteed skull})
  insert(:name, %{dreadsteed skull})
  insert(:exclude, %{dreadsteed skull})
  insert(:exclude, %{bundle of flame-scarred dreadsteed skull})
end

#Crawling Shore Creatures
migrate :aggressive_npc do
  insert(:name, %{bony Tenthsworn occultist})
  insert(:name, %{desiccated half-krolvin strigoi})
  insert(:name, %{gaunt feral selkie})
  insert(:name, %{grisly corpse hulk})
end
