migrate :note do
  delete(:name, %{.+ promissory note})
end

migrate :note do
  insert(:name, %{salt-stained kraken chit})
  insert(:name, %{Northwatch bond note})
  insert(:name, %{Icemule promissory note})
  insert(:name, %{Borthuum Mining Company scrip})
  insert(:name, %{Wehnimer's promissory note})
  insert(:name, %{Torren promissory note})
  insert(:name, %{City-States promissory note})
  insert(:name, %{Vornavis promissory note})
  insert(:name, %{Mist Harbor promissory note})

  # various event box reward notes
  insert(:name, %{bloodstained promissory note})
  insert(:name, %{damp promissory note})
  insert(:name, %{dirty promissory note})
  insert(:name, %{old promissory note})
  insert(:name, %{smudged promissory note})
  insert(:name, %{stained promissory note})
end
