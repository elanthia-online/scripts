# Moonsedge Creatures
migrate :undead, :aggressive_npc do
  insert(:name, %{ashen patrician vampire})
  insert(:name, %{cadaverous tatterdemalion ghast})
  insert(:name, %{horned basalt grotesque})
  insert(:name, %{infernal death knight})
  insert(:name, %{smouldering skeletal dreadsteed})
end

migrate :undead, :aggressive_npc, :noncorporeal do
  insert(:name, %{flickering mist-wreathed banshee})
  insert(:name, %{gaudy phantasmic conjurer})
end

migrate :boon do
  insert(:exclude, %{flickering mist-wreathed banshee})
end

migrate :skin, :furrier do
  insert(:name, %{(?:flame-scarred )?dreadsteed skull})
end

# Crawling Shore Creatures
migrate :aggressive_npc do
  insert(:name, %{bony Tenthsworn occultist})
  insert(:name, %{desiccated half-krolvin strigoi})
  insert(:name, %{gaunt feral selkie})
  insert(:name, %{grisly corpse hulk})
end

migrate :gem, :gemshop do
  insert(:name, %{cabochon torchlight carnelian})
  insert(:name, %{chatoyant cerulean chrysoberyl})
  insert(:name, %{copper-chased azurite chunk})
  insert(:name, %{blue-green glacial core})
  insert(:name, %{pinch of electrum dust})
  insert(:name, %{fragment of pale blue glacialite})
  insert(:name, %{swirling quicksilver globe})
  insert(:name, %{clear azure hoarstone})
  insert(:name, %{stygian lichstone})
  insert(:name, %{jagged nephrite shard})
  insert(:name, %{niveous snowdrop})
  insert(:name, %{disk of petrified spruce})
end
