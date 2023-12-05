# The Hive, a post-cap hunting area in Zul Logoth, gameobj-data.xml additions.

migrate :aggressive_npc do
  insert(:name, %{chitinous kiramon myrmidon})
  insert(:name, %{corpulent kresh ravager})
  insert(:name, %{disfigured hive thrall})
  insert(:name, %{iridescent kiramon shardmind})
  insert(:name, %{sleek black kiramon stalker})
  insert(:name, %{translucent kiramon strandweaver})
end

=begin
Additional migrations to be added.
migrate :gem, :gemshop do
  insert(:name, %{virescent nephrite shard})
end

migrate :skin, :furrier do
  insert(:name, %{(?:niveous )?warg pelt})
  insert(:name, %{(?:golden )?hinterboar mane})
  insert(:name, %{(?:inky black )?valravn plume})
  insert(:name, %{(?:handful of )?undansormr scales})
  insert(:name, %{(?:woolly )?mastodon trunk})
end

migrate :uncommon do
  insert(:name, %{stygian valravn quill})
  insert(:name, %{nacreous disir feather})
end
=end
