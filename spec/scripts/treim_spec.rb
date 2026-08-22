# frozen_string_literal: true

require_relative '../spec_helper'

# Spec for the pure/near-pure Treim:: modules in treim.lic (REIM reactive
# script). treim.lic cannot be required standalone -- it needs the whole
# Lich runtime and runs `Treim.start` on load. Instead each nested
# module/class body is extracted verbatim from scripts/treim.lic and
# module_eval'd into a shared Harness namespace, so these specs exercise the
# production code (and fail if it changes shape) without needing a live
# game session.
#
# Most of the Lich runtime stand-ins these extracted modules need
# (UserVars, Char, Script, Spell, Lich::Util, Lich::Common::Frontend, plus
# the bare waitrt?/fput/put/pause/checkstance game-command methods) come
# from spec/spec_helper.rb, shared with the rest of this repo's .lic-script
# specs. Two things stay local to this file:
#
# - GameObj: spec_helper.rb deliberately does not provide one (see its own
#   header comment) because lib/lich/gameobj.rb defines a real, top-level
#   GameObj class that spec/gameobj-data exercises directly, and a shared
#   top-level stub would silently corrupt it for every spec file loaded in
#   the same rspec process. This file's GameObj lives nested inside Harness
#   instead, matching spec/bigshot/priority_spec.rb's precedent.
# - Group: spec_helper.rb's Group stub *is* defined at the true top level,
#   unlike everything else there -- because treim.lic's Party module reaches
#   for it via an explicitly absolute `::Group`, not a bare `Group`, so only
#   a genuine top-level constant satisfies that reference. Nothing else in
#   this repo defines a top-level Group, so it's safe to share; no local
#   alias is needed here since `::Group` bypasses lexical nesting entirely.
#
# Extracting every treim.lic piece into ONE shared Harness namespace (rather
# than isolated namespaces per piece, as spec/scripts/ledger_spec.rb does)
# matters here: treim.lic's modules refer to each other by bare constant
# (Attack calls Config.stance_dance?, ClearProgress reaches for GameObj,
# ...). Evaluating them all under Harness reproduces the same lexical
# nesting they have under `module Treim` in the real file, so those bare
# references resolve the same way -- which is also why the shared stand-ins
# above are aliased into Harness below rather than left as bare
# `LichStub::` constants: treim.lic's own code never says `LichStub::`.
#
# Runner (the main reactive loop) is deliberately not covered here: it's a
# thin dispatcher over live game state (GameObj.npcs, Room.current, get,
# XMLData) that would need a much larger integration-style harness to
# exercise meaningfully, and the review that requested this coverage called
# out the same tradeoff for the two `Lich::Util.issue_command`/`Group`-based
# call sites -- those need a live session, not more stubbing.

SOURCE_PATH = find_lic_source('treim.lic', from: __dir__)
SOURCE = File.read(SOURCE_PATH)

GEOGRAPHY_SRC       = extract_lic_module(SOURCE, 'Geography', source_path: SOURCE_PATH)
BOSSES_SRC          = extract_lic_module(SOURCE, 'Bosses', source_path: SOURCE_PATH)
SEEN_IDS_SRC        = extract_lic_module(SOURCE, 'SeenIds', kind: 'class', source_path: SOURCE_PATH)
CONFIG_SRC          = extract_lic_module(SOURCE, 'Config', source_path: SOURCE_PATH)
ATTACK_SRC          = extract_lic_module(SOURCE, 'Attack', source_path: SOURCE_PATH)
CLEAR_PROGRESS_SRC  = extract_lic_module(SOURCE, 'ClearProgress', source_path: SOURCE_PATH)
PARTY_SRC           = extract_lic_module(SOURCE, 'Party', source_path: SOURCE_PATH)
FAMILIAR_WINDOW_SRC = extract_lic_module(SOURCE, 'FamiliarWindow', source_path: SOURCE_PATH)

FakeNpc = LichStub::FakeNpc

module Harness
  # Nested here, not shared via spec_helper.rb -- see the file header.
  class GameObj
    class << self
      attr_accessor :npcs
    end
  end

  UserVars = LichStub::UserVars
  Char = LichStub::Char
  Script = LichStub::Script
  Spell = LichStub::Spell
  Lich = LichStub::Lich

  module_eval(GEOGRAPHY_SRC, SOURCE_PATH)
  module_eval(BOSSES_SRC, SOURCE_PATH)
  module_eval(SEEN_IDS_SRC, SOURCE_PATH)
  module_eval(CONFIG_SRC, SOURCE_PATH)
  module_eval(ATTACK_SRC, SOURCE_PATH)
  module_eval(CLEAR_PROGRESS_SRC, SOURCE_PATH)
  module_eval(PARTY_SRC, SOURCE_PATH)
  module_eval(FAMILIAR_WINDOW_SRC, SOURCE_PATH)
end

RSpec.describe 'Treim' do
  before do
    Harness::Char.name = 'Tysong'
    Harness::GameObj.npcs = []
  end

  # -- Geography -----------------------------------------------------------

  describe 'Geography' do
    it 'recognizes every stage room as in REIM' do
      Harness::Geography::STAGES.each do |stage|
        stage.rooms.each do |room_id|
          expect(Harness::Geography.in_reim?(room_id)).to be true
        end
      end
    end

    it 'recognizes misc-area rooms as in REIM' do
      expect(Harness::Geography.in_reim?(Harness::Geography::MISC_AREAS.first)).to be true
    end

    it 'does not recognize an unrelated room as in REIM' do
      expect(Harness::Geography.in_reim?(1)).to be false
    end

    it 'holds at a stage whose next_stage matches the reported clear-to' do
      village_room = Harness::Geography::VILLAGE.first
      stage = Harness::Geography.stage_holding(village_room, 'road')
      expect(stage.name).to eq('village')
    end

    it 'does not hold when clear-to has not reached the next stage' do
      village_room = Harness::Geography::VILLAGE.first
      expect(Harness::Geography.stage_holding(village_room, 'village')).to be_nil
    end

    it 'does not hold when clear-to is nil (progress unknown)' do
      village_room = Harness::Geography::VILLAGE.first
      expect(Harness::Geography.stage_holding(village_room, nil)).to be_nil
    end

    it 'only the village stage skips the pause before continuing' do
      village = Harness::Geography::STAGES.find { |s| s.name == 'village' }
      others = Harness::Geography::STAGES.reject { |s| s.name == 'village' }

      expect(village.pause_before_next).to be false
      expect(others.map(&:pause_before_next)).to all(be true)
    end
  end

  # -- Bosses ----------------------------------------------------------------

  describe 'Bosses' do
    it 'matches common ethereal-flavor NPC names' do
      expect('ethereal commoner').to match(Harness::Bosses::NPC_NAME_REGEX)
      expect('an ethereal commoner').to match(Harness::Bosses::NPC_NAME_REGEX)
    end

    it 'matches multi-word boss names' do
      expect('Patrol Leader').to match(Harness::Bosses::NPC_NAME_REGEX)
      expect('Royal Empress').to match(Harness::Bosses::NPC_NAME_REGEX)
    end

    it 'does not match unrelated text' do
      expect('a wild boar').not_to match(Harness::Bosses::NPC_NAME_REGEX)
    end

    it 'lists boss nouns used to classify GameObj#noun' do
      expect(Harness::Bosses::BOSS_NOUNS).to include('Captain', 'Emperor', 'Empress')
    end

    it 'lists common nouns used to classify GameObj#noun' do
      expect(Harness::Bosses::COMMON_NOUNS).to include('commoner', 'guard', 'bandit')
    end
  end

  # -- SeenIds -----------------------------------------------------------

  describe 'SeenIds' do
    it 'reports ids that have been recorded' do
      seen = Harness::SeenIds.new
      seen << 'abc'
      expect(seen.include?('abc')).to be true
    end

    it 'does not report unrecorded ids' do
      seen = Harness::SeenIds.new
      expect(seen.include?('abc')).to be false
    end

    it 'evicts the oldest id once past max_size' do
      seen = Harness::SeenIds.new(max_size: 2)
      seen << 'a'
      seen << 'b'
      seen << 'c'
      expect(seen.include?('a')).to be false
      expect(seen.include?('b')).to be true
      expect(seen.include?('c')).to be true
    end

    it 'returns self from << for chaining' do
      seen = Harness::SeenIds.new
      expect(seen << 'a').to be(seen)
    end
  end

  # -- Config --------------------------------------------------------------

  describe 'Config' do
    it 'fills in every default on first setup' do
      Harness::Config.setup!

      expect(Harness::Config.stance_dance?).to be true
      expect(Harness::Config.attack_type).to eq('')
      expect(Harness::Config.active_scripts).to eq([])
      expect(Harness::Config.clear_title?).to be false
      expect(Harness::Config.spam_control?).to be true
      expect(Harness::Config.lag_control?).to be false
      expect(Harness::Config.toggle_ambients?).to be false
    end

    it 'defaults announce_rares to true for a known announcer name' do
      Harness::Char.name = 'Tysong'
      Harness::Config.setup!
      expect(Harness::Config.announce_rares?).to be true
    end

    it 'defaults announce_rares to false for an unknown character' do
      Harness::Char.name = 'SomeoneElse'
      Harness::Config.setup!
      expect(Harness::Config.announce_rares?).to be false
    end

    it 'does not overwrite an already-configured value on a later setup! call' do
      Harness::Config.setup!
      Harness::Config.attack_type = 'mstrike'

      Harness::Config.setup!

      expect(Harness::Config.attack_type).to eq('mstrike')
    end

    it 'defaults script_args lookups to an empty string' do
      Harness::Config.setup!
      expect(Harness::Config.script_args_for('nonexistent')).to eq('')
    end
  end

  # -- Attack dispatch -------------------------------------------------------

  describe 'Attack.perform dispatch' do
    before { Harness::Config.setup! }

    def dispatch(attack_type)
      Harness::Config.attack_type = attack_type
      Harness::Attack.perform
    end

    it 'dispatches mstrike/physical to physical("mstrike")' do
      expect(Harness::Attack).to receive(:physical).with('mstrike')
      dispatch('mstrike')
    end

    it 'dispatches attack to physical("attack")' do
      expect(Harness::Attack).to receive(:physical).with('attack')
      dispatch('attack')
    end

    it 'dispatches fire/ranged to physical("fire")' do
      expect(Harness::Attack).to receive(:physical).with('fire')
      dispatch('fire')
    end

    it 'dispatches jab/punch/grapple/kick to physical(type)' do
      expect(Harness::Attack).to receive(:physical).with('kick')
      dispatch('kick')
    end

    it 'dispatches uac to physical("mstrike punch")' do
      expect(Harness::Attack).to receive(:physical).with('mstrike punch')
      dispatch('uac')
    end

    it 'dispatches sleep to cast_sleep' do
      expect(Harness::Attack).to receive(:cast_sleep)
      dispatch('sleep')
    end

    it 'dispatches scrub to spell_then_mstrike(435, "435")' do
      expect(Harness::Attack).to receive(:spell_then_mstrike).with(435, '435')
      dispatch('scrub')
    end

    it 'dispatches bardass to spell_then_mstrike(1030, "1030 open")' do
      expect(Harness::Attack).to receive(:spell_then_mstrike).with(1030, '1030 open')
      dispatch('bardass')
    end

    it 'dispatches dredd to spell_then_mstrike(1630, "1630 open")' do
      expect(Harness::Attack).to receive(:spell_then_mstrike).with(1630, '1630 open')
      dispatch('dredd')
    end

    it 'dispatches the bare "1030" attack type to cast_only(1030, "1030 open", pause_before: 2)' do
      expect(Harness::Attack).to receive(:cast_only).with(1030, '1030 open', pause_before: 2)
      dispatch('1030')
    end

    it 'dispatches 709 to cast_and_release(709, "stop 709")' do
      expect(Harness::Attack).to receive(:cast_and_release).with(709, 'stop 709')
      dispatch('709')
    end

    it 'dispatches bare 435/635 to cast_only(type, type, pause_before: 2)' do
      expect(Harness::Attack).to receive(:cast_only).with('435', '435', pause_before: 2)
      dispatch('435')
    end

    it 'dispatches a custom ".lic" attack type to run_custom_script' do
      expect(Harness::Attack).to receive(:run_custom_script).with('duskattack.lic')
      dispatch('duskattack.lic')
    end

    it 'dispatches an unrecognized spell number to cast_generic' do
      expect(Harness::Attack).to receive(:cast_generic).with('908')
      dispatch('908')
    end

    it 'returns true (a no-op) for attack type "none" without touching the game' do
      expect(dispatch('none')).to be true
      expect(LichStub::GameStub.calls).to eq([])
    end
  end

  # -- Attack handler bodies -------------------------------------------------

  describe 'Attack handler bodies' do
    before { Harness::Config.setup! }

    it 'physical stance-dances to offensive, sends the command, then back to defensive' do
      Harness::Attack.physical('mstrike')

      expect(LichStub::GameStub.calls).to eq([
                                               [:waitrt?],
                                               [:fput, 'stance offensive'],
                                               [:fput, 'mstrike'],
                                               [:pause, 1],
                                               [:waitrt?],
                                               [:fput, 'stance defensive']
                                             ])
    end

    it 'physical skips stance dancing when disabled' do
      Harness::Config.setup!
      Harness::UserVars.treim[:stance_dance] = false

      Harness::Attack.physical('mstrike')

      expect(LichStub::GameStub.calls).to eq([[:waitrt?], [:fput, 'mstrike']])
    end

    it 'physical does not re-issue "stance offensive" when already offensive' do
      LichStub::GameStub.stance = 'offensive'

      Harness::Attack.physical('mstrike')

      expect(LichStub::GameStub.calls.first(2)).to eq([[:waitrt?], [:fput, 'mstrike']])
    end

    it 'cast_only does nothing but return true when the spell is unaffordable' do
      Harness::Spell.affordable = false

      expect(Harness::Attack.cast_only(1030, '1030 open', pause_before: 2)).to be true
      expect(LichStub::GameStub.calls).to eq([])
    end

    it 'cast_only casts the spell when affordable' do
      Harness::Spell.affordable = true

      Harness::Attack.cast_only(1030, '1030 open', pause_before: 2)

      expect(LichStub::GameStub.calls).to eq([
                                               [:waitrt?],
                                               [:waitcastrt?],
                                               [:pause, 2],
                                               [:put, 'incant 1030 open']
                                             ])
    end

    it 'spell_then_mstrike falls back to a plain mstrike when unaffordable' do
      Harness::Spell.affordable = false

      Harness::Attack.spell_then_mstrike(1030, '1030 open')

      expect(LichStub::GameStub.calls).to eq([
                                               [:waitrt?],
                                               [:fput, 'stance offensive'],
                                               [:fput, 'mstrike'],
                                               [:pause, 1],
                                               [:waitrt?],
                                               [:fput, 'stance defensive']
                                             ])
    end

    it 'run_custom_script starts the script with ".lic" stripped, case-insensitively' do
      Harness::Attack.run_custom_script('DuskAttack.LIC')
      expect(Harness::Script.started).to eq([['DuskAttack', nil]])
    end

    it 'run_custom_script does not restart an already-running script' do
      Harness::Script.mark_running!('duskattack')
      Harness::Attack.run_custom_script('duskattack.lic')
      expect(Harness::Script.started).to eq([])
    end
  end

  # -- ClearProgress ---------------------------------------------------------

  describe 'ClearProgress.check' do
    it 'parses clear-to stage, scrip, and hours+minutes remaining' do
      Harness::Lich::Util.issue_command_result = [
        'You are currently flagged for entry for up to the road.',
        'Total Ethereal Scrip for this run: 500/1000',
        'You have 1 hour and 30 minutes remaining in the Settlement of Reim.'
      ]

      result = Harness::ClearProgress.check

      expect(result.clear_to).to eq('road')
      expect(result.scrip).to eq(500)
      expect(result.time_left).to eq('1H 30M')
    end

    it 'parses a bare minutes-remaining line when under an hour is left' do
      Harness::Lich::Util.issue_command_result = ['You have 45 minutes remaining.']

      result = Harness::ClearProgress.check

      expect(result.time_left).to eq('45M')
    end

    it 'returns nils for fields REIM INFO did not report' do
      Harness::Lich::Util.issue_command_result = []

      result = Harness::ClearProgress.check

      expect(result.clear_to).to be_nil
      expect(result.scrip).to be_nil
      expect(result.time_left).to be_nil
    end

    it 'waits for a given target id to no longer be alive before checking' do
      # check itself unconditionally does one `pause 0.5` after the wait, so
      # a live target (which makes wait_for_death's loop run at least once)
      # is distinguished from an already-dead one by an *extra* pause call,
      # not by whether pause was called at all.
      npc = FakeNpc.new('123', 'captain', 'The Captain', 'alive')
      Harness::GameObj.npcs = [npc]
      LichStub::GameStub.on_pause = -> { npc.status = 'dead' }

      Harness::ClearProgress.check(target_id: '123')

      expect(LichStub::GameStub.calls.count { |call| call == [:pause, 0.5] }).to eq(2)
    end

    it 'does not wait when the target is already dead' do
      Harness::GameObj.npcs = [FakeNpc.new('123', 'captain', 'The Captain', 'dead')]

      Harness::ClearProgress.check(target_id: '123')

      expect(LichStub::GameStub.calls.count { |call| call == [:pause, 0.5] }).to eq(1)
    end
  end

  # -- Party -----------------------------------------------------------------

  describe 'Party' do
    it "reports the character's own name as leader when leading" do
      Group.leader = :self
      Harness::Char.name = 'Tysong'
      expect(Harness::Party.leader_name).to eq('Tysong')
    end

    it "reports the leader's noun when someone else is leading" do
      Group.leader = FakeNpc.new('1', 'Durakar', nil, nil)
      expect(Harness::Party.leader_name).to eq('Durakar')
    end

    it 'returns nil for leader_name when the leader is unknown' do
      Group.leader = nil
      expect(Harness::Party.leader_name).to be_nil
    end

    it "includes the character's own name in member_names" do
      Harness::Char.name = 'Tysong'
      Group.leader = :self
      Group.members = [FakeNpc.new('1', 'Durakar', nil, nil)]

      expect(Harness::Party.member_names).to contain_exactly('Tysong', 'Durakar')
    end
  end

  # -- FamiliarWindow ----------------------------------------------------

  describe 'FamiliarWindow.wrap' do
    it 'uses pushStream tags on an XML-capable frontend' do
      Harness::Lich::Common::Frontend.xml_supported = true
      expect(Harness::FamiliarWindow.wrap('hi')).to include('pushStream').and include('popStream')
    end

    it 'uses the legacy GSe/GSf escape sequence otherwise' do
      Harness::Lich::Common::Frontend.xml_supported = false
      wrapped = Harness::FamiliarWindow.wrap('hi')
      expect(wrapped).to include("\034GSe\r\n").and include("\034GSf\r\n")
    end

    it 'includes the given message either way' do
      Harness::Lich::Common::Frontend.xml_supported = true
      expect(Harness::FamiliarWindow.wrap('Mob Count: 5')).to include('Mob Count: 5')
    end
  end
end
