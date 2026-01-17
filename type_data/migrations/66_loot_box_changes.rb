migrate :box do
  create_key(:name)
  insert(:name, %{(?:gold-trimmed|copper-(?:edged|trimmed)|rune-incised|waterlogged|blackened|lacquered|scratched|battered|riveted|enruned|charred|painted|rotting|scuffed|jeweled|scarred|ornate|singed|fluted|banded|sturdy|plain )?(?:cherrywood|white oak|mahogany|hickory|bronze|modwir|walnut|silver|maoral|cooper|wooden|cedar|maple|steel|thanot|monir|tanik|brass|iron|gold|fel) (?:strongbox|coffer|chest|trunk|box)})
end

migrate :uncommon do
  insert(:exclude, %{(?:gold-trimmed|copper-(?:edged|trimmed)|rune-incised|waterlogged|blackened|lacquered|scratched|battered|riveted|enruned|charred|painted|rotting|scuffed|jeweled|scarred|ornate|singed|fluted|banded|sturdy|plain )?(?:cherrywood|white oak|mahogany|hickory|bronze|modwir|walnut|silver|maoral|cooper|wooden|cedar|maple|steel|thanot|monir|tanik|brass|iron|gold|fel) (?:strongbox|coffer|chest|trunk|box)})
end
