# Spec for bigshot.lic Priority Hunt retargeting.
#
# We do NOT load the .lic file: it needs the whole Lich runtime (Settings,
# XMLData, Spell, GTK, DRb ...). Instead the real method bodies are extracted
# from scripts/bigshot.lic and evaluated against stubs, so these specs exercise
# production code and fail if that code changes shape.
#
# Every stub lives inside BigshotPrioritySpec::Harness rather than at top level,
# so running the whole suite in one process cannot collide with the real GameObj
# used by the gameobj-data specs.
#
# Deliberately no NilClass patch here. Lich patches NilClass#method_missing to
# return nil (lich-5 lib/common/class_exts/nilclass.rb), which is what let the
# removed room-composition cache paper over nil comparisons. This code must not
# depend on that.

module BigshotPrioritySpec
  SOURCE_PATH = File.expand_path('../../scripts/bigshot.lic', __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")

  def self.extract(pattern, label)
    found = SOURCE[pattern]
    raise "could not extract #{label} from bigshot.lic" unless found

    found
  end

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

  Creature = Struct.new(:id, :name, :noun, :type, :status) do
    def to_s
      name
    end
  end

  class Harness
    # Stubs for the Lich globals the extracted bodies reach for. Nested here so
    # constant lookup inside the eval'd method bodies finds these, not the real
    # classes other specs load.
    module GameObj
      class << self
        attr_writer :room_targets

        def targets
          (@room_targets || []).dup
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
      GameObj.room_targets = []
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

    def room(*creatures)
      GameObj.room_targets = creatures
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
      Creature.new('101', 'stone mastiff', 'mastiff', 'aggressive npc', nil)
    end

    def mystic
      Creature.new('102', 'illoke mystic', 'mystic', 'aggressive npc', nil)
    end

    def giant
      Creature.new('103', 'stone giant', 'giant', 'aggressive npc', nil)
    end

    def shaman
      Creature.new('104', 'illoke shaman', 'shaman', 'aggressive npc boon', nil)
    end

    def troll
      Creature.new('105', 'ice troll', 'troll', 'aggressive npc', nil)
    end

    def second_mastiff
      Creature.new('106', 'stone mastiff', 'mastiff', 'aggressive npc', nil)
    end

    # From the reported thrash: order was valravn, angargeist, disir
    def valravn
      Creature.new('280414583', 'eyeless black valravn', 'valravn', 'aggressive npc', nil)
    end

    def angargeist
      Creature.new('280405751', 'roiling crimson angargeist', 'angargeist', 'aggressive npc', nil)
    end

    def disir
      Creature.new('280394883', 'shining winged disir', 'disir', 'aggressive npc', nil)
    end

    def draugr
      Creature.new('280394876', 'withered shadow-cloaked draugr', 'draugr', 'aggressive npc', nil)
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
    # GameObj.targets is the game's target dropdown (xmlparser dDBTarget), which
    # is cleared and rebuilt wholesale, so the current target can be missing from
    # it for a moment. Ranking off the list rather than off dropdown membership
    # keeps that from handing the fight to a lower ranked creature.
    it 'keeps the current target when the target itself is missing from the dropdown' do
      bs.room(giant)
      expect(bs.priority(mastiff)).to be true
    end

    it 'switches when a higher ranked creature is in the dropdown and the target is not' do
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

    it 'does not hand the fight to the disir when the angargeist drops out of the dropdown' do
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
