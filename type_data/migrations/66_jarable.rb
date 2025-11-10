create_table "jarable", keys: [:name, :noun, :exclude]

migrate "jarable" do
  insert(:name, %{amethyst clam shell})
  insert(:name, %{angulate wentletrap shell})
  insert(:name, %{beige clam shell})
  insert(:name, %{black-spined conch shell})
  insert(:name, %{blue-banded coquina shell})
  insert(:name, %{bright noble pectin shell})
  insert(:name, %{blue periwinkle shell})
  insert(:name, %{candystick tellin shell})
  insert(:name, %{checkered chiton shell})
  insert(:name, %{crown conch shell})
  insert(:name, %{crown-of-Charl shell})
  insert(:name, %{dovesnail shell})
  insert(:name, %{egg cowrie shell})
  insert(:name, %{fluted limpet shell})
  insert(:name, %{golden cowrie shell})
  insert(:name, %{polished hornsnail shell})
  insert(:name, %{piece of iridescent mother-of-pearl})
  insert(:name, %{large chipped clam shell})
  insert(:name, %{large moonsnail shell})
  insert(:name, %{lavender nassa shell})
  insert(:name, %{leopard cowrie shell})
  insert(:name, %{lynx cowrie shell})
  insert(:name, %{marlin spike shell})
  insert(:name, %{multi-colored snail shell})
  insert(:name, %{opaque spiral shell})
  insert(:name, %{pearl nautilus shell})
  insert(:name, %{pink-banded coquina shell})
  insert(:name, %{pink clam shell})
  insert(:name, %{polished batwing chiton shell})
  insert(:name, %{polished black tegula shell})
  insert(:name, %{purple-cap cowrie shell})
  insert(:name, %{ruby-lined nassa shell})
  insert(:name, %{sea urchin shell})
  insert(:name, %{silvery clam shell})
  insert(:name, %{snake-head cowrie shell})
  insert(:name, %{snow cowrie shell})
  insert(:name, %{Solhaven Bay scallop shell})
  insert(:name, %{sparkling silvery conch shell})
  insert(:name, %{speckled conch shell})
  insert(:name, %{spiny siren's-comb shell})
  insert(:name, %{spiral turret shell})
  insert(:name, %{striated abalone shell})
  insert(:name, %{sundial shell})
  insert(:name, %{three-lined nassa shell})
  insert(:name, %{tiger cowrie shell})
  insert(:name, %{tiger-striped nautilus shell})
  insert(:name, %{translucent golden spiral shell})
  insert(:name, %{yellow-banded coquina shell})
  insert(:name, %{white clam shell})
  insert(:name, %{white gryphon's wing shell})

  gem_table = get_table("gem")
  gem_names = gem_table.get_rules(:name)
  get_nouns = gem_table.get_rules(:noun)
  get_excludes = gem_table.get_rules(:exclude)

  gem_names.each do |gem_name|
    insert(:name, gem_name)
  end

  gem_names.each do |gem_name|
    insert(:noun, gem_name)
  end  

  gem_names.each do |gem_name|
    insert(:exclude, gem_name)
  end  
end
