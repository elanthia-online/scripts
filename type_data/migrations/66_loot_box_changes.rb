migrate :box do
  create_key(:name)
  insert(:name, %{((?:gold-trimmed|copper-(?:edged|trimmed)|rune-incised|badly damaged|corroded|iron-bound|waterlogged|rusted|weathered|engraved|simple|blackened|lacquered|scratched|battered|riveted|enruned|charred|painted|rotting|scuffed|jeweled|scarred|ornate|singed|fluted|banded|sturdy|plain) )?(?:cherrywood|white oak|mahogany|hickory|bronze|modwir|walnut|silver|mithril|maoral|cooper|wooden|cedar|maple|steel|haon|thanot|monir|tanik|brass|iron|gold|fel) (?:strongbox|coffer|chest|trunk|box)})
end

migrate :uncommon do
  insert(:exclude, %{((?:gold-trimmed|copper-(?:edged|trimmed)|rune-incised|badly damaged|corroded|iron-bound|waterlogged|rusted|weathered|engraved|simple|blackened|lacquered|scratched|battered|riveted|enruned|charred|painted|rotting|scuffed|jeweled|scarred|ornate|singed|fluted|banded|sturdy|plain) )?(?:cherrywood|white oak|mahogany|hickory|bronze|modwir|walnut|silver|mithril|maoral|cooper|wooden|cedar|maple|steel|haon|thanot|monir|tanik|brass|iron|gold|fel) (?:strongbox|coffer|chest|trunk|box)})
end

migrate :valuable, :gemshop do
  insert(:name, %{bright gold ingot})
end
