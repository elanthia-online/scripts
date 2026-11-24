create_table "simucoin:regular", keys: [:name]
create_table "simucoin:briarmooncove", keys: [:name]
create_table "simucoin:deliriummanor", keys: [:name]
create_table "simucoin:duskruin", keys: [:name]
create_table "simucoin:rumorwoods", keys: [:name]
create_table "simucoin:ebongate", keys: [:name]
create_table "simucoin:reim", keys: [:name]
create_table "simucoin:f2p", keys: [:name]

migrate "simucoin:regular" do
  insert(:name, %{Adventurer's Guild task waiver})                                 # 30 day Adventurer's Guild Task Waiver
  insert(:name, %{Adventurer's Guild voucher pack})                                # Adventurer's Guild Bounty Task Vouchers
  insert(:name, %{brown-flecked dark green potion})                                # Animal Companion Reset
  insert(:name, %{gleaming shard of reflective soulstone})                         # ATTUNEMENT Reset
  insert(:name, %{silver transfer form})                                           # Bank - Crossrealm Silver Transfer
  insert(:name, %{bright orange potion})                                           # Character Age Reset Potion
  insert(:name, %{birth certificate parchment})                                    # Character Birthday Adjustment Parchment
  insert(:name, %{cultural registration document})                                 # Character Culture Reset
  insert(:name, %{brass and gold sphere})                                          # Chronomage transport sphere
  insert(:name, %{Chronomage rush ticket})                                         # Chronomage Rush Ticket
  insert(:name, %{squat jar of pallid grey salve})                                 # Death's Sting Salve
  insert(:name, %{blue feather-shaped charm})                                      # Encumbrance Charm (6 sips)
  insert(:name, %{silvery blue potion})                                            # Encumbrance Potion (1 sip) 30 days
  insert(:name, %{flexing arm token})                                              # Enhancive Pauses (60 uses)
  insert(:name, %{notched flexing arm token})                                      # Enhancive Pauses (30 days)
  insert(:name, %{swirling yellow-green potion})                                   # Enhancive Recharger (long-term) 30 days
  insert(:name, %{churning yellow-green potion})                                   # Enhancive Recharger (long-term) 360 days
  insert(:name, %{twisting blue-green potion})                                     # Enhancive Recharger (short-term) 30 minutes
  insert(:name, %{potent yellow-green potion})                                     # Enhancive Spell Knowledge Recharger (long-term) 30 days
  insert(:name, %{vigorous yellow-green potion})                                   # Enhancive Spell Knowledge Recharger (long-term) 360 days
  insert(:name, %{potent blue-green potion})                                       # Enhancive Spell Knowledge Recharger (short-term) 30 minutes
  insert(:name, %{dark blue potion})                                               # Fixskills Potion
  insert(:name, %{hazy green potion})                                              # Fixstat Potion
  insert(:name, %{sun-etched gold ring})                                           # Gold Ring - Unnavvable (30 days)
  insert(:name, %{enruned gold ring})                                              # Gold Ring - Unnavvable (60 uses)
  insert(:name, %{locker expansion contract})                                      # Locker - additional permanent slots
  insert(:name, %{larger locker contract})                                         # Locker Capacity Boost (30 days)
  insert(:name, %{locker manifest contract})                                       # Locker Manifest
  insert(:name, %{locker runner contract})                                         # Locker Runner Contract
  insert(:name, %{deluxe locker contract})                                         # Locker - Multirealm
  insert(:name, %{stability contract})                                             # Login Reward Bridges (5)
  insert(:name, %{Lumnis schedule})                                                # Login Reward Lumnis Schedule
  insert(:name, %{Elanthian Guilds voucher pack})                                  # Profession Guild Task Vouchers
  insert(:name, %{Elanthian Guild Night form})                                     # Profession Guild Guild Night Form
  insert(:name, %{amnesty parchment})                                              # Society Transfer Form
  insert(:name, %{shimmering spell token})                                         # Spell Receiving Pass
  insert(:name, %{squat pale grey crystal bottle})                                 # Spell Up Pills (10)
  insert(:name, %{squat pale blue crystal bottle})                                 # Spell Up Pills (100)
  insert(:name, %{urchin guide contract})                                          # Urchin Guide Contract
  insert(:name, %{blown glass vial of magenta liquid spiral-wrapped by gold wire}) # Polymorph Potion: Gender
  insert(:name, %{round-bellied glass cruet of fizzy heliotrope liquid})           # Polymorph Potion: Name
  insert(:name, %{square crystal flacon filled with bubbling vermilion liquid})    # Polymorph Potion: Race
  insert(:name, %{gold-bound pellucid glass phial filled with carmine liquid})     # Polymorph Potion: Profession
  insert(:name, %{pale grey property deed})                                        # Customized Private Property - 6 rooms
end

migrate "simucoin:briarmooncove" do
  insert(:name, %{Briarmoon Cove entry orb}) # Briarmoon Cove - 1 entry orb
end

migrate "simucoin:deliriummanor" do
  insert(:name, %{vellum invitational pass})        # Delirium Manor - 1 entry
  insert(:name, %{scallop-edged invitational pass}) # Delirium Manor - 10 entries
  insert(:name, %{silvery invitational pass})       # Delirium Manor - 25 entries
  insert(:name, %{gold leaf invitational pass})     # Delirium Manor - 50 entries
end

migrate "simucoin:duskruin" do
  insert(:name, %{parchment stamped voucher})        # Duskruin Arena - 1 voucher
  insert(:name, %{bronze stamped voucher booklet})   # Duskruin Arena - 10 vouchers
  insert(:name, %{silver stamped voucher booklet})   # Duskruin Arena - 25 vouchers
  insert(:name, %{gold stamped voucher booklet})     # Duskruin Arena - 150 vouchers
  insert(:name, %{platinum stamped voucher booklet}) # Duskruin Arena - 100 vouchers
  insert(:name, %{sanguine stamped voucher booklet}) # Duskruin Arena - 250 vouchers
end

migrate "simucoin:rumorwoods" do
  insert(:name, %{circular tin sunburst marker})    # Rumor Woods Entries (1 uses)
  insert(:name, %{circular bronze sunburst marker}) # Rumor Woods Entries (10 uses)
  insert(:name, %{circular silver sunburst marker}) # Rumor Woods Entries (25 uses)
  insert(:name, %{circular golden sunburst marker}) # Rumor Woods Entries (50 uses)
  insert(:name, %{circular laje sunburst marker})   # Rumor Woods Entries (100 uses)
  insert(:name, %{circular vaalin sunburst marker}) # Rumor Woods Entries (250 uses)
end

migrate "simucoin:ebongate" do
  insert(:name, %{prismatic ether}) # Ebon Gate Holy Ether
end

migrate "simucoin:reim" do
  insert(:name, %{small glowing orb})         # Settlement of Reim - 1 access token
  insert(:name, %{glowing orb})               # Settlement of Reim - 10 access tokens
  insert(:name, %{large glowing orb})         # Settlement of Reim - 50 access tokens
  insert(:name, %{pair of prismatic goggles}) # Settlement of Reim - Reim googles
end

migrate "simucoin:f2p" do
  insert(:name, %{engraved adventurer token})     # Adventurer's Guild Boost
  insert(:name, %{engraved bank token})           # Bank Account Cap Increase
  insert(:name, %{account transfer form})         # Bank Account Transfer
  insert(:name, %{engraved Lumnis token})         # Experience - Gift of Lumnis Token
  insert(:name, %{heavy introspection token})     # Experience - Greater Experience Pass (3 hrs)
  insert(:name, %{light introspection token})     # Experience - Lesser Experience Pass (3 hrs)
  insert(:name, %{small leaf-shaped token})       # Foraging Pass (3 hrs)
  insert(:name, %{large leaf-shaped token})       # Foraging Pass (30 days)
  insert(:name, %{bronze sword token})            # Gear Pass - Bronze
  insert(:name, %{golden sword token})            # Gear Pass - Gold
  insert(:name, %{silver sword token})            # Gear Pass - Silver
  insert(:name, %{small blood drop token})        # Healing Pass (3 hrs)
  insert(:name, %{large blood drop token})        # Healing Pass (30 days)
  insert(:name, %{bright flame-shaped token})     # Initial Element Attunement
  insert(:name, %{small pouch-shaped token})      # Inventory - 3 hrs
  insert(:name, %{large pouch-shaped token})      # Inventory - 30 or 90 days
  insert(:name, %{engraved locker token})         # Locker Access (30 days)
  insert(:name, %{whimsical harp-shaped token})   # Loresinging Pass (1 item)
  insert(:name, %{engraved quotation token})      # Profile Quote Pass
  insert(:name, %{glowing spell token})           # Spell Pass (casting) (15 min)
  insert(:name, %{shimmering spell token})        # Spell Pass (receiving) (15 min)
  insert(:name, %{engraved gate token})           # Resurrection Pass (30 days)
  insert(:name, %{engraved society token})        # Society Advancement Pass (30 days)
  insert(:name, %{tiny fox-shaped token})         # Spell Reset - Familiar Gate (930)
  insert(:name, %{tiny window-shaped token})      # Spell Reset - Locate Person (116)
  insert(:name, %{tiny swirl-shaped token})       # Spell Reset - Planar Shift (740)
  insert(:name, %{tiny mist-shaped token})        # Spell Reset - Spirit Guide (130)
  insert(:name, %{tiny fog cloud token})          # Spell Reset - Transference (225)
  insert(:name, %{tiny ale-shaped token})         # Spell Reset - Traveler's Song (1020)
  insert(:name, %{tiny eye-shaped token})         # Spell Reset - Vision (1217)
  insert(:name, %{tiny willow-shaped token})      # Spell Reset - Whispering Willow (605)
  insert(:name, %{tiny starburst token})          # Spell Reset - Mass Attack Spells
  insert(:name, %{engraved identification token}) # Title Change Pass
  insert(:name, %{small coin-shaped token})       # Treasure Boost (3 hrs)
  insert(:name, %{large coin-shaped token})       # Treasure Boost (30 days)
  insert(:name, %{tiny coin-shaped token})        # Treasure Cap Reset
end

migrate :scroll do
  create_key(:exclude)

  insert(:exclude, %{birth certificate parchment})
  insert(:exclude, %{amnesty parchment})
end

migrate :jewelry do
  insert(:exclude, %{sun-etched gold ring})
  insert(:exclude, %{enruned gold ring})
end

migrate :jar do
  insert(:exclude, %{squat pale grey crystal bottle})
  insert(:exclude, %{squat pale blue crystal bottle})
end

migrate :magic do
  insert(:exclude, %{Briarmoon Cove entry orb})
  insert(:exclude, %{small glowing orb})
  insert(:exclude, %{glowing orb})
  insert(:exclude, %{large glowing orb})
end

migrate :uncommon do
  insert(:exclude, %{bronze stamped voucher booklet})
  insert(:exclude, %{circular bronze sunburst marker})
  insert(:exclude, %{circular laje sunburst marker})
  insert(:exclude, %{circular vaalin sunburst marker})
  insert(:exclude, %{bronze sword token})
end
