migrate :ebongate, :gem, :gemshop do
  insert(:name, %{branch of petrified driftwood})
  insert(:name, %{grooved burnt orange sea star})
  insert(:name, %{misty silver crystalline spiral})
  insert(:name, %{piece of petrified wyrmwood})
  insert(:name, %{wedge of ocher and ebony ambergris})
  insert(:name, %{cabochon of milky azure aquamarine})
  insert(:name, %{thin blade of verdant sea glass})
  insert(:name, %{triangular charcoal shark tooth})
  insert(:name, %{sickle-shaped opaque white soulstone})
end

migrate :gemshop do
  insert(:name, %{blackened feystone core})
  insert(:name, %{dark grey dreamstone fragment})
  insert(:name, %{fossilized thrak tooth})
  insert(:name, %{shard of pale grey shadowglass})
end

migrate :ebongate do
  insert(:name, %{limpid dark indigo tidal pearl})
  insert(:name, %{prismatic rose-gold fire agate})
  insert(:name, %{radiant lush viridian star emerald})
  insert(:name, %{rich cerulean mermaid's-tear sapphire})
  insert(:name, %{spiny fan of lustrous black coral})
  insert(:name, %{stellular dragon's-tear diamond})
  insert(:name, %{teardrop of murky sanguine ruby})
  insert(:name, %{honey-washed violet water sapphire})
  insert(:name, %{ebon-cored ruddy almandine garnet})
  insert(:name, %{five-pointed seafoam white sandsilver})

  insert(:name, %{eel-etched raffle token})
  insert(:name, %{short-handled rusted steel shovel})
  insert(:name, %{some indigo-black seashells})
end

migrate :valuable do
  insert(:exclude,  %{burnished sepia moonsnail shell})
  insert(:exclude,  %{pale-spotted rosy sea urchin shell})
  insert(:exclude,  %{purple-banded razor clam shell})
  insert(:exclude,  %{rainbow-hued oval abalone shell})
  insert(:exclude,  %{rust-speckled ivory slipper shell})
  insert(:exclude,  %{wine-tinged calico scallop shell})
end

migrate :ebongate, :gem do
  insert(:name,  %{burnished sepia moonsnail shell})
  insert(:name,  %{pale-spotted rosy sea urchin shell})
  insert(:name,  %{purple-banded razor clam shell})
  insert(:name,  %{rainbow-hued oval abalone shell})
  insert(:name,  %{rust-speckled ivory slipper shell})
  insert(:name,  %{wine-tinged calico scallop shell})
end

migrate :gem do
  insert(:name,  %{rough-edged matte white soulstone})

end


migrate :ebongate, :quest do
  insert(:name, %{smooth grey boulder})
  insert(:name, %{tiny blue mosaic tile})
  insert(:name, %{waterproof sack})
  insert(:name, %{waterproof bag})
  insert(:name, %{tumbled grey stone})
  insert(:name, %{rough piece of driftwood})
  insert(:name, %{forged horseshoe nail})
  insert(:name, %{rough oak post})
  insert(:name, %{fistful of iron nails})
  insert(:name, %{smooth wooden plank})
  insert(:name, %{square of thin grey shale})
  insert(:name, %{bright red mosaic tile})
  insert(:name, %{small vial})
  insert(:name, %{bluish grey slate tile})
  insert(:name, %{painted wood casing})
  insert(:name, %{warped wooden door})
  insert(:name, %{smooth glaesine window pane})
  insert(:name, %{blocky pine beam})
  insert(:name, %{oak-handled diorite chisel})
  insert(:name, %{porous lava block})
  insert(:name, %{some indigo and silver tiles})
  insert(:name, %{some green and white tiles})
  insert(:name, %{small eel-carved stone})
end

migrate :gem, :gemshop do
  insert(:exclude, %{tumbled grey stone})
  insert(:exclude, %{small eel-carved stone})
end

migrate :clothing, :pawnshop do
  insert(:exclude, %{waterproof sack})
  insert(:exclude, %{waterproof bag})
end

migrate :junk, :magic do
  create_key(:prefix)
  insert(:prefix, %{bent})
  insert(:prefix, %{dirt-caked})
  insert(:prefix, %{dirty})
  insert(:prefix, %{encrusted})
  insert(:prefix, %{gritty})
  insert(:prefix, %{marred})
  insert(:prefix, %{misshapen})
  insert(:prefix, %{murky})
  insert(:prefix, %{sand-caked})
  insert(:prefix, %{scorched})
  insert(:prefix, %{slimy})
end

migrate :junk do
  insert(:name, %r{iron doorknob})
  insert(:name, %r{iron horseshoe})
  insert(:name, %r{stone brick})
  insert(:name, %r{table leg})
end

migrate :jewelry, :gemshop do
  insert(:exclude, %{gritty crystal amulet})
  insert(:exclude, %{dirt-caked crystal amulet})
end

migrate :ebongate, :quest do
  insert(:name, %{pair of dark tin species})
  insert(:name, %{pair of dented pewter species})
  insert(:name, %{pair of scratched gold species})
  insert(:name, %{pair of tarnished steel species})
  insert(:name, %{pair of thin copper species})
end
