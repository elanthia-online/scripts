# frozen_string_literal: true

# RSpec for ELoot::Loot.pool_full_recovery? (the sell-and-return recovery decision).
#
# Run: rspec pool_full_recovery_spec.rb
#
# eloot.lic cannot be required standalone -- it depends on the Lich runtime (GameObj,
# Script, Spell, Map, ...) and executes a main block on load. Rather than copy the
# predicate here (which would silently drift from the shipped code), the spec extracts
# the real method body from eloot.lic and evaluates it into a bare module. The predicate
# is pure -- all state is passed as arguments -- so it needs no Lich runtime to exercise.
# If the source or method cannot be found, the spec fails loudly instead of passing on a
# stale copy.

RSpec.describe 'ELoot::Loot.pool_full_recovery?' do
  # Extract only the pure predicate from eloot.lic and eval it into an isolated module.
  # (The full script cannot be required standalone; it needs the Lich runtime and runs a
  # main block on load. The predicate takes only plain arguments, so it needs no runtime.)
  # Sourcing the real method keeps this spec from drifting from the shipped code; if the
  # source or method cannot be found, it fails loudly rather than passing on a stale copy.
  let(:predicate) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    body = File.read(path)[/^ {4}def self\.pool_full_recovery\?[\s\S]*?^ {4}end$/]
    raise "pool_full_recovery? could not be extracted from #{path}" unless body

    Module.new { module_eval(body) }
  end

  # Fully-passing baseline; each example overrides only the field under test.
  let(:base) do
    { room_tags: ['locksmith pool', 'town'], has_disk: true, sell_allowed: true, attempted: false }
  end

  def recover?(**overrides)
    predicate.pool_full_recovery?(**base.merge(overrides))
  end

  context 'at a locksmith pool with a disk, selling allowed, first attempt' do
    it 'runs the recovery' do
      expect(recover?).to be true
    end
  end

  context 'room matching' do
    it 'matches a plain "locksmith" tag, not only "locksmith pool"' do
      expect(recover?(room_tags: ['locksmith'])).to be true
    end

    it 'is case-insensitive' do
      expect(recover?(room_tags: ['LOCKSMITH POOL'])).to be true
    end

    it 'does not recover away from a locksmith room' do
      expect(recover?(room_tags: ['town', 'bank'])).to be false
    end

    it 'does not recover with no room tags' do
      expect(recover?(room_tags: [])).to be false
    end
  end

  context 'guards' do
    it 'does not recover during a standalone pool command (sell not allowed)' do
      expect(recover?(sell_allowed: false)).to be false
    end

    it 'does not recover with no disk to set the box aside' do
      expect(recover?(has_disk: false)).to be false
    end

    it 'does not recover if recovery already ran for this box' do
      expect(recover?(attempted: true)).to be false
    end
  end

  context 'guard precedence (a failing guard wins even at a locksmith pool)' do
    it 'sell_allowed:false overrides an otherwise-eligible state' do
      expect(recover?(sell_allowed: false, has_disk: true, attempted: false)).to be false
    end

    it 'attempted:true overrides an otherwise-eligible state' do
      expect(recover?(attempted: true, has_disk: true, sell_allowed: true)).to be false
    end
  end
end

# RSpec for ELoot::Loot.loot_specials (box-context stow routing).
#
# box_loot drains loot_specials before loot_regular, so items that loot_specials handles
# (orbs, cursed items, keepers, uncommon weapons/armor, clothing) never reached the
# locksmith pool full-container recovery that v2.11.0 wired into loot_regular alone --
# they paused the script mid-pool-return instead. These specs pin the routing.
#
# Same approach as the predicate spec above: the real method body is extracted from
# eloot.lic and evaluated into a bare module alongside named stubs for the Lich runtime
# pieces it touches. Sourcing the shipped method keeps this from drifting; if the source
# or method cannot be found the spec fails loudly rather than passing on a stale copy.

RSpec.describe 'ELoot::Loot.loot_specials' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:method_body) do
    body = File.read(eloot_path)[/^ {4}def self\.loot_specials\b[\s\S]*?^ {4}end$/]
    raise "loot_specials could not be extracted from #{eloot_path}" unless body

    body
  end

  # A minimal GameObj stand-in -- only the readers loot_specials touches.
  let(:obj_class) { Struct.new(:name, :type, :id) }

  def obj(name, type, id = '1')
    obj_class.new(name, type, id)
  end

  # Every collaborator call, in order, so the specs can assert on routing rather than
  # on internal state.
  let(:calls) { [] }

  # Queued return values for Loot.stow_box_item: nil means the item fit normally,
  # :recovered means a sell-and-resume recovery re-looted the whole box.
  let(:stow_results) { [nil] }

  # Mirrors the shipped defaults closely enough to exercise the real branch conditions.
  let(:allowed_special_types) { %w[box clothing collectible cursed jewelry food breakable] }
  let(:loot_types) { %w[box clothing collectible coins cursed food gem jewelry magic uncommon valuable] }

  # Named stubs (not a loose double) so an argument-list change in eloot.lic fails here.
  let(:harness) do
    recorder = calls
    queued = stow_results
    types = loot_types
    special = allowed_special_types

    data = Object.new
    data.define_singleton_method(:loot_exclude_regex) { /black ora|urglaes/ }
    data.define_singleton_method(:loot_keep_regex) { /keepsake/ }
    data.define_singleton_method(:allowed_special_types) { special }
    data.define_singleton_method(:settings) { { loot_types: types } }
    data.define_singleton_method(:charm) { nil }

    eloot = Module.new
    eloot.define_singleton_method(:data) { data }
    eloot.define_singleton_method(:msg) { |**_kw| nil }
    # decurse returns true for anything not cursed; that is the path under test.
    eloot.define_singleton_method(:decurse) { |_thing| true }
    eloot.define_singleton_method(:get_res) do |command, _regex|
      recorder << [:get_res, command]
      nil
    end

    inventory = Module.new
    inventory.define_singleton_method(:open_loot_containers) { |_objs| nil }
    inventory.define_singleton_method(:free_hand) { nil }
    inventory.define_singleton_method(:single_drag) do |thing|
      recorder << [:single_drag, thing.name]
      nil
    end

    stats = Module.new
    stats.define_singleton_method(:level) { 1 }

    loot = Module.new
    loot.define_singleton_method(:bag_loot) do |thing|
      recorder << [:bag_loot, thing.name]
      nil
    end
    loot.define_singleton_method(:stow_box_item) do |thing, box, location, data_arg, sell_recovered|
      recorder << [:stow_box_item, thing.name, box&.name, location, data_arg, sell_recovered]
      queued.shift
    end

    mod = Module.new
    mod.const_set(:ELoot, eloot)
    mod.const_set(:Inventory, inventory)
    mod.const_set(:Loot, loot)
    mod.const_set(:Stats, stats)
    mod.module_eval(method_body)
    mod
  end

  let(:box) { obj('white oak strongbox', 'box', '10244306') }
  let(:orb) { obj('heavy quartz orb', 'magic', '10244314') } # special: matches the orb rule
  let(:earcuff) { obj('sunstone earcuff', 'clothing', '10244316') } # special: allowed_special_types
  let(:mica) { obj('large piece of mica', 'gem', '10244313') } # not special: left for loot_regular

  context 'in a box-looting flow (box context supplied)' do
    it 'stows through stow_box_item so the pool recovery can fire, not straight to single_drag' do
      remaining = harness.loot_specials([orb, mica], box: box, location: 'Icemule Trace', data: {}, sell_recovered: false)

      expect(calls).to eq([[:stow_box_item, 'heavy quartz orb', 'white oak strongbox', 'Icemule Trace', {}, false]])
      expect(remaining).to eq([mica])
    end

    it 'threads sell_recovered through so a recovery cannot re-enter for the same box' do
      harness.loot_specials([orb], box: box, location: 'Icemule Trace', data: {}, sell_recovered: true)

      expect(calls.first.last).to be true
    end

    it 'still routes silver coins to the coin command rather than a stow' do
      coins = obj('some silver coins', 'coins', '10244308')

      harness.loot_specials([coins], box: box)

      expect(calls).to eq([[:get_res, 'get coins']])
    end

    it 'still leaves excluded items for loot_regular without touching them' do
      excluded = obj('black ora bar', 'valuable', '10244309')

      remaining = harness.loot_specials([excluded], box: box)

      expect(calls).to be_empty
      expect(remaining).to eq([excluded])
    end
  end

  context 'when a recovery re-loots the whole box' do
    let(:stow_results) { [:recovered] }

    it 'reports :recovered rather than an empty list, which would mean "nothing left"' do
      remaining = harness.loot_specials([orb, earcuff], box: box, location: 'Icemule Trace', data: {})

      expect(remaining).to eq(:recovered)
    end

    it 'never reports :recovered as a bare empty list, which callers cannot distinguish' do
      remaining = harness.loot_specials([orb, earcuff], box: box, location: 'Icemule Trace', data: {})

      expect(remaining).not_to eq([])
    end

    it 'stops processing the stale item list instead of working items twice' do
      harness.loot_specials([orb, earcuff], box: box, location: 'Icemule Trace', data: {})

      expect(calls.count { |c| c.first == :stow_box_item }).to eq(1)
      expect(calls).not_to include([:bag_loot, 'sunstone earcuff'])
    end
  end

  context 'outside a box-looting flow (room looting, critter bags)' do
    it 'keeps the existing single_drag behavior and never consults the pool recovery' do
      remaining = harness.loot_specials([orb, mica])

      expect(calls).to eq([[:single_drag, 'heavy quartz orb']])
      expect(remaining).to eq([mica])
    end

    it 'looks inside clothing for critter bags before stowing it' do
      remaining = harness.loot_specials([earcuff])

      expect(calls).to eq([[:bag_loot, 'sunstone earcuff'], [:single_drag, 'sunstone earcuff']])
      expect(remaining).to eq([])
    end
  end
end

# RSpec for the box-looting call sites.
#
# The v2.11.0 defect was not a broken method -- stow_box_item and pool_full_recovery? were
# both correct. It was a call site that never routed to them: box_loot drained
# loot_specials first and passed it no box context. A unit spec on loot_specials cannot
# catch box_loot forgetting to pass that context, so the wiring is asserted here against
# the shipped source.

RSpec.describe 'ELoot box-looting call sites' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  def method_body(source, name)
    body = source[/^ {4}def self\.#{Regexp.escape(name)}\b[\s\S]*?^ {4}end$/]
    raise "#{name} could not be extracted from eloot.lic" unless body

    body
  end

  let(:box_loot) { method_body(source, 'box_loot') }
  let(:box_loot_ground) { method_body(source, 'box_loot_ground') }

  it 'box_loot hands the box to loot_specials so a full-container stow can recover' do
    expect(box_loot).to match(/Loot\.loot_specials\([^)]*\bbox:\s*box\b/)
  end

  it 'box_loot hands sell_recovered to loot_specials so a recovery cannot re-enter' do
    expect(box_loot).to match(/Loot\.loot_specials\([^)]*\bsell_recovered:\s*sell_recovered\b/)
  end

  it 'box_loot hands loot_specials the same location and data it hands loot_regular' do
    expect(box_loot).to match(/Loot\.loot_specials\([^)]*\blocation:\s*location\b/)
    expect(box_loot).to match(/Loot\.loot_specials\([^)]*\bdata:\s*data\b/)
  end

  it 'box_loot_ground hands the box to loot_specials, matching its loot_regular call' do
    expect(box_loot_ground).to match(/Loot\.loot_specials\([^)]*\bbox:\s*box\b/)
  end

  # A completed recovery re-loots the box through a nested box_loot, which finalizes it.
  # Finalizing again re-issues trash and drag commands against a box that is already gone.
  # box_loot cannot be exercised without the Lich runtime, so the guard is asserted
  # structurally: the :recovered exits must come before the finalization call.
  context 'double finalization after a completed recovery' do
    it 'box_loot returns on :recovered before it reaches Sell.save_trash_box' do
      guard = box_loot.index(/^ +return if .*== :recovered$/)
      finalize = box_loot.index(/Sell\.save_trash_box/)

      expect(guard).not_to be_nil, 'box_loot has no :recovered guard'
      expect(finalize).not_to be_nil, 'box_loot no longer finalizes the box'
      expect(guard).to be < finalize
    end

    it 'box_loot guards both the loot_specials and the loot_regular result' do
      expect(box_loot.scan(/^ +return if .*== :recovered$/).length).to eq(2)
    end

    it 'box_loot_ground skips to the next box on :recovered before its inline cleanup' do
      guard = box_loot_ground.index(/^ +next if .*== :recovered$/)
      cleanup = box_loot_ground.index(/toss_cmd = /)

      expect(guard).not_to be_nil, 'box_loot_ground has no :recovered guard'
      expect(cleanup).not_to be_nil, 'box_loot_ground no longer cleans up the box'
      expect(guard).to be < cleanup
    end

    it 'box_loot_ground guards both the loot_specials and the loot_regular result' do
      expect(box_loot_ground.scan(/^ +next if .*== :recovered$/).length).to eq(2)
    end

    it 'loot_regular actually returns the :recovered it documents, not nil' do
      loot_regular = method_body(source, 'loot_regular')

      expect(loot_regular).to match(/return :recovered if/)
      expect(loot_regular).not_to match(/^ +return if .*== :recovered$/)
    end
  end
end

# RSpec for ELoot::Sell.town_openable? and the box routing that depends on it.
#
# "case" boxes cannot be opened by the town locksmith -- it ignores them even when the box
# is held in hand -- so only the locksmith pool or a player locksmith can open them.
# Routing one to town burns a silver withdrawal and a trip on every sell run and the box
# never opens, so the predicate and the routing are pinned here.

RSpec.describe 'ELoot::Sell.town_openable?' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  let(:method_bodies) do
    %w[town_openable? remember_town_refusal].map do |name|
      body = source[/^ {4}def self\.#{Regexp.escape(name)}[\s\S]*?^ {4}end$/]
      raise "#{name} could not be extracted from eloot.lic" unless body

      body
    end.join("\n\n")
  end

  let(:pool_only_nouns) do
    line = source[/^ {4}POOL_ONLY_NOUNS = .*$/]
    raise 'POOL_ONLY_NOUNS could not be extracted from eloot.lic' unless line

    line
  end

  let(:obj_class) { Struct.new(:name, :noun) }

  def obj(name, noun)
    obj_class.new(name, noun)
  end

  # Fresh per example so a remembered refusal cannot leak between them.
  let(:refused) { [] }

  let(:harness) do
    store = refused

    data = Object.new
    data.define_singleton_method(:town_refused) { store }
    data.define_singleton_method(:town_refused=) { |v| store.replace(Array(v)) }

    eloot = Module.new
    eloot.define_singleton_method(:data) { data }
    eloot.define_singleton_method(:msg) { |**_kw| nil }

    mod = Module.new
    mod.const_set(:ELoot, eloot)
    mod.module_eval("#{pool_only_nouns}\n#{method_bodies}")
    mod.const_set(:Sell, mod)
    mod
  end

  context 'the static pool-only rule' do
    it 'refuses "case" boxes, which the town locksmith ignores even when held' do
      expect(harness.town_openable?(obj('a gilded delicate case', 'case'))).to be false
      expect(harness.town_openable?(obj('a crude stained case', 'case'))).to be false
    end

    it 'still allows the box nouns the town locksmith does open' do
      %w[box chest coffer strongbox trunk].each do |noun|
        expect(harness.town_openable?(obj("an acid-pitted steel #{noun}", noun))).to be true
      end
    end

    it 'does not refuse a box merely for sharing a case adjective' do
      expect(harness.town_openable?(obj('a gilded delicate coffer', 'coffer'))).to be true
    end

    it 'treats an object with no noun as openable rather than raising' do
      expect(harness.town_openable?(Object.new)).to be true
    end
  end

  context 'the learned refusal safety net' do
    it 'refuses a box name the NPC already ignored this run' do
      box = obj('a scorched cracked trunk', 'trunk')
      expect(harness.town_openable?(box)).to be true

      harness.remember_town_refusal(box)

      expect(harness.town_openable?(box)).to be false
    end

    it 'records each refused name once' do
      box = obj('a scorched cracked trunk', 'trunk')

      3.times { harness.remember_town_refusal(box) }

      expect(refused).to eq(['a scorched cracked trunk'])
    end

    it 'does not refuse other boxes that happen to be present' do
      harness.remember_town_refusal(obj('a scorched cracked trunk', 'trunk'))

      expect(harness.town_openable?(obj('an acid-pitted steel chest', 'chest'))).to be true
    end
  end
end

RSpec.describe 'ELoot::Sell.process_boxes routing' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  def method_body(source, name)
    body = source[/^ {4}def self\.#{Regexp.escape(name)}\b[\s\S]*?^ {4}end$/]
    raise "#{name} could not be extracted from eloot.lic" unless body

    body
  end

  let(:process_boxes) { method_body(source, 'process_boxes') }
  let(:locksmith) { method_body(source, 'locksmith') }
  let(:locksmith_open) { method_body(source, 'locksmith_open') }

  # process_boxes cannot be exercised without the Lich runtime, so the routing invariants
  # are asserted against the shipped source.
  it 'never hands the raw box list to the town locksmith' do
    expect(process_boxes).not_to match(/Sell\.locksmith\(boxes\)/)
  end

  it 'filters the town locksmith list through town_openable?' do
    expect(process_boxes).to match(/town_boxes = boxes\.select \{ \|box\| Sell\.town_openable\?\(box\) \}/)
    expect(process_boxes).to match(/Sell\.locksmith\(town_boxes\)/)
  end

  it 'pools only the pool-only boxes when the gem bounty diverts the rest to town' do
    expect(process_boxes).to match(/Sell\.locksmith_pool\(boxes\.reject \{ \|box\| Sell\.town_openable\?\(box\) \}\)/)
  end

  it 'checks the pool is usable before routing pool-only boxes to it' do
    expect(process_boxes).to match(/Sell\.pool_available\?/)
  end

  it 'reports boxes it is keeping when the pool was unavailable' do
    expect(process_boxes).to match(/pool_needed\.any\?/)
  end

  it 'skips known-refused boxes inside the locksmith activator loop' do
    expect(locksmith).to match(/next unless Sell\.town_openable\?\(box\)/)
  end

  it 'distinguishes an in-hand refusal from a timeout and remembers it' do
    expect(locksmith_open).to match(/ignores you/)
    expect(locksmith_open).to match(/Sell\.remember_town_refusal\(box\)/)
    expect(locksmith_open).to match(/ELoot\.in_hand\?\(box\)/)
  end
end

# RSpec for the "Locksmith Priority" setting (Pool First / Locksmith First), which only
# matters when both sell_locksmith and sell_locksmith_pool are enabled. process_boxes'
# locksmith_first gating is asserted structurally, same as the rest of process_boxes -- it
# cannot be exercised without the Lich runtime. Sell.route_town_then_pool has no navigation
# of its own, though, so it is exercised for real against a small stand-in for Sell/ELoot.

RSpec.describe 'ELoot::Sell locksmith_priority routing' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  def method_body(source, name)
    body = source[/^ {4}def self\.#{Regexp.escape(name)}\b[\s\S]*?^ {4}end$/]
    raise "#{name} could not be extracted from eloot.lic" unless body

    body
  end

  let(:process_boxes) { method_body(source, 'process_boxes') }
  let(:route_town_then_pool_body) { method_body(source, 'route_town_then_pool') }

  it 'defaults locksmith_priority to pool, so existing setups keep their current behavior' do
    line = source[/^\s*locksmith_priority: \{ default: '(\w+)' \},$/, 1]
    expect(line).to eq('pool')
  end

  context 'process_boxes locksmith_first gating' do
    it 'only takes the locksmith-first path with both routes enabled and no gem-bounty override' do
      expect(process_boxes).to match(/locksmith_first = !skip_for_gem_bounty && pool_enabled && town_enabled &&/)
      expect(process_boxes).to match(/ELoot\.data\.settings\[:locksmith_priority\] == 'locksmith'/)
    end

    it 'routes through route_town_then_pool only on the locksmith-first path' do
      expect(process_boxes).to match(/if locksmith_first\s*\n\s*boxes = Sell\.route_town_then_pool\(boxes\)/)
    end

    it 'still reports leftover boxes the same way regardless of which path ran' do
      expect(process_boxes).to match(/pool_needed = boxes\.reject \{ \|box\| Sell\.town_openable\?\(box\) \}/)
    end
  end

  context 'route_town_then_pool' do
    let(:obj_class) { Struct.new(:name, :noun) }

    def obj(name, noun)
      obj_class.new(name, noun)
    end

    let(:calls) { [] }
    let(:town_openable) { {} } # box name => bool, defaults to true
    let(:find_boxes_queue) { [] } # successive ELoot.find_boxes return values
    let(:pool_available) { true }
    let(:always_check_pool) { false } # ELoot.data.settings[:always_check_pool]

    let(:harness) do
      log = calls
      openable = town_openable
      queue = find_boxes_queue
      avail = pool_available
      always_check = always_check_pool

      eloot = Module.new
      eloot.define_singleton_method(:find_boxes) { queue.shift || [] }
      eloot.define_singleton_method(:data) { Struct.new(:settings).new({ always_check_pool: always_check }) }

      mod = Module.new
      mod.const_set(:ELoot, eloot)
      mod.define_singleton_method(:town_openable?) { |box| openable.fetch(box.name, true) }
      mod.define_singleton_method(:locksmith) { |boxes| log << [:locksmith, boxes.map(&:name)] }
      mod.define_singleton_method(:pool_available?) do
        log << [:pool_available?]
        avail
      end
      mod.define_singleton_method(:locksmith_pool) { |boxes| log << [:locksmith_pool, boxes.map(&:name)] }
      mod.define_singleton_method(:pool_return) { log << [:pool_return] }
      mod.const_set(:Sell, mod)
      mod.module_eval(route_town_then_pool_body)
      mod
    end

    it 'sends only town-openable boxes to the town locksmith first' do
      openable_box = obj('a steel strongbox', 'strongbox')
      pool_only_box = obj('a delicate case', 'case')
      town_openable[pool_only_box.name] = false
      find_boxes_queue.replace([[], []])

      harness.route_town_then_pool([openable_box, pool_only_box])

      expect(calls.first).to eq([:locksmith, ['a steel strongbox']])
    end

    it 'refreshes from the room before deciding what to pool, not the pre-town list' do
      box = obj('a steel strongbox', 'strongbox')
      # Still present after the town run (e.g. a mid-run refusal), gone after the pool.
      find_boxes_queue.replace([[box], []])

      harness.route_town_then_pool([box])

      expect(calls).to include([:locksmith_pool, ['a steel strongbox']])
      expect(calls).to include([:pool_return])
    end

    it 'does not visit the pool when nothing is left after town' do
      box = obj('a steel strongbox', 'strongbox')
      find_boxes_queue.replace([[]])

      harness.route_town_then_pool([box])

      expect(calls.map(&:first)).not_to include(:locksmith_pool)
    end

    context 'when always_check_pool is set and nothing is left to drop off' do
      let(:always_check_pool) { true }

      it 'still checks the pool for returns, without a drop-off attempt' do
        box = obj('a steel strongbox', 'strongbox')
        find_boxes_queue.replace([[]])

        harness.route_town_then_pool([box])

        expect(calls.map(&:first)).not_to include(:locksmith_pool)
        expect(calls).to include([:pool_return])
      end
    end

    context 'when always_check_pool is not set and nothing is left to drop off' do
      it 'does not check the pool for returns' do
        box = obj('a steel strongbox', 'strongbox')
        find_boxes_queue.replace([[]])

        harness.route_town_then_pool([box])

        expect(calls.map(&:first)).not_to include(:pool_return)
      end
    end

    context 'when the pool is unavailable' do
      let(:pool_available) { false }

      it 'does not visit the pool' do
        box = obj('a delicate case', 'case')
        town_openable[box.name] = false
        find_boxes_queue.replace([[box]])

        harness.route_town_then_pool([box])

        expect(calls.map(&:first)).not_to include(:locksmith_pool)
      end
    end

    it 'returns whatever is still present after both routes have run' do
      box = obj('a steel strongbox', 'strongbox')
      leftover = [box]
      find_boxes_queue.replace([[box], leftover])

      result = harness.route_town_then_pool([box])

      expect(result).to equal(leftover)
    end
  end
end

# RSpec for ELoot::Sell.gem_bounty_override? (extracted so process_boxes and box_in_hand
# cannot drift out of sync on what counts as the gem-bounty override).

RSpec.describe 'ELoot::Sell.gem_bounty_override?' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  let(:method_body) do
    body = source[/^ {4}def self\.gem_bounty_override\?[\s\S]*?^ {4}end$/]
    raise "gem_bounty_override? could not be extracted from #{eloot_path}" unless body

    body
  end

  let(:gem_task) { true }
  let(:setting) { true }

  let(:harness) do
    task_gem = gem_task
    setting_val = setting

    data = Object.new
    data.define_singleton_method(:settings) { { locksmith_when_gem_bounty: setting_val } }

    eloot = Module.new
    eloot.define_singleton_method(:data) { data }

    task = Object.new
    task.define_singleton_method(:gem?) { task_gem }

    bounty = Module.new
    bounty.define_singleton_method(:task) { task }

    mod = Module.new
    mod.const_set(:ELoot, eloot)
    mod.const_set(:Bounty, bounty)
    mod.module_eval(method_body)
    mod
  end

  it 'is true when a gem bounty is active and the override setting is on' do
    expect(harness.gem_bounty_override?).to be true
  end

  context 'gem bounty active, override setting off' do
    let(:setting) { false }

    it 'returns false' do
      expect(harness.gem_bounty_override?).to be false
    end
  end

  context 'override setting on, no gem bounty active' do
    let(:gem_task) { false }

    it 'returns false' do
      expect(harness.gem_bounty_override?).to be false
    end
  end

  context 'neither condition holds' do
    let(:gem_task) { false }
    let(:setting) { false }

    it 'returns false' do
      expect(harness.gem_bounty_override?).to be false
    end
  end
end

# RSpec for ELoot::Sell.box_in_hand's Locksmith Priority handling (v2.11.3/v2.11.4).
#
# box_in_hand previously always tried the locksmith pool first, ignoring the
# Locksmith Priority setting entirely, and could walk a pool-only box to the town
# locksmith on the final fallback. This exercises the real method body -- unlike
# locksmith/locksmith_open, box_in_hand's own collaborators (GameObj, ELoot::Inventory,
# Sell.locksmith/locksmith_pool/town_openable?/gem_bounty_override?) are all easily
# stubbed, with no direct Lich-runtime primitives (dothistimeout, fput, move) in its
# own body, so it does not need to fall back to structural-only assertions.

RSpec.describe 'ELoot::Sell.box_in_hand' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  let(:method_body) do
    body = source[/^ {4}def self\.box_in_hand\b[\s\S]*?^ {4}end$/]
    raise "box_in_hand could not be extracted from #{eloot_path}" unless body

    body
  end

  let(:hand_class) { Struct.new(:type, :noun, :id) }

  def hand(type, noun = 'strongbox', id = '111')
    hand_class.new(type, noun, id)
  end

  let(:empty_hand) { hand('Empty', nil, nil) }

  # Mutable hand state: the fake GameObj reads these, and the fake Sell.locksmith
  # (never Sell.locksmith_pool -- see note below) can clear whichever hand holds the
  # box under test, simulating a successful town open.
  let(:right) { hand('box') }
  let(:left) { empty_hand }

  let(:calls) { [] }
  let(:pool_enabled) { true }
  let(:town_enabled) { true }
  let(:priority) { 'pool' }
  let(:gem_bounty_override) { false }
  let(:town_openable) { true }

  # What Sell.locksmith_pool does to the hand it's given: :clear removes the box
  # (accepted), :noop leaves it (declined/full). Only :noop is used below -- whether
  # a single-box pool give-away leaves both hands truly empty afterward is a
  # pre-existing, unrelated question this spec does not need to settle; every
  # scenario here either never reaches the pool call or treats it as a decline,
  # which is exactly what "pool is full" already covers.
  let(:pool_result) { :noop }

  let(:harness) do
    r = right
    l = left
    log = calls
    settings_hash = {
      sell_locksmith_pool: pool_enabled,
      sell_locksmith: town_enabled,
      locksmith_priority: priority
    }
    override = gem_bounty_override
    openable = town_openable
    pool_res = pool_result
    empty = empty_hand

    gameobj = Module.new
    gameobj.define_singleton_method(:right_hand) { r }
    gameobj.define_singleton_method(:left_hand) { l }

    data = Object.new
    data.define_singleton_method(:settings) { settings_hash }

    eloot = Module.new
    eloot.define_singleton_method(:data) { data }
    eloot.define_singleton_method(:msg) { |**kw| log << [:msg, kw] }

    inventory = Module.new
    inventory.define_singleton_method(:free_hands) { |**kw| log << [:free_hands, kw] }
    eloot.const_set(:Inventory, inventory)

    mod = Module.new
    mod.const_set(:ELoot, eloot)
    mod.const_set(:GameObj, gameobj)
    mod.define_singleton_method(:town_openable?) { |_item| openable }
    mod.define_singleton_method(:gem_bounty_override?) { override }
    mod.define_singleton_method(:locksmith) do |items|
      log << [:locksmith, items.map(&:noun)]
      items.each do |it|
        l = empty if l.equal?(it)
        r = empty if r.equal?(it)
      end
    end
    mod.define_singleton_method(:locksmith_pool) do |items, dep|
      log << [:locksmith_pool, items.map(&:noun), dep]
      next unless pool_res == :clear

      items.each do |it|
        l = empty if l.equal?(it)
        r = empty if r.equal?(it)
      end
    end
    mod.define_singleton_method(:exit) { raise 'exit called' }
    mod.const_set(:Sell, mod)
    mod.module_eval(method_body)
    mod
  end

  # Only entries relevant to routing order/coverage; free_hands/msg noise filtered out.
  def routing_calls(calls)
    calls.select { |c| %i[locksmith locksmith_pool].include?(c.first) }
  end

  context 'default priority (pool), both routes enabled, box is town-openable' do
    it 'tries the pool before the town locksmith' do
      harness.box_in_hand

      expect(routing_calls(calls).first).to eq([:locksmith_pool, ['strongbox'], true])
    end

    it 'falls through to town once the pool declines it' do
      harness.box_in_hand

      expect(routing_calls(calls).map(&:first)).to eq(%i[locksmith_pool locksmith])
    end
  end

  context 'Locksmith Priority set to town first, both routes enabled' do
    let(:priority) { 'locksmith' }

    it 'tries the town locksmith before ever touching the pool' do
      harness.box_in_hand

      expect(routing_calls(calls)).to eq([[:locksmith, ['strongbox']]])
    end
  end

  context 'gem-bounty override active, even with default Locksmith Priority (pool)' do
    let(:priority) { 'pool' }
    let(:gem_bounty_override) { true }

    it 'still tries the town locksmith first -- this is the bug this override fixes' do
      harness.box_in_hand

      expect(routing_calls(calls)).to eq([[:locksmith, ['strongbox']]])
    end
  end

  context 'Locksmith Priority set to town first, but the box is pool-only (e.g. a case)' do
    let(:priority) { 'locksmith' }
    let(:town_openable) { false }

    it 'never sends a pool-only box to town, even with town-first priority' do
      expect { harness.box_in_hand }.to raise_error('exit called')

      expect(routing_calls(calls).map(&:first)).not_to include(:locksmith)
      expect(routing_calls(calls).map(&:first)).to include(:locksmith_pool)
    end
  end

  context 'only the pool is enabled (sell_locksmith is off)' do
    let(:town_enabled) { false }
    let(:priority) { 'locksmith' } # should have no effect with only one route enabled
    let(:gem_bounty_override) { true } # same -- neither can turn on a disabled route

    it 'never calls the town locksmith at all' do
      expect { harness.box_in_hand }.to raise_error('exit called')

      expect(routing_calls(calls).map(&:first)).not_to include(:locksmith)
    end
  end

  context 'the pool is full and the box is pool-only, so nothing can process it' do
    let(:town_openable) { false }

    it 'does not walk it to town as a last resort' do
      expect { harness.box_in_hand }.to raise_error('exit called')

      expect(routing_calls(calls).map(&:first)).not_to include(:locksmith)
    end

    it 'reports it instead of silently giving up' do
      begin
        harness.box_in_hand
      rescue RuntimeError
        nil
      end

      expect(calls).to include([:msg, { text: ' Not able to process the box in your hand. Exiting...', space: true }])
    end
  end

  it 'threads the deposit flag through to the pool' do
    harness.box_in_hand(false)

    expect(calls).to include([:locksmith_pool, ['strongbox'], false])
  end
end

# RSpec for the insufficient-silver retry in Sell.locksmith/locksmith_open (v2.11.4).
#
# The retry previously recursed with the configured locksmith_withdraw_amount every
# time, which withdraws-and-fails forever if that setting is smaller than the box's
# actual fee. locksmith/locksmith_open cannot be exercised without the Lich runtime
# (dothistimeout, ELoot.get_command, Room, move, ...), so -- same as the rest of
# process_boxes' routing above -- this is pinned structurally against the shipped
# source rather than executed.

RSpec.describe 'ELoot::Sell.locksmith insufficient-silver retry' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  def method_body(source, name)
    body = source[/^ {4}def self\.#{Regexp.escape(name)}\b[\s\S]*?^ {4}end$/]
    raise "#{name} could not be extracted from eloot.lic" unless body

    body
  end

  let(:locksmith) { method_body(source, 'locksmith') }
  let(:locksmith_open) { method_body(source, 'locksmith_open') }

  it 'accepts a withdraw_amount/retries override and threads retries into locksmith_open' do
    expect(locksmith).to match(/def self\.locksmith\(boxes, withdraw_amount: .*, retries: 0\)/)
    expect(locksmith).to match(/Sell\.locksmith_open\(box, activator, retries: retries\)/)
  end

  it 'gives up after exactly one retry instead of withdrawing forever' do
    expect(locksmith_open).to match(/def self\.locksmith_open\(box, activator, retries: 0\)/)
    expect(locksmith_open).to match(/if retries\.positive\?/)
  end

  it 'leaves the box for the pool or a player locksmith when the retry is exhausted' do
    give_up = locksmith_open[/if retries\.positive\?[\s\S]*?^ {12}end$/]
    expect(give_up).not_to be_nil, 'could not find the retries-exhausted branch'
    expect(give_up).to match(/Leaving it for the pool or a player locksmith/)
    expect(give_up).not_to match(/Sell\.locksmith/)
  end

  it 'withdraws at least the quoted fee, not just the (possibly too small) configured amount' do
    expect(locksmith_open).to match(/quoted_fee = res\[\/Gimme \(\[\\d,\]\+\) silvers\/, 1\]/)
    expect(locksmith_open).to match(
      /withdraw_amount = \[quoted_fee, ELoot\.data\.settings\[:locksmith_withdraw_amount\]\]\.compact\.max/
    )
  end

  it 'retries through Sell.locksmith rather than recursing into locksmith_open directly' do
    expect(locksmith_open).not_to match(/return Sell\.locksmith_open\(box, activator\)/)
    expect(locksmith_open).to match(/return Sell\.locksmith\(\[box\], withdraw_amount: withdraw_amount, retries: retries \+ 1\)/)
  end
end

# RSpec for the gem_bounty_override? dedup: process_boxes must go through the same
# predicate as box_in_hand rather than keeping its own inline copy, or the two can
# silently drift apart again the way box_in_hand's did before v2.11.4.

RSpec.describe 'ELoot::Sell.process_boxes gem-bounty predicate reuse' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  let(:process_boxes) do
    body = source[/^ {4}def self\.process_boxes\b[\s\S]*?^ {4}end$/]
    raise "process_boxes could not be extracted from #{eloot_path}" unless body

    body
  end

  it 'computes skip_for_gem_bounty from the shared predicate' do
    expect(process_boxes).to match(/skip_for_gem_bounty = Sell\.gem_bounty_override\? && town_enabled && boxes\.any\?/)
  end
end

# RSpec for ELoot.marked_unsellable? and ELoot.toss (the trash/drop helper).
#
# box_loot_ground and Sell.save_trash_box each carried their own inline copies of the
# same trash/drop-and-check-hand logic (once for a single item, once retried up to 4
# times for a box), and Sell.dump_herbs_junk carried a third copy that polled instead of
# waiting on roundtime. ELoot.toss consolidates all three into one helper, parameterized
# on attempts/poll/notify_on_keep, with a mark-status safety check in front of every
# attempt so a marked item is never sent to trash/drop in the first place.
#
# Same approach as the specs above: the real method bodies are extracted from eloot.lic
# and evaluated into a bare module alongside named stubs for the collaborators they call
# (ELoot.get_res, ELoot.msg, ELoot.in_hand?, ELoot.wait_rt, and the global fput). Sourcing
# the shipped methods keeps this from drifting; if the source or a method cannot be found
# the spec fails loudly rather than passing on a stale copy.

RSpec.describe 'ELoot.marked_unsellable?' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  let(:method_body) do
    body = source[/^ {2}def self\.marked_unsellable\?[\s\S]*?^ {2}end$/]
    raise "marked_unsellable? could not be extracted from #{eloot_path}" unless body

    body
  end

  let(:obj_class) { Struct.new(:name, :id) }

  def obj(name, id = '60982408')
    obj_class.new(name, id)
  end

  let(:calls) { [] }

  # What the game sends back in response to the "mark <item> status" command, as the
  # single matching line get_command would hand back. Each context below overrides
  # this with one of the two real responses (or nil, for "no matching line found") to
  # drive the branch under test.
  let(:response) { nil }

  let(:harness) do
    recorder = calls
    reply = response

    mod = Module.new
    mod.define_singleton_method(:get_command) do |command, _regex, **kw|
      recorder << [:get_command, command, kw]
      reply.nil? ? [] : [reply]
    end
    mod.define_singleton_method(:msg) { |**kw| recorder << [:msg, kw] }
    mod.module_eval(method_body)
    mod.const_set(:ELoot, mod)
    mod
  end

  it 'asks for the item mark status by id' do
    harness.marked_unsellable?(obj('a dark mithril lockpick', '60982408'))

    expect(calls.map { |c| c[0..1] }).to include([:get_command, 'mark #60982408 status'])
  end

  it 'asks silently, without echoing the command or its response to the player' do
    harness.marked_unsellable?(obj('a dark mithril lockpick', '60982408'))

    expect(calls.find { |c| c.first == :get_command }.last).to eq(silent: true, quiet: true)
  end

  context 'when the item is not marked' do
    let(:response) { 'Your dark mithril lockpick is not marked as unsellable.' }

    it 'returns false' do
      expect(harness.marked_unsellable?(obj('a dark mithril lockpick'))).to be false
    end

    it 'does not report anything about it' do
      harness.marked_unsellable?(obj('a dark mithril lockpick'))

      expect(calls.none? { |c| c.first == :msg }).to be true
    end
  end

  context 'when the item has been marked as unsellable' do
    let(:response) { 'Your sage green silk cloak has been marked as unsellable.' }

    it 'returns true' do
      expect(harness.marked_unsellable?(obj('a sage green silk cloak'))).to be true
    end

    it 'reports which item it is keeping' do
      harness.marked_unsellable?(obj('a sage green silk cloak'))

      expect(calls.last).to eq([:msg, { type: 'info', text: ' a sage green silk cloak is marked as unsellable, keeping it.' }])
    end
  end

  context 'when no line matches (lag, an unrelated line, a timeout)' do
    let(:response) { nil }

    it 'fails open rather than blocking a legitimate toss' do
      expect(harness.marked_unsellable?(obj('a dark mithril lockpick'))).to be false
    end
  end
end

RSpec.describe 'ELoot.toss' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  let(:method_body) do
    body = source[/^ {2}def self\.toss\b[\s\S]*?^ {2}end$/]
    raise "toss could not be extracted from #{eloot_path}" unless body

    body
  end

  let(:obj_class) { Struct.new(:name, :id) }
  let(:item) { obj_class.new('a rusty dagger', '12345') }

  let(:fput_calls) { [] }
  let(:wait_rt_calls) { [] }

  # The item "leaves hand" once fput has been called `disposed_after` times. A value
  # larger than `attempts` means it never leaves hand within the attempts under test.
  let(:disposed_after) { 1 }
  let(:marked) { false }

  let(:harness) do
    fputs = fput_calls
    waits = wait_rt_calls
    need = disposed_after
    is_marked = marked

    mod = Module.new
    mod.define_singleton_method(:marked_unsellable?) { |_obj| is_marked }
    mod.define_singleton_method(:fput) { |cmd| fputs << cmd }
    mod.define_singleton_method(:in_hand?) { |_obj| fputs.length < need }
    mod.define_singleton_method(:wait_rt) { waits << true }
    mod.module_eval(method_body)
    mod.const_set(:ELoot, mod)
    mod
  end

  context 'when the item is marked as unsellable' do
    let(:marked) { true }

    it 'never attempts to toss it' do
      harness.toss(item, 'trash')

      expect(fput_calls).to be_empty
    end

    it 'returns false so the caller stows it back' do
      expect(harness.toss(item, 'trash')).to be false
    end
  end

  context 'when unmarked and disposed on the first attempt' do
    it 'issues the toss command with the item id' do
      harness.toss(item, 'trash')

      expect(fput_calls).to eq(['trash #12345'])
    end

    it 'uses the given toss_cmd verbatim (drop vs trash)' do
      harness.toss(item, 'drop')

      expect(fput_calls).to eq(['drop #12345'])
    end

    it 'returns true' do
      expect(harness.toss(item, 'trash')).to be true
    end

    it 'waits on roundtime by default' do
      harness.toss(item, 'trash')

      expect(wait_rt_calls.length).to eq(1)
    end
  end

  context 'when unmarked but still in hand after the only attempt (attempts: 1 default)' do
    let(:disposed_after) { 2 }

    it 'returns false' do
      expect(harness.toss(item, 'trash')).to be false
    end

    it 'only tries once' do
      harness.toss(item, 'trash')

      expect(fput_calls.length).to eq(1)
    end

    it 'stays silent by default (notify_on_keep: false)' do
      recorder = fput_calls
      mod = harness
      msgs = []
      mod.define_singleton_method(:msg) { |**kw| msgs << kw }

      mod.toss(item, 'trash')

      expect(msgs).to be_empty
      expect(recorder.length).to eq(1) # sanity: the attempt still happened
    end

    it 'reports it when notify_on_keep is true' do
      mod = harness
      msgs = []
      mod.define_singleton_method(:msg) { |**kw| msgs << kw }

      mod.toss(item, 'trash', notify_on_keep: true)

      expect(msgs).to eq([{ type: 'info', text: " #{item.name} isn't trashed so maybe its special...keeping it." }])
    end
  end

  context 'with attempts: 4 (the box-toss retry)' do
    context 'and it never leaves hand' do
      let(:disposed_after) { 99 }

      it 'tries exactly 4 times, no more' do
        harness.toss(item, 'trash', attempts: 4)

        expect(fput_calls.length).to eq(4)
      end

      it 'returns false' do
        expect(harness.toss(item, 'trash', attempts: 4)).to be false
      end
    end

    context 'and it leaves hand on the 3rd attempt' do
      let(:disposed_after) { 3 }

      it 'stops retrying once it is gone, instead of always spending all 4' do
        harness.toss(item, 'trash', attempts: 4)

        expect(fput_calls.length).to eq(3)
      end

      it 'returns true' do
        expect(harness.toss(item, 'trash', attempts: 4)).to be true
      end
    end
  end

  context 'with poll: true (dump_herbs_junk\'s fast in-hand poll)' do
    it 'never waits on roundtime' do
      harness.toss(item, 'trash', poll: true)

      expect(wait_rt_calls).to be_empty
    end

    it 'still disposes correctly' do
      expect(harness.toss(item, 'trash', poll: true)).to be true
    end

    context 'when the item survives' do
      let(:disposed_after) { 2 }

      it 'still returns false' do
        expect(harness.toss(item, 'trash', poll: true)).to be false
      end
    end
  end

  it 'checks mark status before ever attempting a toss' do
    mark_check = method_body.index(/marked_unsellable\?/)
    retry_loop = method_body.index(/attempts\.times/)

    expect(mark_check).not_to be_nil
    expect(retry_loop).not_to be_nil
    expect(mark_check).to be < retry_loop
  end
end

# RSpec for the trash/drop call-site refactor (box_loot_ground, Sell.save_trash_box,
# Sell.dump_herbs_junk). Before this, all 5 call sites carried their own copy of the
# fput/wait/check-hand sequence; a unit spec on ELoot.toss alone cannot catch a call site
# drifting back to an inline copy, so the wiring is pinned here against the shipped
# source, the same way the box-looting call sites above are pinned.

RSpec.describe 'ELoot trash/drop call sites' do
  let(:eloot_path) do
    path = [
      File.expand_path('eloot.lic', __dir__), # delivered alongside the spec
      File.expand_path('../eloot.lic', __dir__),
      File.expand_path('../../eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__) # spec/scripts/ -> scripts/
    ].find { |p| File.exist?(p) }
    raise "eloot.lic not found (looked relative to #{__dir__})" unless path

    path
  end

  let(:source) { File.read(eloot_path) }

  # Indent-agnostic: box_loot_ground/save_trash_box/dump_herbs_junk sit at different
  # nesting depths (Loot vs Sell vs top-level ELoot), unlike the fixed-indent helper
  # used elsewhere in this file.
  def method_body(source, name)
    match = source.match(/^( +)def self\.#{Regexp.escape(name)}\b[\s\S]*?\n\1end$/)
    raise "#{name} could not be extracted from eloot.lic" unless match

    match[0]
  end

  let(:box_loot_ground) { method_body(source, 'box_loot_ground') }
  let(:save_trash_box) { method_body(source, 'save_trash_box') }
  let(:dump_herbs_junk) { method_body(source, 'dump_herbs_junk') }

  it 'routes every trash/drop call site through the shared helper' do
    expect(source.scan(/ELoot\.toss\(/).length).to eq(5)
  end

  # Single-quoted deliberately: this is a literal substring match against the source
  # text, not interpolation. Double-quoting would try to interpolate a `toss_cmd`
  # local that doesn't exist in this spec and raise NameError.
  it 'leaves the raw toss command in exactly one place: inside the helper itself' do
    expect(source.scan('fput("#{toss_cmd}').length).to eq(1) # rubocop:disable Lint/InterpolationCheck
  end

  it 'box_loot_ground tosses box contents with the 1-attempt default, and the box itself with 4' do
    expect(box_loot_ground).to match(/Inventory\.single_drag\(item\) unless ELoot\.toss\(item, toss_cmd\)/)
    expect(box_loot_ground).to match(/ELoot\.toss\(box, toss_cmd, attempts: 4\)/)
  end

  it 'save_trash_box tosses box contents with the 1-attempt default, and the box itself with 4' do
    expect(save_trash_box).to match(/Inventory\.single_drag\(item\) unless ELoot\.toss\(item, toss_cmd\)/)
    expect(save_trash_box).to match(/ELoot\.toss\(box, toss_cmd, attempts: 4\)/)
  end

  it 'dump_herbs_junk keeps its fast poll and keep-notification behavior' do
    expect(dump_herbs_junk).to match(/ELoot\.toss\(item, toss_cmd, poll: true, notify_on_keep: true\)/)
  end
end
