# frozen_string_literal: true

require_relative '../spec_helper'

# Specs for bigshot.lic. We do NOT load the .lic file: it needs the whole
# Lich runtime (Settings, XMLData, Spell, GTK, DRb ...). Instead the real
# method/class bodies are extracted from scripts/bigshot.lic and evaluated
# against stubs, so these specs exercise production code and fail if that
# code changes shape. Path lookup and loud-failure-on-miss extraction use
# the shared helpers in spec/spec_helper.rb.
#
# This file covers independent slices of bigshot, each kept in its own
# namespaced module (BigshotPrioritySpec, BigshotCreatureAdapterSpec, ...)
# with its own Harness rather than one shared harness, since each slice
# needs a differently-shaped Creature/GameObj double. Merging them into one
# shared harness would blur what each section is actually asserting and
# risk one section's stub state leaking into another's.
#
# Deliberately no NilClass patch here. Lich patches NilClass#method_missing to
# return nil (lich-5 lib/common/class_exts/nilclass.rb), which is what let the
# removed room-composition cache paper over nil comparisons. This code must not
# depend on that.
#
# Deliberately no shared GameObj stub from spec_helper.rb either: each
# section below nests its own GameObj inside its own Harness, per
# spec_helper.rb's own header note that a shared top-level GameObj stub
# would corrupt the real, top-level GameObj class spec/gameobj-data
# exercises directly.
#
# Phase 1 of the GameObj -> Creature/Combat migration moved the room-creature
# source of truth from GameObj.targets to Lich::Gemstone::Creature.targets,
# behind a BigshotCreature adapter that still exposes GameObj-shaped
# .status/.type (by delegating to the matching GameObj entry). This harness
# models both halves: a Creature stub standing in for the room roster, and a
# GameObj stub standing in for the matching entries the adapter falls back to.

module BigshotPrioritySpec
  SOURCE_PATH = find_lic_source('bigshot.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")

  def self.extract(pattern, label)
    extract_from_source(SOURCE, pattern, label: label, source_path: SOURCE_PATH)
  end

  BIGSHOT_CREATURE_SRC = extract(/^class BigshotCreature\n.*?^end$/m, 'BigshotCreature')
  BS_TARGETS_SRC = extract(/^  def bs_targets\(\*filters\).*?^  end$/m, 'bs_targets')
  BS_HOSTILE_SRC = extract(/^  def bs_hostile_creatures\(\*filters\).*?^  end$/m, 'bs_hostile_creatures')
  BS_ROOM_CREATURES_SRC = extract(/^  def bs_room_creatures\(\*filters\).*?^  end$/m, 'bs_room_creatures')
  PRIORITY_SRC = extract(/^  def priority\(target\).*?^  end$/m, 'priority')
  MATCHERS_SRC = extract(/^  def priority_matchers\n.*?^  end$/m, 'priority_matchers')
  RANK_SRC = extract(/^  def priority_rank\(npc, matchers\).*?^  end$/m, 'priority_rank')
  SORT_NPCS_SRC = extract(/^  def sort_npcs\(\).*?^  end$/m, 'sort_npcs')
  FIND_TARGET_SRC = extract(/^  def find_target\(target, just_entered = false\).*?^  end$/m, 'find_target')
  BOONS_SRC = extract(/^  def invalid_target_with_boons\(creature, assess = true\).*?^  end$/m,
                      'invalid_target_with_boons')
  DO_HUNT_RETARGET_SRC = extract(/^        if !priority\(target\)\n.*?^        end$/m,
                                 'do_hunt retarget block')
  FOLLOWER_RETARGET_SRC = extract(/^          if !\$bigshot_bandits && bs\.PRIORITY && !bs\.priority\(target\)\n.*?^          end$/m,
                                  'follower retarget block')
  EACHTARGET_SRC = extract(/^  def cmd_eachtarget\(command, npc\).*?^  end$/m, 'cmd_eachtarget')

  # GameObj-shaped fixture data (id/name/noun/type/status). Registered both as
  # the GameObj stub's lookup-by-id entry (what BigshotCreature#status/#type
  # fall back to) and as the source for the Creature stub's room roster, so a
  # single fixture describes "the same creature" the way both real systems
  # would report it.
  NpcFixture = Struct.new(:id, :name, :noun, :type, :status) do
    def to_s
      name
    end
  end

  class Harness
    # Stubs for the Lich globals the extracted bodies reach for. Nested here so
    # constant lookup inside the eval'd method bodies finds these, not the real
    # classes other specs load.

    # Minimal double for Lich::Gemstone::Creature::CreatureInstance. Only the
    # members id/noun/name are used by the method bodies extracted in this
    # file; crtr_flag?/has_status?/valid_target?/template are stubbed to
    # sensible defaults since nothing here reaches them (check_state_condition,
    # which does use them for the crtrStatus command checks, is not extracted
    # in this spec).
    FakeCreatureInstance = Struct.new(:id, :noun, :name, :flags) do
      def crtr_flag?(key)
        !!(flags || {})[key.to_sym]
      end

      def has_status?(_name)
        false
      end

      def valid_target?
        true
      end

      def template
        nil
      end
    end

    module Creature
      class << self
        attr_writer :room_targets

        def targets(*_filters)
          (@room_targets || []).dup
        end

        def in_room(*_filters)
          (@room_targets || []).dup
        end

        def [](id)
          (@room_targets || []).find { |c| c.id.to_i == id.to_i }
        end
      end
    end

    module GameObj
      class << self
        attr_writer :registry

        # Every fixture here is also a Creature instance, so the
        # bs_hostile_creatures GameObj bridge finds nothing to add - which is
        # what we want for the ranking tests.
        def targets
          []
        end

        def [](id)
          (@registry || {})[id]
        end
      end
    end

    module CharSettings
      class << self
        attr_accessor :store

        def [](key)
          store[key]
        end
      end
    end

    module XMLData
      class << self
        attr_accessor :current_target_id
      end
    end

    attr_accessor :PRIORITY, :TARGETS, :QUICKHUNT_TARGETS, :BOONS_IGNORE, :BOON_CACHE
    attr_reader :check_boons_calls, :fputs, :cmd_calls

    def initialize
      @PRIORITY = true
      @TARGETS = {}
      @QUICKHUNT_TARGETS = {}
      @BOONS_IGNORE = []
      @BOON_CACHE = {}
      @check_boons_calls = []
      @fputs = []
      @cmd_calls = []
      @unpickable = []
      @DEBUG_COMBAT = false
      @DEBUG_COMMANDS = false
      CharSettings.store = { 'untargetable' => [], 'targetable' => [] }
      GameObj.registry = {}
      Creature.room_targets = []
      XMLData.current_target_id = nil
    end

    def fput(command)
      @fputs << command
      XMLData.current_target_id = Regexp.last_match(1) if command =~ /\Atarget #(\d+)\z/
    end

    # Records what cmd_eachtarget asks of cmd. The other half of the contract,
    # that cmd honours check_priority, is locked by a source expectation below.
    def cmd(command, npc = nil, _stance_dance = true, check_priority: true)
      @cmd_calls << { command: command, npc: npc, check_priority: check_priority }
    end

    # Registers each fixture as both a GameObj entry (what the BigshotCreature
    # adapter's .status/.type fall back to) and a Creature room-roster entry
    # (what bs_targets/bs_room_creatures/Creature.targets iterate).
    def room(*fixtures)
      GameObj.registry = fixtures.each_with_object({}) { |f, h| h[f.id] = f }
      # hostile so bs_hostile_creatures keeps them; these fixtures stand in for
      # live attackable creatures.
      Creature.room_targets = fixtures.map do |f|
        FakeCreatureInstance.new(f.id.to_i, f.noun, f.name, { hostile: true })
      end
    end

    def untargetable(*names)
      CharSettings.store['untargetable'] = names
    end

    # find_target refuses these, standing in for the reasons valid_target? can
    # reject a creature that priority cannot see (ignored boons, flee checks).
    def cannot_pick(name)
      @unpickable << name
    end

    def debug_msg(*); end

    # Stands in for the real check_boons, which sends "assess #id" to the game
    # on a cache miss. Recording calls lets us prove priority never gets here.
    def check_boons(creature)
      @check_boons_calls << creature.id
      @BOON_CACHE[creature.id]
    end

    # Stands in for valid_target?, which probes the game with "target #id".
    def valid_target?(target, _just_entered = false)
      return false if target.nil?

      !@unpickable.include?(target.name)
    end

    eval(BIGSHOT_CREATURE_SRC)
    eval(BS_TARGETS_SRC)
    eval(BS_HOSTILE_SRC)
    eval(BS_ROOM_CREATURES_SRC)
    eval(PRIORITY_SRC)
    eval(MATCHERS_SRC)
    eval(RANK_SRC)
    eval(SORT_NPCS_SRC)
    eval(FIND_TARGET_SRC)
    eval(BOONS_SRC)
    eval(EACHTARGET_SRC)

    # Runs the real do_hunt retarget block with target bound as a local.
    def do_hunt_retarget(target)
      instance_eval("lambda { |target| #{DO_HUNT_RETARGET_SRC}\n target }", __FILE__, __LINE__).call(target)
    end

    # Runs the real follower retarget block, which reaches the script through bs.
    def follower_retarget(target)
      eval("lambda { |bs, target| #{FOLLOWER_RETARGET_SRC}\n target }").call(self, target)
    end
  end

  module Creatures
    def mastiff
      NpcFixture.new('101', 'stone mastiff', 'mastiff', 'aggressive npc', nil)
    end

    def mystic
      NpcFixture.new('102', 'illoke mystic', 'mystic', 'aggressive npc', nil)
    end

    def giant
      NpcFixture.new('103', 'stone giant', 'giant', 'aggressive npc', nil)
    end

    def shaman
      NpcFixture.new('104', 'illoke shaman', 'shaman', 'aggressive npc boon', nil)
    end

    def troll
      NpcFixture.new('105', 'ice troll', 'troll', 'aggressive npc', nil)
    end

    def second_mastiff
      NpcFixture.new('106', 'stone mastiff', 'mastiff', 'aggressive npc', nil)
    end

    # From the reported thrash: order was valravn, angargeist, disir
    def valravn
      NpcFixture.new('280414583', 'eyeless black valravn', 'valravn', 'aggressive npc', nil)
    end

    def angargeist
      NpcFixture.new('280405751', 'roiling crimson angargeist', 'angargeist', 'aggressive npc', nil)
    end

    def disir
      NpcFixture.new('280394883', 'shining winged disir', 'disir', 'aggressive npc', nil)
    end

    def draugr
      NpcFixture.new('280394876', 'withered shadow-cloaked draugr', 'draugr', 'aggressive npc', nil)
    end
  end
end

RSpec.describe 'bigshot Priority Hunt' do
  include BigshotPrioritySpec::Creatures

  let(:bs) { BigshotPrioritySpec::Harness.new }

  before do
    $bigshot_bandits = false
    $bigshot_quick = false
    # user-ordered list: mystic outranks mastiff, which outranks giant
    bs.TARGETS = { 'illoke mystic' => 'f', 'stone mastiff' => 'f', 'stone giant' => 'd' }
  end

  describe '#priority' do
    it 'returns false when there is no target' do
      bs.room(mastiff)
      expect(bs.priority(nil)).to be false
    end

    it 'does not interrupt bandit hunting' do
      $bigshot_bandits = true
      bs.room(mystic, mastiff)
      expect(bs.priority(mastiff)).to be true
    end

    it 'does not interrupt when Priority Hunt is disabled' do
      bs.PRIORITY = false
      bs.room(mystic, mastiff)
      expect(bs.priority(mastiff)).to be true
    end

    it 'accepts the target when it is the highest ranked creature in the room' do
      bs.room(mastiff, giant)
      expect(bs.priority(mastiff)).to be true
    end

    it 'rejects the target when a higher ranked creature is in the room' do
      bs.room(mastiff, mystic)
      expect(bs.priority(mastiff)).to be false
    end

    it 'accepts the target when a lower ranked creature joins the room' do
      bs.room(mastiff)
      expect(bs.priority(mastiff)).to be true

      bs.room(mastiff, giant)
      expect(bs.priority(mastiff)).to be true
    end

    it 'rejects the target on a later call, after the same room was already evaluated' do
      bs.room(mastiff)
      expect(bs.priority(mastiff)).to be true

      bs.room(mastiff, mystic)
      expect(bs.priority(mastiff)).to be false
    end

    it 'keeps rejecting the target while the higher ranked creature stays in the room' do
      bs.room(mastiff, mystic)
      expect(Array.new(5) { bs.priority(mastiff) }).to eq([false, false, false, false, false])
    end

    it 'accepts the target again once the higher ranked creature is gone' do
      bs.room(mastiff, mystic)
      expect(bs.priority(mastiff)).to be false

      bs.room(mastiff)
      expect(bs.priority(mastiff)).to be true
    end

    it 'ignores creatures on the untargetable list' do
      bs.untargetable('illoke mystic')
      bs.room(mastiff, mystic)
      expect(bs.priority(mastiff)).to be true
    end

    it 'accepts the target when none of the configured creatures are in the room' do
      bs.room(troll)
      expect(bs.priority(troll)).to be true
    end

    it 'matches a list entry against the creature noun' do
      bs.TARGETS = { 'mystic' => 'f', 'stone mastiff' => 'f' }
      bs.room(mastiff, mystic)

      expect(bs.priority(mystic)).to be true
      expect(bs.priority(mastiff)).to be false
    end

    it 'anchors matching so a partial list entry cannot claim a creature find_target could not pick' do
      bs.TARGETS = { 'illoke' => 'a', 'stone mastiff' => 'f' }
      bs.room(mastiff, mystic)

      expect(bs.sort_npcs.map(&:name)).to eq(['stone mastiff'])
      expect(bs.priority(mastiff)).to be true
    end

    it 'never assesses boons, because a priority check must not send commands' do
      bs.BOONS_IGNORE = ['spell warded']
      bs.TARGETS = { 'illoke shaman' => 'a', 'stone mastiff' => 'f' }
      bs.room(mastiff, shaman)

      expect(bs.priority(mastiff)).to be false
      expect(bs.check_boons_calls).to be_empty
    end

    it 'skips creatures whose already-assessed boons are on the ignore list' do
      bs.BOONS_IGNORE = ['spell warded']
      bs.BOON_CACHE['104'] = ['spell warded']
      bs.TARGETS = { 'illoke shaman' => 'a', 'stone mastiff' => 'f' }
      bs.room(mastiff, shaman)

      expect(bs.priority(mastiff)).to be true
    end
  end

  describe 'rank comparison' do
    # Creature.targets is rebuilt from the room roster on every call, so the
    # current target can be momentarily missing from it (e.g. between XML
    # updates). Ranking off the list rather than off list membership keeps
    # that from handing the fight to a lower ranked creature.
    it 'keeps the current target when the target itself is missing from the roster' do
      bs.room(giant)
      expect(bs.priority(mastiff)).to be true
    end

    it 'switches when a higher ranked creature is in the roster and the target is not' do
      bs.room(mystic)
      expect(bs.priority(mastiff)).to be false
    end

    it 'prefers a listed creature over an unlisted target' do
      bs.room(giant)
      expect(bs.priority(troll)).to be false
    end

    it 'does not treat a second creature matching the same entry as an interrupt' do
      bs.room(mastiff, second_mastiff)
      expect(bs.priority(mastiff)).to be true
      expect(bs.priority(second_mastiff)).to be true
    end
  end

  describe 'the reported retarget thrash' do
    before do
      bs.TARGETS = { 'valravn' => 'a', 'angargeist' => 'b', 'disir' => 'c' }
    end

    it 'settles on the angargeist once the valravn is known to be untargetable' do
      bs.untargetable('eyeless black valravn')
      bs.room(angargeist, disir, valravn)

      expect(bs.priority(angargeist)).to be true
      expect(bs.do_hunt_retarget(angargeist).name).to eq('roiling crimson angargeist')
    end

    it 'does not hand the fight to the disir when the angargeist drops out of the roster' do
      bs.untargetable('eyeless black valravn')
      bs.room(disir)

      expect(bs.priority(angargeist)).to be true
      expect(bs.do_hunt_retarget(angargeist).name).to eq('roiling crimson angargeist')
    end

    it 'keeps the angargeist while the valravn is still unclassified but unpickable' do
      bs.room(angargeist, disir, valravn)
      bs.cannot_pick('eyeless black valravn')

      # the valravn outranks everything, so the check does report an interrupt
      expect(bs.priority(angargeist)).to be false
      # but selection cannot pick it, so the fight stays on the angargeist
      expect(bs.do_hunt_retarget(angargeist).name).to eq('roiling crimson angargeist')
    end
  end

  describe 'do_hunt retargeting' do
    it 'switches to the higher ranked creature when one arrives mid fight' do
      bs.room(mastiff, mystic)
      expect(bs.do_hunt_retarget(mastiff).name).to eq('illoke mystic')
    end

    it 'stays on the current target when nothing outranks it' do
      bs.room(mastiff, giant)
      expect(bs.do_hunt_retarget(mastiff).name).to eq('stone mastiff')
    end

    it 'keeps the current target when the higher ranked creature cannot be picked' do
      bs.room(mastiff, mystic)
      bs.cannot_pick('illoke mystic')

      expect(bs.find_target(nil)).to be_nil
      expect(bs.do_hunt_retarget(mastiff).name).to eq('stone mastiff')
    end
  end

  describe 'follower retargeting' do
    it 'switches to the higher ranked creature through the accessor, not an unset ivar' do
      bs.room(mastiff, mystic)
      expect(bs.follower_retarget(mastiff).name).to eq('illoke mystic')
    end

    it 'honours the follower Priority Hunt setting' do
      bs.PRIORITY = false
      bs.room(mastiff, mystic)
      expect(bs.follower_retarget(mastiff).name).to eq('stone mastiff')
    end

    it 'keeps the current target when the higher ranked creature cannot be picked' do
      bs.room(mastiff, mystic)
      bs.cannot_pick('illoke mystic')
      expect(bs.follower_retarget(mastiff).name).to eq('stone mastiff')
    end
  end

  describe 'eachtarget sweeps' do
    # From the reported log: routine "eachtarget wandolier guarded noreserve" in a
    # room holding an angargeist (rank 1), a disir (rank 2) and a draugr (rank 12).
    # Each creature was targeted and then skipped, because the per-creature cmd
    # call hit the priority gate.
    before do
      bs.TARGETS = { 'valravn' => 'b', 'angargeist' => 'a', 'disir' => 'b', 'draugr' => 'a' }
      bs.room(angargeist, draugr, disir)
    end

    it 'issues the command against every creature in the room, not only the highest ranked one' do
      bs.cmd_eachtarget('wandolier guarded noreserve', angargeist)

      expect(bs.cmd_calls.map { |call| call[:npc].name })
        .to eq(['roiling crimson angargeist', 'withered shadow-cloaked draugr', 'shining winged disir'])
    end

    it 'asks cmd to skip the priority gate for creatures inside the sweep' do
      bs.cmd_eachtarget('wandolier guarded noreserve', angargeist)

      expect(bs.cmd_calls.map { |call| call[:check_priority] }).to all(be false)
    end

    it 'restores the original target after the sweep' do
      bs.cmd_eachtarget('wandolier guarded noreserve', angargeist)

      expect(bs.fputs.last).to eq("target ##{angargeist.id}")
    end

    it 'still skips creatures that cannot be picked' do
      bs.cannot_pick('shining winged disir')
      bs.cmd_eachtarget('wandolier guarded noreserve', angargeist)

      expect(bs.cmd_calls.map { |call| call[:npc].name }).not_to include('shining winged disir')
    end

    it 'keeps the priority gate on every other cmd caller' do
      expect(BigshotPrioritySpec::SOURCE).to match(/^    return if check_priority && @PRIORITY && !priority\(npc\)$/)
      expect(BigshotPrioritySpec::SOURCE).to match(/^  def cmd\(command, npc = nil, stance_dance = true, check_priority: true\)$/)
    end
  end

  describe 'the removed room snapshot cache' do
    it 'leaves no reference to the room composition globals or the snapshot thread' do
      expect(BigshotPrioritySpec::SOURCE).not_to match(/current_room_npcs|room_npcs_last_check|npc_room_check/)
    end
  end
end

# Spec for bigshot.lic's Phase 2 native crtrStatus/HP/UCS reads.
#
# Same extraction-and-eval approach as BigshotPrioritySpec above, but a
# separate Harness: this section exercises a different slice of bigshot -
# the BigshotCreature adapter boundary and the helpers that read
# Combat::Tracker data (dead_or_gone?, gone?, creature_backed?,
# npc_has_status?, npc_crtr_flag?, npc_low_hp?, npc_fatal_crit?,
# npc_smote?, npc_ucs_position, npc_ucs_tierup, leader_target?) - rather
# than targeting/ranking. Kept independent of BigshotPrioritySpec's Harness
# so neither section's stub state can leak into the other.
module BigshotCreatureAdapterSpec
  SOURCE_PATH = find_lic_source('bigshot.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")

  def self.extract(pattern, label)
    extract_from_source(SOURCE, pattern, label: label, source_path: SOURCE_PATH)
  end

  BIGSHOT_CREATURE_SRC = extract(/^class BigshotCreature\n.*?^end$/m, 'BigshotCreature')
  BS_ROOM_CREATURES_SRC = extract(/^  def bs_room_creatures\(\*filters\).*?^  end$/m, 'bs_room_creatures')
  BS_HOSTILE_SRC = extract(/^  def bs_hostile_creatures\(\*filters\).*?^  end$/m, 'bs_hostile_creatures')
  BS_TARGETS_SRC = extract(/^  def bs_targets\(\*filters\).*?^  end$/m, 'bs_targets')
  CREATURE_BACKED_SRC = extract(/^  def creature_backed\?\(npc\).*?^  end$/m, 'creature_backed?')
  DEAD_OR_GONE_SRC = extract(/^  def dead_or_gone\?\(npc\).*?^  end$/m, 'dead_or_gone?')
  GONE_SRC = extract(/^  def gone\?\(npc\).*?^  end$/m, 'gone?')
  NPC_HAS_STATUS_SRC = extract(/^  def npc_has_status\?\(npc, status_name\).*?^  end$/m, 'npc_has_status?')
  NPC_CRTR_FLAG_SRC = extract(/^  def npc_crtr_flag\?\(npc, flag\).*?^  end$/m, 'npc_crtr_flag?')
  NPC_FROZEN_SRC = extract(/^  def npc_frozen\?\(npc\).*?^  end$/m, 'npc_frozen?')
  NPC_PRONE_SRC = extract(/^  def npc_prone\?\(npc\).*?^  end$/m, 'npc_prone?')
  PRONE_CONSTS_SRC = extract(/^  PRONE \|\|=.*?^  PRONE_STATUSES \|\|=.*?$/m, 'PRONE constants')
  NPC_LOW_HP_SRC = extract(/^  def npc_low_hp\?\(npc, threshold = 25\).*?^  end$/m, 'npc_low_hp?')
  NPC_FATAL_CRIT_SRC = extract(/^  def npc_fatal_crit\?\(npc\).*?^  end$/m, 'npc_fatal_crit?')
  NPC_SMOTE_SRC = extract(/^  def npc_smote\?\(npc\).*?^  end$/m, 'npc_smote?')
  NPC_UCS_POSITION_SRC = extract(/^  def npc_ucs_position\(npc\).*?^  end$/m, 'npc_ucs_position')
  NPC_UCS_TIERUP_SRC = extract(/^  def npc_ucs_tierup\(npc\).*?^  end$/m, 'npc_ucs_tierup')
  LEADER_TARGET_SRC = extract(/^  def leader_target\?\n.*?^  end$/m, 'leader_target?')

  # Configurable double for CreatureInstance. statuses/flags start empty so
  # each test opts in only to the state it's asserting on - a status/flag
  # that isn't set behaves exactly like the real has_status?/crtr_flag?
  # default (false).
  FakeCreatureInstance = Struct.new(:id, :noun, :name, :statuses, :flags, :low_hp, :fatal_crit, :smote, :ucs_pos, :ucs_tierup, :valid_target_override) do
    def initialize(*)
      super
      self.statuses ||= []
      self.flags ||= {}
    end

    def has_status?(status_name)
      statuses.include?(status_name.to_s)
    end

    def crtr_flag?(key)
      !!flags[key.to_sym]
    end

    # Real CreatureInstance#valid_target? is false whenever the guessed
    # max_hp/damage_taken heuristic says #dead? - independently of the live
    # <crtrStatus> dead flag. valid_target_override lets a test put the
    # double into that same divergent state without a real damage model.
    def valid_target?
      return valid_target_override unless valid_target_override.nil?

      !crtr_flag?(:dead)
    end

    def template
      nil
    end

    def low_hp?(_threshold = 25)
      !!low_hp
    end

    def fatal_crit?
      !!fatal_crit
    end

    def smote?
      !!smote
    end

    def ucs_position
      ucs_pos
    end
  end

  # A bare GameObj-shaped double with no .creature accessor at all - what
  # leader_target? falls back to when GameObj.target has no matching Creature
  # registry entry, and the shape creature_backed? must recognize as false.
  RawGameObj = Struct.new(:id, :noun, :name, :status, :type) do
    def to_s
      name
    end
  end

  class Harness
    module Creature
      class << self
        attr_writer :room_targets, :registry

        def in_room(*_filters)
          (@room_targets || []).dup
        end

        def [](id)
          (@registry || {})[id.to_i]
        end
      end
    end

    module GameObj
      class << self
        attr_accessor :target
        attr_accessor :registry
        attr_writer :target_list

        def [](id)
          (@registry || {})[id]
        end

        # Stands in for the real GameObj.targets, which bs_hostile_creatures
        # bridges from for creatures Creature cannot represent (bandits).
        def targets
          (@target_list || []).dup
        end
      end
    end

    def initialize
      Creature.room_targets = []
      Creature.registry = {}
      GameObj.registry = {}
      GameObj.target = nil
      GameObj.target_list = []
    end

    # Registers a creature in both the Creature id registry and the current
    # room roster, wrapped for the methods under test the way bs_room_creatures
    # would wrap it.
    def room(*fake_creatures)
      Creature.room_targets = fake_creatures
      Creature.registry = fake_creatures.each_with_object({}) { |c, h| h[c.id] = c }
    end

    def wrap(fake_creature)
      BigshotCreature.new(fake_creature)
    end

    eval(BIGSHOT_CREATURE_SRC)
    eval(BS_ROOM_CREATURES_SRC)
    eval(BS_HOSTILE_SRC)
    eval(BS_TARGETS_SRC)
    eval(CREATURE_BACKED_SRC)
    eval(DEAD_OR_GONE_SRC)
    eval(GONE_SRC)
    eval(NPC_HAS_STATUS_SRC)
    eval(NPC_CRTR_FLAG_SRC)
    eval(PRONE_CONSTS_SRC)
    eval(NPC_FROZEN_SRC)
    eval(NPC_PRONE_SRC)
    eval(NPC_LOW_HP_SRC)
    eval(NPC_FATAL_CRIT_SRC)
    eval(NPC_SMOTE_SRC)
    eval(NPC_UCS_POSITION_SRC)
    eval(NPC_UCS_TIERUP_SRC)
    eval(LEADER_TARGET_SRC)
  end

  RSpec.describe 'BigshotCreature adapter and native crtrStatus/HP/UCS reads' do
    subject(:bs) { Harness.new }

    # bigshot's PRONE constant, as evaluated into the harness.
    def described_class_prone_regex
      Harness::PRONE
    end

    let(:goblin) { FakeCreatureInstance.new(201, 'goblin', 'a snarling goblin') }

    describe '#creature_backed?' do
      it 'is true for a BigshotCreature wrapping a real CreatureInstance' do
        expect(bs.creature_backed?(bs.wrap(goblin))).to be true
      end

      it 'is false for a bare GameObj-shaped double with no .creature accessor' do
        raw = RawGameObj.new('201', 'goblin', 'a snarling goblin', nil, 'aggressive npc')
        expect(bs.creature_backed?(raw)).to be false
      end

      it 'is false for nil' do
        expect(bs.creature_backed?(nil)).to be false
      end
    end

    describe '#status (BigshotCreature, no matching GameObj entry yet)' do
      it 'is "dead" when the live dead flag is set' do
        goblin.flags[:dead] = true
        bs.room(goblin)

        expect(bs.wrap(goblin).status).to eq('dead')
      end

      it 'is nil for a live, present creature' do
        bs.room(goblin)

        expect(bs.wrap(goblin).status).to be_nil
      end

      it 'does NOT synthesize "gone" from valid_target? for a live creature the damage heuristic misjudges' do
        # Regression guard: real CreatureInstance#valid_target? is false
        # whenever the guessed max_hp/damage_taken heuristic says #dead?,
        # independently of the live <crtrStatus> dead flag. Synthesizing
        # "gone" from that would feed straight into dead_or_gone?/gone? and
        # misreport a live creature - the exact failure mode this migration
        # exists to avoid (see the module-level migration notes).
        goblin.valid_target_override = false
        bs.room(goblin)

        expect(bs.wrap(goblin).status).to be_nil
        expect(bs.dead_or_gone?(bs.wrap(goblin))).to be false
        expect(bs.gone?(bs.wrap(goblin))).to be false
      end
    end

    describe '#dead_or_gone?' do
      it 'is true when the live dead flag is set, regardless of room presence' do
        goblin.flags[:dead] = true
        bs.room(goblin)

        expect(bs.dead_or_gone?(bs.wrap(goblin))).to be true
      end

      it 'does NOT report a live creature as gone merely because it dropped out of the room roster' do
        # Creature.clear_room fires on every room-objs refresh and only
        # re-registers an object when a fresh <crtrStatus> arrives for it or
        # its id is in the client's target dropdown. Treating roster absence
        # as death made bigshot abandon live creatures for a tick.
        bs.room # empty roster, but the creature is alive and has no dead flag

        expect(bs.dead_or_gone?(bs.wrap(goblin))).to be false
      end

      it 'is true when the GameObj status says gone' do
        bs.room(goblin)
        Harness::GameObj.registry = { '201' => RawGameObj.new('201', 'goblin', 'a snarling goblin', 'gone', nil) }

        expect(bs.dead_or_gone?(bs.wrap(goblin))).to be true
      end

      it 'is false for a live, present creature' do
        bs.room(goblin)

        expect(bs.dead_or_gone?(bs.wrap(goblin))).to be false
      end

      it 'falls back to the GameObj status regex for a non-creature-backed npc' do
        raw = RawGameObj.new('201', 'goblin', 'a snarling goblin', 'dead', 'aggressive npc')
        expect(bs.dead_or_gone?(raw)).to be true

        raw.status = nil
        expect(bs.dead_or_gone?(raw)).to be false
      end

      it 'is true for nil' do
        expect(bs.dead_or_gone?(nil)).to be true
      end
    end

    describe '#gone?' do
      it 'does NOT trivially return true for an already-dead creature still in the room' do
        # Regression guard: gone? must stay narrower than dead_or_gone? or the
        # dead_npcs loot loop (which only ever holds already-dead entries)
        # would skip every corpse instead of looting it.
        goblin.flags[:dead] = true
        bs.room(goblin)

        expect(bs.gone?(bs.wrap(goblin))).to be false
      end

      it 'is true once the GameObj status says gone, not merely on roster absence' do
        bs.room # roster absence alone must not count
        expect(bs.gone?(bs.wrap(goblin))).to be false

        Harness::GameObj.registry = { '201' => RawGameObj.new('201', 'goblin', 'a snarling goblin', 'gone', nil) }
        expect(bs.gone?(bs.wrap(goblin))).to be true
      end
    end

    describe '#npc_has_status?' do
      it 'reads the live status list' do
        goblin.statuses << 'stunned'

        expect(bs.npc_has_status?(bs.wrap(goblin), 'stunned')).to be true
        expect(bs.npc_has_status?(bs.wrap(goblin), 'webbed')).to be false
      end

      it 'degrades to false rather than raising for a non-creature-backed npc' do
        raw = RawGameObj.new('201', 'goblin', 'a snarling goblin', nil, nil)
        expect { bs.npc_has_status?(raw, 'stunned') }.not_to raise_error
        expect(bs.npc_has_status?(raw, 'stunned')).to be false
      end
    end

    describe '#npc_crtr_flag?' do
      it 'reads the live classification flags' do
        goblin.flags[:mini_boss] = true

        expect(bs.npc_crtr_flag?(bs.wrap(goblin), :mini_boss)).to be true
        expect(bs.npc_crtr_flag?(bs.wrap(goblin), :ascended)).to be false
      end
    end

    describe '#npc_frozen? ("frozen" is the immobilized status)' do
      it 'reads the native immobilized status, which the legacy string match misses' do
        # The room text renders this as "(immobile)", so GameObj's status
        # string never contains "frozen" for an XML-driven immobilize.
        goblin.statuses << 'immobilized'
        bs.room(goblin)
        Harness::GameObj.registry = { '201' => RawGameObj.new('201', 'goblin', 'a snarling goblin', 'immobile', nil) }

        expect(bs.npc_frozen?(bs.wrap(goblin))).to be true
      end

      it 'still honours the legacy GameObj "frozen" string as a fallback' do
        bs.room(goblin) # no immobilized status set
        Harness::GameObj.registry = { '201' => RawGameObj.new('201', 'goblin', 'a snarling goblin', 'frozen', nil) }

        expect(bs.npc_frozen?(bs.wrap(goblin))).to be true
      end

      it 'is false when the creature is neither' do
        bs.room(goblin)

        expect(bs.npc_frozen?(bs.wrap(goblin))).to be false
      end

      it 'is false for a nil npc rather than raising' do
        expect(bs.npc_frozen?(nil)).to be false
      end
    end

    describe '#npc_prone? (crtrStatus carries several statuses; GameObj.status carries one)' do
      it 'sees prone on a creature whose room text advertises a different status' do
        # Straight from a real feed line:
        #   <crtrStatus exist="153281570" hostile="1" stunned="1" prone="1" inferior="1"/>
        #   ...<a exist="153281570" noun="dybbuk">dybbuk</a> that appears stunned.
        # The parser assigns a single capture, so GameObj.status is "stunned"
        # even though the creature is also prone. The old regex also returned
        # true here (because "stunned" is itself in PRONE); this asserts the
        # native read reaches the same answer from the accurate source.
        dybbuk = FakeCreatureInstance.new(153281570, 'dybbuk', 'a dybbuk')
        dybbuk.flags[:hostile] = true
        dybbuk.flags[:inferior] = true
        dybbuk.statuses.push('stunned', 'prone')
        bs.room(dybbuk)
        Harness::GameObj.registry = {
          '153281570' => RawGameObj.new('153281570', 'dybbuk', 'a dybbuk', 'stunned', nil)
        }

        expect(bs.npc_prone?(bs.wrap(dybbuk))).to be true
      end

      it 'catches a prone creature whose single status annotation is NOT in the PRONE regex' do
        # The case the string match misses outright rather than by luck.
        creature = FakeCreatureInstance.new(501, 'dybbuk', 'a dybbuk')
        creature.statuses << 'prone'
        bs.room(creature)
        Harness::GameObj.registry = {
          '501' => RawGameObj.new('501', 'dybbuk', 'a dybbuk', 'disoriented', nil)
        }

        expect(bs.npc_prone?(bs.wrap(creature))).to be true
      end

      it 'treats immobilized as prone, covering frozen/entangled/held in place' do
        creature = FakeCreatureInstance.new(502, 'goblin', 'a snarling goblin')
        creature.statuses << 'immobilized'
        bs.room(creature)

        expect(bs.npc_prone?(bs.wrap(creature))).to be true
      end

      it 'agrees with the old regex on a prone-only creature, which really renders "lying down"' do
        # Measured from real GS4 logs: prone alone renders
        # "that is lying down.", so GameObj.status is "lying down" and the
        # old ^lying regex matched it too. Both paths must say true - this
        # guards against anyone "fixing" one of them apart from the other.
        creature = FakeCreatureInstance.new(503, 'worm', 'a carrion worm')
        creature.statuses << 'prone'
        bs.room(creature)
        Harness::GameObj.registry = {
          '503' => RawGameObj.new('503', 'worm', 'a carrion worm', 'lying down', nil)
        }

        expect(bs.npc_prone?(bs.wrap(creature))).to be true
      end

      it 'sees prone that the status string masks behind "dead"' do
        # The one masking case the string cannot express, from real logs:
        #   <crtrStatus ... hostile="1" dead="1" prone="1"/> ... "that appears dead."
        # dead_or_gone? gates before this matters, but the native read is
        # the only path that can see it.
        corpse = FakeCreatureInstance.new(504, 'fanatic', 'a triton fanatic')
        corpse.statuses << 'prone'
        corpse.flags[:dead] = true
        bs.room(corpse)
        Harness::GameObj.registry = {
          '504' => RawGameObj.new('504', 'fanatic', 'a triton fanatic', 'dead', nil)
        }

        wrapped = bs.wrap(corpse)
        expect(wrapped.status =~ described_class_prone_regex).to be_nil # string cannot see it
        expect(bs.npc_prone?(wrapped)).to be true
      end

      it 'falls back to the regex for an npc with no CreatureInstance behind it' do
        # Bridged bandits and leader_target?'s fallback have no statuses to
        # read, so the status string is all there is. "lying down" is the
        # room-players phrasing for the same state crtrStatus calls prone.
        raw = RawGameObj.new('88802', 'bandit', 'a grizzled bandit', 'lying down', nil)

        expect(bs.creature_backed?(raw)).to be false
        expect(bs.npc_prone?(raw)).to be true
      end

      it 'is false for an upright creature, and nil-safe' do
        bs.room(goblin)

        expect(bs.npc_prone?(bs.wrap(goblin))).to be false
        expect(bs.npc_prone?(nil)).to be false
      end
    end

    describe 'HP/UCS readers' do
      it 'npc_low_hp? reads the tracked low-HP state' do
        goblin.low_hp = true
        expect(bs.npc_low_hp?(bs.wrap(goblin))).to be true
      end

      it 'npc_fatal_crit? reads the tracked fatal-crit flag' do
        goblin.fatal_crit = true
        expect(bs.npc_fatal_crit?(bs.wrap(goblin))).to be true
      end

      it 'npc_smote? reads the tracked smite state' do
        goblin.smote = true
        expect(bs.npc_smote?(bs.wrap(goblin))).to be true
      end

      it 'npc_ucs_position/npc_ucs_tierup read the tracked UCS state' do
        goblin.ucs_pos = 2
        goblin.ucs_tierup = 'kick'

        wrapped = bs.wrap(goblin)
        expect(bs.npc_ucs_position(wrapped)).to eq(2)
        expect(bs.npc_ucs_tierup(wrapped)).to eq('kick')
      end

      it 'all degrade to a safe default rather than raising for a non-creature-backed npc' do
        raw = RawGameObj.new('201', 'goblin', 'a snarling goblin', nil, nil)

        expect(bs.npc_low_hp?(raw)).to be false
        expect(bs.npc_fatal_crit?(raw)).to be false
        expect(bs.npc_smote?(raw)).to be false
        expect(bs.npc_ucs_position(raw)).to be_nil
        expect(bs.npc_ucs_tierup(raw)).to be_nil
      end
    end

    describe '#leader_target?' do
      it 'returns nil when the client has no selected target' do
        Harness::GameObj.target = nil
        expect(bs.leader_target?).to be_nil
      end

      it 'wraps the selected target in BigshotCreature when a Creature registry entry exists' do
        bs.room(goblin)
        Harness::GameObj.target = RawGameObj.new('201', 'goblin', 'a snarling goblin', nil, nil)

        result = bs.leader_target?
        expect(bs.creature_backed?(result)).to be true
        expect(result.name).to eq('a snarling goblin')
      end

      it 'falls back to the raw GameObj when no Creature registry entry exists yet' do
        raw = RawGameObj.new('999', 'orc', 'a hulking orc', nil, nil)
        bs.room # instantiates bs (which resets GameObj.target) before we set it below
        Harness::GameObj.target = raw

        result = bs.leader_target?
        expect(bs.creature_backed?(result)).to be false
        expect(result).to equal(raw)
      end
    end

    describe 'targeting must not depend on Combat::Tracker HP estimates' do
      # CreatureInstance#valid_target? (and therefore Creature.targets) is
      # false once #dead? is true, where #dead? means
      # `max_hp - damage_taken <= 0`. damage_taken is accumulated by
      # Combat::Tracker from every damage number in the feed, is never reset,
      # and max_hp is often a guess (131 of 611 bundled templates carry
      # max_hp: nil -> fallback/400). Group hunting over-attributes damage
      # roughly per-member. If bigshot trusted that, a live creature would
      # silently vanish from its target list mid-fight.
      it 'keeps a creature the tracker believes is dead when the game has not flagged it dead' do
        tracker_thinks_dead = FakeCreatureInstance.new(301, 'kraken', 'an ancient kraken')
        tracker_thinks_dead.flags[:hostile] = true
        # simulates damage_taken >= max_hp with no <crtrStatus> dead flag
        def tracker_thinks_dead.valid_target? = false

        bs.room(tracker_thinks_dead)

        expect(bs.bs_hostile_creatures.map(&:id)).to include(301)
        expect(bs.bs_targets.map(&:id)).to include('301')
      end

      it 'drops a creature the game itself flags dead over <crtrStatus>' do
        really_dead = FakeCreatureInstance.new(302, 'goblin', 'a snarling goblin')
        really_dead.flags[:hostile] = true
        really_dead.flags[:dead] = true

        bs.room(really_dead)

        expect(bs.bs_hostile_creatures).to be_empty
      end

      it 'excludes appendages and animated decoys, as GameObj.targets did' do
        # These only ever lived in should_flee?/gameobj_npc_check inside
        # bigshot - neither is on the sort_npcs -> find_target selection path -
        # so dropping them here would let bigshot attack a severed limb.
        arm = FakeCreatureInstance.new(401, 'arm', 'severed troll arm')
        arm.flags[:hostile] = true
        # Real GS creature names carry no leading article (the bundled
        # templates are 'animated guardian', 'animated slush', ...), so
        # upstream's anchored /^animated\b/ does fire on them.
        decoy = FakeCreatureInstance.new(402, 'guardian', 'animated guardian')
        decoy.flags[:hostile] = true
        slush = FakeCreatureInstance.new(403, 'slush', 'animated slush')
        slush.flags[:hostile] = true
        kraken = FakeCreatureInstance.new(404, 'tentacle', 'ghostly kraken tentacle')
        kraken.flags[:hostile] = true

        bs.room(arm, decoy, slush, kraken)

        ids = bs.bs_hostile_creatures.map(&:id)
        expect(ids).not_to include(401)
        expect(ids).not_to include(402)
        # carve-outs upstream keeps, so we keep them too
        expect(ids).to include(403)
        expect(ids).to include(404)
      end

      it 'drops a non-hostile creature' do
        bystander = FakeCreatureInstance.new(303, 'child', 'a frightened child')

        bs.room(bystander)

        expect(bs.bs_hostile_creatures).to be_empty
      end
    end

    describe 'GameObj-only targets (bandits) must still reach the targeting pipeline' do
      # bandit_track manufactures its quarry with GameObj.new_npc after
      # scraping a manual "look", because bandits never appear in the normal
      # room feed. Creature.register is therefore never called for them, and
      # they could not carry crtr_flag?(:hostile) even if it were, since that
      # flag only ever comes from a <crtrStatus> tag they never send. Sourcing
      # targets purely from Creature silently broke $bigshot_bandits: the
      # bandit was found, added to XMLData.current_target_ids, and then never
      # targeted.
      let(:bandit) { RawGameObj.new('88801', 'bandit', 'a grizzled bandit', nil, 'aggressive npc') }

      it 'bridges in a GameObj target that Creature has no instance for' do
        bs.room # Creature knows about nothing at all
        Harness::GameObj.target_list = [bandit]

        expect(bs.bs_hostile_creatures).to include(bandit)
        expect(bs.bs_targets.map(&:id)).to include('88801')
      end

      it 'hands the bridged GameObj through unwrapped, and it degrades safely' do
        bs.room
        Harness::GameObj.target_list = [bandit]

        picked = bs.bs_targets.find { |t| t.id == '88801' }
        expect(picked).not_to be_nil # else the assertions below pass vacuously
        expect(picked).to equal(bandit) # handed through, not wrapped
        expect(bs.creature_backed?(picked)).to be false
        expect { bs.npc_has_status?(picked, 'stunned') }.not_to raise_error
        expect(bs.npc_has_status?(picked, 'stunned')).to be false
      end

      it 'does not double-list a creature Creature already knows about' do
        # Anything Creature can represent stays on the native roster, so the
        # stale client-dropdown behavior this migration escaped cannot leak
        # back in for ordinary creatures.
        goblin.flags[:hostile] = true
        bs.room(goblin)
        Harness::GameObj.target_list = [RawGameObj.new('201', 'goblin', 'a snarling goblin', nil, nil)]

        expect(bs.bs_hostile_creatures.size).to eq(1)
        expect(bs.bs_hostile_creatures.first).to equal(goblin)
      end
    end

    describe 'GameObj.npcs presence checks that must NOT be migrated to Creature.in_room' do
      # lib/common/xmlparser.rb only registers a room object into Creature
      # (and re-marks it present on every subsequent room-objs refresh, which
      # fires far more often than a full room change) when a live
      # <crtrStatus> tag arrives for it or its id is in the client's target
      # dropdown (XMLData.current_target_ids). GameObj.npcs has no such gate.
      # A corpse that stops getting <crtrStatus> updates post-mortem, or a
      # named-but-not-currently-hostile NPC (a bounty rescue target, a feared
      # creature that hasn't aggroed yet), can be a real, present room object
      # while invisible to Creature.in_room/bs_room_creatures. These specific
      # call sites were migrated to Creature.in_room and then reverted after
      # tracing that gate in the real parser source - this guards against a
      # future re-migration repeating the mistake without knowing why.
      it 'keeps loot()/need_to_loot?/should_flee?/the bounty child-rescue check on GameObj.npcs' do
        expect(SOURCE).to match(/dead_npcs = GameObj\.npcs\.find_all \{ \|i\| i\.status == 'dead' && i\.type !~ \/escort\/i \}/)
        expect(SOURCE).to match(/break unless GameObj\.npcs\.any\? \{ \|npc\| npc\.status == 'dead' && npc\.type !~ \/escort\/i \}/)
        expect(SOURCE).to match(/GameObj\.npcs\.any\? \{ \|i\| @ALWAYS_FLEE_FROM\.include\?\(i\.noun\) or @ALWAYS_FLEE_FROM\.include\?\(i\.name\) \}/)
        expect(SOURCE).to match(/GameObj\.npcs\.find \{ \|n\| n\.name =~ \/child\/i \}/)
        expect(SOURCE).to match(/GameObj\.npcs\.any\? \{ \|npc\| npc\.name =~ \/\\\\bchild\\\\b\/ \}/)
      end
    end
  end
end
