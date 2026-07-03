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
  # Locate eloot.lic relative to the spec: same directory first (as delivered), then
  # common repo layouts (spec/ alongside the script, or spec/ one level below root).
  def self.eloot_source_path
    [
      File.expand_path('scripts/eloot.lic', __dir__),
      File.expand_path('../scripts/eloot.lic', __dir__),
      File.expand_path('../../scripts/eloot.lic', __dir__)
    ].find { |p| File.exist?(p) }
  end

  # Extract only the pure predicate and eval it into an isolated module (memoized once).
  PREDICATE = begin
    path = eloot_source_path
    raise "eloot.lic not found (looked in #{__dir__} and parent directories)" unless path

    source = File.read(path)
    body = source[/^ {4}def self\.pool_full_recovery\?[\s\S]*?^ {4}end$/]
    raise "pool_full_recovery? could not be extracted from #{path}" unless body

    Module.new { module_eval(body) }
  end

  # Fully-passing baseline; each example overrides only the field under test.
  let(:base) do
    { room_tags: ['locksmith pool', 'town'], has_disk: true, sell_allowed: true, attempted: false }
  end

  def recover?(**overrides)
    PREDICATE.pool_full_recovery?(**base.merge(overrides))
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
