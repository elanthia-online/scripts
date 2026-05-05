migrate :gemshop, :pawnshop, :jewelry do
  insert(:noun, %{armbands?})
  insert(:noun, %{armlets?})
  insert(:noun, %{armwraps?})
  insert(:noun, %{bangle})
  insert(:noun, %{beads?})
  insert(:noun, %{bracers?})
  insert(:noun, %{carcanet})
  insert(:noun, %{collar})
  insert(:noun, %{comb})
  insert(:noun, %{corsage})
  insert(:noun, %{choker})
  insert(:noun, %{ear studs?})
  insert(:noun, %{fichu})
  insert(:noun, %{garland})
  insert(:noun, %{hairclip})
  insert(:noun, %{hairpin})
  insert(:noun, %{hairsticks?})
  insert(:noun, %{locket})
  insert(:noun, %{necklet})
  insert(:noun, %{pectoral})
  insert(:noun, %{studs?})
  insert(:noun, %{wristlet})
end

migrate :pawnshop, :clothing do
  insert(:noun, %{buskins})
  insert(:noun, %{case})
  insert(:noun, %{cassock})
  insert(:noun, %{cinch})
  insert(:noun, %{cinture})
  insert(:noun, %{clogs})
  insert(:noun, %{coif})
  insert(:noun, %{cowl})
  insert(:noun, %{gauntlets})
  insert(:noun, %{jerkin})
  insert(:noun, %{haversack})
  insert(:noun, %{sabots})
  insert(:noun, %{singlet})
  insert(:noun, %{shift})
  insert(:noun, %{smock})
  insert(:noun, %{soutane})
  insert(:noun, %{tam'o'shanter})
  insert(:noun, %{tricorne})
end

migrate :gemshop, :jewelry do
  insert(:noun, %{periapt})
  insert(:exclude, %{small bone periapt})
end

migrate :clothing do
  insert(:exclude, %{(?:(?:shifting) )?(?:(?:acid-pitted|austere|badly damaged|banded|battered|blackened|brass-inlaid|charred|copper-edged|copper-trimmed|corroded|crude|dented|engraved|enruned|fluted|gilded|gold-trimmed|iron-bound|jeweled|lacquered|ornate|painted|plain|riveted|rotting|rusted|rune-incised|scarred|scorched|scratched|scuffed|simple|singed|sturdy|waterlogged|weathered) )?(?:brass|bronze|carved modwir|cedar|cherrywood|cooper|copper|cracked|deeply-scored|deeply scored|delicate|fel|gold|haon|hickory|iron|mahogany|maple|maoral|mithril|modwir|monir|red lacquered|silver|stained|steel|tanik|thanot|walnut|white oak|wooden) (?:box|case|chest|coffer|strongbox|trunk)})
end
