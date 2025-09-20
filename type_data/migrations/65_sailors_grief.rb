migrate :aggressive_npc do
  insert(:name, %{(?:algae-draped )?merrow oracle})
  insert(:name, %{(?:amaranthine )?kraken tentacle})
  insert(:name, %{(?:blubbery )?humpbacked merrow})
  insert(:name, %{(?:brackish )?bilge mass})
  insert(:name, %{(?:fulminating )?stormborn primordial})
  insert(:name, %{(?:gigantic )?lightning whelk})
  insert(:name, %{(?:grey-plumed )?steelwing harpy})
  insert(:name, %{(?:hapless )?charmed corsair})
  insert(:name, %{(?:kelp-tangled )?coral golem})
  insert(:name, %{(?:scaly )?needle-toothed trenchling})
end

migrate :undead, :aggressive_npc do
  insert(:name, %{(?:garish )?revenant buccaneer})
  insert(:name, %{(?:milky-eyed )?drowned mariner})
  insert(:name, %{(?:pallid )?fog-cloaked kelpie})
end

migrate :undead, :aggressive_npc, :noncorporeal do
  insert(:name, %{(?:tenebrific )?wraith shark})
end

migrate :gem, :gemshop do
  insert(:name, %{asymmetrical rough grey pearl})
  insert(:name, %{banana yellow citrine})
  insert(:name, %{banded mauve sugar stone})
  insert(:name, %{blue-veined volcanic obsidian})
  insert(:name, %{blue-whorled greenish ocean jasper})
  insert(:name, %{cabochon of striated grape jade})
  insert(:name, %{chunk of indigo seaglass})
  insert(:name, %{clouded cream orange pearl})
  insert(:name, %{copper-veined royal azel})
  insert(:name, %{cracked shell-infused geode})
  insert(:name, %{deep blue tide's heart opal})
  insert(:name, %{dusky grey storm alexandrite})
  insert(:name, %{ebon-washed carnelian red ammolite})
  insert(:name, %{faint blue water sapphire})
  insert(:name, %{fiery gold-flecked sunstone})
  insert(:name, %{gold-dappled olive peridot})
  insert(:name, %{grey-green mist emerald})
  insert(:name, %{indigo seastone orb})
  insert(:name, %{metallic chunk of galena})
  insert(:name, %{mottled algae chalcedony})
  insert(:name, %{plum-flecked ruby zoisite})
  insert(:name, %{porous oily black stone})
  insert(:name, %{rosette rhodonite block})
  insert(:name, %{sanguine pyrope teardrop})
  insert(:name, %{scaled indigo ammolite})
  insert(:name, %{smooth dolphin stone disc})
  insert(:name, %{tiny cut ametrine})
  insert(:name, %{uncut sanguine pyrope})
  insert(:name, %{vibrant ocean jasper cabochon})
  insert(:name, %{volcanic blue larimar stone})
  insert(:name, %{whorled jungle malachite})
end

migrate :skin, :furrier do
  insert(:name, %{(?:iridescent )?whelk shell fragment})
  insert(:name, %{needle-thin trenchling tooth})
  insert(:name, %{trenchling teeth})
  insert(:name, %{(?:metallic )?harpy feather})
end
