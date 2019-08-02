# https://github.com/elanthia-online/scripts/issues/91
# https://github.com/elanthia-online/scripts/issues/90
# https://github.com/elanthia-online/scripts/issues/87

migrate :skin do
  insert(:name, "ruff of raptor feathers")
  insert(:name, "centaur ranger hide")
end

migrate :furrier do
  insert(:name, "centaur ranger hide")
  insert(:name, "ruff of raptor feathers")
  insert(:name, "scintillating fishscale")
  insert(:name, "lump of black ambergris")
  insert(:name, "lump of grey ambergris")
end