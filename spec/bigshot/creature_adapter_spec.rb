# Spec for bigshot.lic's Phase 2 native crtrStatus/HP/UCS reads.
#
# Same extraction-and-eval approach as priority_spec.rb (see that file's
# header for the rationale) but a separate Harness: this file exercises a
# different slice of bigshot - the BigshotCreature adapter boundary and the
# helpers that read Combat::Tracker data (dead_or_gone?, gone?,
# creature_backed?, npc_has_status?, npc_crtr_flag?, npc_low_hp?,
# npc_fatal_crit?, npc_smote?, npc_ucs_position, npc_ucs_tierup,
# leader_target?) - rather than targeting/ranking. Kept independent of
# priority_spec.rb's Harness so neither file's stub state can leak into the
# other.

module BigshotCreatureAdapterSpec
  SOURCE_PATH = File.expand_path('../../scripts/bigshot.lic', __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")

  def self.extract(pattern, label)
    found = SOURCE[pattern]
    raise "could not extract #{label} from bigshot.lic" unless found

    found
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
