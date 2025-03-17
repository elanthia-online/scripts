migrate :aggressive_npc do
  insert(:name, %{azure-scaled cold wyrm})
  insert(:name, %{behemothic gorefrost golem})
  insert(:name, %{bloody halfling cannibal})
  insert(:name, %{brawny gigas shield-maiden})
  insert(:name, %{cinereous chthonian sybil})
  insert(:name, %{(?:colossal )?boreal undansormr})
  insert(:name, %{flayed gigas disciple})
  insert(:name, %{grim gigas skald})
  insert(:name, %{heavily armored battle mastodon})
  insert(:name, %{immense gold-bristled hinterboar})
  insert(:name, %{niveous giant warg})
  insert(:name, %{quivering sanguine ooze})
  insert(:name, %{quivering sanguine oozeling})
  insert(:name, %{savage fork-tongued wendigo})
  insert(:name, %{snowy warg packmother})
  insert(:name, %{squamous reptilian mutant})
  insert(:name, %{stunted halfling bloodspeaker})
  insert(:name, %{tattooed gigas berserker})
end

migrate :boon do
  insert(:exclude, %{tattooed gigas berserker})
end

migrate :undead, :aggressive_npc do
  insert(:name, %{(?:eyeless )?black valravn})
  insert(:name, %{(?:shining )?winged disir})
  insert(:name, %{(?:withered )?shadow-cloaked draugr})
end

migrate :undead, :aggressive_npc, :noncorporeal do
  insert(:name, %{(?:roiling )?crimson angargeist})
end

migrate :gem, :gemshop do
  insert(:name, %{blue lace agate})
  insert(:name, %{blue-violet chunk of kornerupine})
  insert(:name, %{bluish black razern-bloom})
  insert(:name, %{carved basalt teardrop})
  insert(:name, %{chunk of pale marble})
  insert(:name, %{chunk of ruddy bauxite})
  insert(:name, %{cylindrical red beryl})
  insert(:name, %{deep red-violet garnet})
  insert(:name, %{deep violet duskjewel})
  insert(:name, %{dull griseous mournstone})
  insert(:name, %{faceted stormcloud alexandrite})
  insert(:name, %{faceted wyrm's-heart sapphire})
  insert(:name, %{fossilized undandsormr egg})
  insert(:name, %{fossilized undansormr egg})
  insert(:name, %{frosted pale violet amethyst})
  insert(:name, %{gold-banded onyx})
  insert(:name, %{gold-green auroral emerald})
  insert(:name, %{green alexandrite stone})
  insert(:name, %{green and pink zoisite})
  insert(:name, %{grey-streaked malachite stone})
  insert(:name, %{inky black nightstone})
  insert(:name, %{lambent gold warg's eye quartz})
  insert(:name, %{lustrous vermilion firedrop})
  insert(:name, %{misty grey deathstone})
  insert(:name, %{mottled green jasper})
  insert(:name, %{nival everfrost shard})
  insert(:name, %{pastel-hued winterbite pearl})
  insert(:name, %{petrified warg fang})
  insert(:name, %{piece of blood amber})
  insert(:name, %{piece of clear oligoclase})
  insert(:name, %{piece of coppery titanite})
  insert(:name, %{piece of dusky blue sapphire})
  insert(:name, %{piece of polished ivory})
  insert(:name, %{rainbowed ammolite shard})
  insert(:name, %{rough cinnabar shard})
  insert(:name, %{royal blue boreal topaz})
  insert(:name, %{rutilated twilight tourmaline})
  insert(:name, %{saffron-hued danburite stone})
  insert(:name, %{shard of raven's wing obsidian})
  insert(:name, %{shard of streaked blue spectrolite})
  insert(:name, %{silver-hite palladium nugget})
  insert(:name, %{silvery nimbus opal})
  insert(:name, %{small flaxen citrine})
  insert(:name, %{smooth blue-green labradorite})
  insert(:name, %{some dark ivory aranthium-bloom})
  insert(:name, %{stark white snowstone})
  insert(:name, %{teal chrome diopside})
  insert(:name, %{twilight blue azurite crystal})
  insert(:name, %{vibrant titian heliodor})
  insert(:name, %{vinous gigasblood ruby})
  insert(:name, %{virescent nephrite shard})
  insert(:name, %{vivid cobalt blue spinel})
end

migrate :skin, :furrier do
  insert(:name, %{(?:niveous )?warg pelt})
  insert(:name, %{(?:golden )?hinterboar mane})
  insert(:name, %{(?:inky black )?valravn plume})
  insert(:name, %{(?:handful of )?undansormr scales})
  insert(:name, %{(?:woolly )?mastodon trunk})
end

migrate :gemshop, :valuable do
  insert(:name, %{fossilized rolton tooth})
  insert(:name, %{swirling silver globe})
end

migrate :uncommon do
  insert(:name, %{stygian valravn quill})
  insert(:name, %{nacreous disir feather})
  insert(:exclude, %{bluish black razern-bloom})
  insert(:exclude, %{faceted stormcloud alexandrite})
  insert(:exclude, %{shard of glossy black obsidian})
  insert(:exclude, %{shard of raven's wing obsidian})
end

migrate :valuable do
  insert(:exclude, %{silver-hite palladium nugget})
end

migrate :magic, :pawnshop do
  insert(:exclude, %{twilight blue azurite crystal})
end
