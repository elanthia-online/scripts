# The Hive, a post-cap hunting area in Zul Logoth, gameobj-data.xml additions.

migrate :aggressive_npc do
  insert(:name, %{bloated kiramon broodtender})
  insert(:name, %{chitinous kiramon myrmidon})
  insert(:name, %{corpulent kresh ravager})
  insert(:name, %{disfigured hive thrall})
  insert(:name, %{iridescent kiramon shardmind})
  insert(:name, %{sleek black kiramon stalker})
  insert(:name, %{translucent kiramon strandweaver})
end

migrate :skin, :furrier do
  insert(:name, %{(?:glittering )?kresh foreclaw})     # from corpulent kresh ravager
  insert(:name, %{(?:some glossy )?kiramon chitin})    # from chitinous kiramon myrmidon
  insert(:name, %{(?:mottled )?kiramon poison gland})  # from sleek black kiramon stalker
  insert(:name, %{(?:pallid )?strandweaver spinneret}) # from translucent kiramon strandweaver
  insert(:name, %{(?:thin )?broodtender tendril})      # from bloated kiramon broodtender
end

migrate :gem, :gemshop do
  insert(:name, %{fragment of pale green-blue aquamarine})
  insert(:name, %{lilac-crested molten gold ametrine})
  insert(:name, %{pear-shaped greenish[\s\-]yellow citrine})
end

migrate :breakable, :valuable do
  insert(:name, %{porous chunk of rock})
end
