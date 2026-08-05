# frozen_string_literal: true

# RSpec for ELoot::Loot.pool_full_recovery? (the sell-and-return recovery decision).
#
# Run: rspec eloot_spec.rb
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

    it 'returns an empty list so box_loot skips loot_regular' do
      remaining = harness.loot_specials([orb, earcuff], box: box, location: 'Icemule Trace', data: {})

      expect(remaining).to eq([])
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
end
