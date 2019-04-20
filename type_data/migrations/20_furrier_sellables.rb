##
## these items are sell for the most at the Furrier
## but are not a result of the `skin` verb
##
## issue: https://github.com/elanthia-online/scripts/issues/129
##
migrate :furrier do
  insert(:name, %[waxy grey caederine])
  insert(:name, %[ant larva])
  insert(:name, %[scintillating fishscale])
  insert(:name, %[lump of black ambergris])
  insert(:name, %[lump of grey ambergris])
end