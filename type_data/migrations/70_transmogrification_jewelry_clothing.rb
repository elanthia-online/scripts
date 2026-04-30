migrate :gemshop, :pawnshop, :jewelry do
  insert(:noun, %{armbands?})
  insert(:noun, %{armlets?})
  insert(:noun, %{bangle})
  insert(:noun, %{beads?})
  insert(:noun, %{bracers?})
  insert(:noun, %{collar})
  insert(:noun, %{comb})
  insert(:noun, %{corsage})
  insert(:noun, %{choker})
  insert(:noun, %{ear studs?})
  insert(:noun, %{fichu})
  insert(:noun, %{hairclip})
  insert(:noun, %{hairpin})
  insert(:noun, %{hairsticks?})
  insert(:noun, %{necklet})
  insert(:noun, %{pectoral})
  insert(:noun, %{studs?})
  insert(:noun, %{wristlet})
end

migrate :pawnshop, :clothing do
  insert(:noun, %{buskins})
  # insert(:noun, %{case}) # conflicts with base "box" type
  insert(:noun, %{cinch})
  insert(:noun, %{clogs})
  insert(:noun, %{coif})
  insert(:noun, %{cowl})
  insert(:noun, %{gauntlets?})
  insert(:noun, %{jerkin})
  insert(:noun, %{haversack})
  insert(:noun, %{singlet})
  insert(:noun, %{shift})
  insert(:noun, %{smock})
  insert(:noun, %{tam'o'shanter})
end

migrate :gemshop, :jewelry do
  insert(:noun, %{periapt})
  insert(:exclude, %{small bone periapt})
end
