create_table "ascension:codex", keys: [:name]

migrate "ascension:codex" do
  insert(:name, %{marble-lined runic codex chiseled with cerulean runes})
  insert(:name, %{skin-bound runic codex tattooed with thick crimson ink})
end

migrate :aggressive_npc do
  insert(:name, %{battle-worn Empyrean captain})
  insert(:name, %{branded goliath diviner})
  insert(:name, %{burly goliath engineer})
  insert(:name, %{haze-shrouded goliath diviner})
  insert(:name, %{masked goliath plunderer})
  insert(:name, %{radiant-eyed goliath auramancer})
  insert(:name, %{tawny armor-clad pegasus})
end

migrate :skin, :furrier do
  insert(:name, %{(?:multihued )?pegasus mane})
end
