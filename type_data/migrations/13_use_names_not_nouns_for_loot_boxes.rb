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
end
