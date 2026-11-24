migrate :box do
  delete(:noun, %{box})
  delete(:noun, %{chest})
  delete(:noun, %{coffer})
  delete(:noun, %{strongbox})
  delete(:noun, %{trunk})
  delete(:exclude, %{polished modwir box})

  create_key(:prefix)
  insert(:prefix, %{shifting})

  create_key(:name)
  insert(:name, %{(?:(?:acid-pitted|badly damaged|battered|corroded|dented|engraved|enruned|gem-encrusted|plain|scratched|sturdy) )?(?:brass|gold|iron|mithril|silver|steel) (?:box|chest|coffer|strongbox|trunk)})
  insert(:name, %{(?:(?:badly damaged|engraved|enruned|gem-encrusted|iron-bound|plain|rotting|scratched|simple|sturdy|weathered) )?(?:fel|haon|maoral|modwir|monir|tanik|thanot|wooden) (?:box|chest|coffer|strongbox|trunk)})
  insert(:name, %{(?:(?:austere|brass-inlaid|crude|gem-encrusted|gilded|ornate|scorched) )?(?:carved modwir|cracked|deeply-scored|deeply scored|delicate|red lacquered|stained) (?:box|chest|coffer|strongbox|trunk|case)})
end

# Exclude all boxes from uncommon
migrate :uncommon do
  insert(:exclude, %{(?:(?:shifting) )?(?:(?:acid-pitted|badly damaged|battered|corroded|dented|engraved|enruned|plain|scratched|sturdy) )?(?:brass|gold|iron|mithril|silver|steel) (?:box|chest|coffer|strongbox|trunk)})
  insert(:exclude, %{(?:(?:shifting) )?(?:(?:badly damaged|engraved|enruned|iron-bound|plain|rotting|scratched|simple|sturdy|weathered) )?(?:fel|haon|maoral|modwir|monir|tanik|thanot|wooden) (?:box|chest|coffer|strongbox|trunk)})
  insert(:exclude, %{(?:(?:shifting) )?(?:(?:austere|brass-inlaid|crude|gilded|ornate|scorched) )?(?:carved modwir|cracked|deeply-scored|deeply scored|delicate|red lacquered|stained) (?:box|chest|coffer|strongbox|trunk|case)})
end
