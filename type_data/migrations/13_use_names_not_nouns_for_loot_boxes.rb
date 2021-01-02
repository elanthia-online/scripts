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
  insert(:name, %{(?:(?:acid-pitted|badly damaged|battered|corroded|dented|engraved|enruned|plain|scratched|sturdy) )?(?:brass|gold|iron|mithril|silver|steel) (?:box|chest|coffer|strongbox|trunk)})
  insert(:name, %{(?:(?:badly damaged|engraved|enruned|iron-bound|plain|rotting|scratched|simple|sturdy|weathered) )?(?:fel|haon|maoral|modwir|monir|tanik|thanot|wooden) (?:box|chest|coffer|strongbox|trunk)})
  #short
  insert(:name, %{(?:carved modwir|cracked|deeply-scored|delicate|red lacquered|stained) (?:box|chest|coffer|strongbox|trunk|case)})
  #long
  insert(:name, %{(?:austere|brass-inlaid|crude|gilded|ornate|scorched) (?:carved modwir|cracked|deeply-scored|delicate|red lacquered|stained) (?:box|chest|coffer|strongbox|trunk|case) (?:covered with tiny worm holes|decorated with bits of colorful glass|engraved with the image of a pile of gems|held together with ragged iron straps|painted with a resplendent sun on the top|swathed in rust-red symbols|with a broken and rusted chain attached|with frayed ropes for handles|with tiny clawed feet|wrapped in red silk|wrapped in green silk|wrapped in black silk)})
end

migrate :uncommon do
  create_key(:prefix)
  insert(:prefix, %{shifting})

  insert(:exclude, %{(?:(?:badly damaged|engraved|enruned|iron-bound|plain|rotting|scratched|simple|sturdy|weathered) )?(?:modwir) (?:box|chest|coffer|strongbox|trunk)})
  insert(:exclude, %{(?:carved modwir) (?:box|chest|coffer|strongbox|trunk|case)})
  insert(:exclude, %{(?:austere|brass-inlaid|crude|gilded|ornate|scorched) (?:carved modwir) (?:box|chest|coffer|strongbox|trunk|case) (?:covered with tiny worm holes|decorated with bits of colorful glass|engraved with the image of a pile of gems|held together with ragged iron straps|painted with a resplendent sun on the top|swathed in rust-red symbols|with a broken and rusted chain attached|with frayed ropes for handles|with tiny clawed feet|wrapped in red silk|wrapped in green silk|wrapped in black silk)})
end
