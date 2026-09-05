# Spec for pilepull.lic's reward tracking: name canonicalization/tiering and
# the handle_loot control flow that decides what gets recorded.
#
# We do NOT load the .lic file: Rewards opens a SQLite database at
# module-load time and needs the whole Lich runtime. Instead the real method
# bodies are extracted from scripts/pilepull.lic and evaluated against
# stubs, so these specs exercise production code and fail if that code
# changes shape. Extraction uses the shared helpers in spec/spec_helper.rb.
#
# This file exists because of two real bugs that shipped and were only
# caught by manually diffing search count against item count in --debug
# output:
#   1. `return` inside the `30.times { }` wait block in handle_loot unwinds
#      the whole method, not just the block -- a Rewards.record_item call
#      placed after that loop was silently skipped every time hands cleared
#      quickly (i.e. almost always).
#   2. Re-reading an item's name via GameObj[id] after redeeming/trashing it
#      returns nil for a consumed/destroyed object (always true for a
#      redeemed booklet or trashed orb), and record_item's nil guard then
#      dropped the reward entirely rather than just mis-tiering it.
# Every example under "handle_loot" is here to make a regression of either
# bug fail loudly instead of silently undercounting again.

require_relative '../spec_helper'

module PilePullRewardsSpec
  SOURCE_PATH = find_lic_source('pilepull.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")

  def self.extract(pattern, label)
    extract_from_source(SOURCE, pattern, label: label, source_path: SOURCE_PATH)
  end

  TIER_PATTERNS_SRC = extract(
    /^    TIER_PATTERNS = \[.*?\]\.freeze unless const_defined\?\(:TIER_PATTERNS, false\)$/m,
    'TIER_PATTERNS'
  )
  FALLBACK_ITEM_FIXUPS_SRC = extract(
    /^    FALLBACK_ITEM_FIXUPS = \[.*?\]\.freeze unless const_defined\?\(:FALLBACK_ITEM_FIXUPS, false\)$/m,
    'FALLBACK_ITEM_FIXUPS'
  )
  CANONICAL_NAME_FOR_SRC = extract_lic_method(SOURCE, 'canonical_name_for', source_path: SOURCE_PATH)
  TIER_FOR_SRC = extract_lic_method(SOURCE, 'tier_for', source_path: SOURCE_PATH)
  EVENT_HALF_SRC = extract_lic_method(SOURCE, 'event_half', source_path: SOURCE_PATH)
  EVENT_KEY_FOR_SRC = extract_lic_method(SOURCE, 'event_key_for', source_path: SOURCE_PATH)
  LABEL_FOR_KEY_SRC = extract_lic_method(SOURCE, 'label_for_key', source_path: SOURCE_PATH)
  RECORD_ITEM_SRC = extract_lic_method(SOURCE, 'record_item', source_path: SOURCE_PATH)
  HANDLE_LOOT_SRC = extract_lic_method(SOURCE, 'handle_loot', source_path: SOURCE_PATH)
  SEARCH_PILE_SRC = extract_lic_method(SOURCE, 'search_pile', source_path: SOURCE_PATH)

  # Real tier/canonicalization/event-bucketing logic under test, evaluated so
  # bare XMLData and PilePull references resolve to the stand-ins nested here.
  class RewardsLogic
    module XMLData
      class << self
        attr_accessor :game
      end
    end

    module PilePull
      class << self
        def dbg(_msg); end
      end
    end

    module_eval(TIER_PATTERNS_SRC, SOURCE_PATH)
    module_eval(FALLBACK_ITEM_FIXUPS_SRC, SOURCE_PATH)
    module_eval(CANONICAL_NAME_FOR_SRC, SOURCE_PATH)
    module_eval(TIER_FOR_SRC, SOURCE_PATH)
    module_eval(EVENT_HALF_SRC, SOURCE_PATH)
    module_eval(EVENT_KEY_FOR_SRC, SOURCE_PATH)
    module_eval(LABEL_FOR_KEY_SRC, SOURCE_PATH)

    class << self
      attr_reader :record_calls

      def reset!
        @record_calls = []
      end

      # Stands in for Rewards.record (the real Sequel insert) so record_item
      # can be tested without a database.
      def record(type:, item_name: nil, tier: nil, quantity: 1)
        (@record_calls ||= []) << { type: type, item_name: item_name, tier: tier, quantity: quantity }
      end
    end

    module_eval(RECORD_ITEM_SRC, SOURCE_PATH)
  end

  # Real handle_loot control flow under test, with GameObj/Rewards stubbed
  # locally (never at top level -- see spec_helper.rb's note on GameObj) and
  # sleep/exit/echo/fput overridden as harness singleton methods so they take
  # precedence over Kernel's for calls made with an implicit receiver, the
  # same trick spec_helper documents for its own generic stubs.
  class HandleLoot
    FakeHand = Struct.new(:id, :name)

    module GameObj
      class << self
        attr_accessor :right_hand, :left_hand

        def clear_hands!
          self.right_hand = FakeHand.new(nil, nil)
          self.left_hand = FakeHand.new(nil, nil)
        end
      end
    end

    module Rewards
      class << self
        attr_reader :recorded

        def reset!
          @recorded = []
        end

        def record_item(item_name, quantity: 1)
          @recorded << [item_name, quantity]
        end
      end
    end

    class << self
      attr_accessor :keep_spoon, :keep_nexus, :stuck, :last_pull_name
      attr_reader :fput_calls, :sleep_count, :exited, :echoed

      def reset!
        @keep_spoon = false
        @keep_nexus = false
        @stuck = false
        @last_pull_name = nil
        @fput_calls = []
        @sleep_count = 0
        @exited = false
        @echoed = []
        GameObj.clear_hands!
        Rewards.reset!
      end

      def dbg(_msg); end

      def echo(msg)
        @echoed << msg
      end

      # Simulates the action succeeding immediately (hands clear) unless the
      # test has set `stuck`, matching a real "containers full" run where
      # the item never leaves your hands no matter what you do with it.
      def fput(command)
        @fput_calls << command
        GameObj.clear_hands! unless stuck
        command
      end

      # Overrides Kernel#sleep for the 30.times wait loop's bare sleep(0.1)
      # so a "stuck" example does not actually block for 3 real seconds.
      def sleep(*)
        @sleep_count += 1
      end

      # Overrides Kernel#exit the same way, turning the real script's
      # process-ending exit into something a test can observe and unwind
      # from safely.
      def exit(*)
        @exited = true
        throw :handle_loot_exit
      end
    end

    module_eval(HANDLE_LOOT_SRC, SOURCE_PATH)

    def self.run
      catch(:handle_loot_exit) { handle_loot }
    end
  end

  # Real search_pile control flow under test. The point of this harness is
  # the @last_pull_name it captures for handle_loot to consume: the search
  # response text spells out a pulled item's full name, unlike
  # GameObj.right_hand.name in handle_loot, which truncates a swirling and a
  # potent yellow-green potion to the exact same ambiguous fragment.
  class SearchPile
    Pile = Struct.new(:id)

    module Rewards
      class << self
        attr_reader :calls

        def reset!
          @calls = []
        end

        def record_search_cost(amount)
          (@calls ||= []) << amount
        end
      end
    end

    class << self
      attr_accessor :max_inventory, :last_pull_name
      attr_reader :dothistimeout_calls, :echoed, :exited, :sleep_calls

      def reset!
        @prize_pile = Pile.new('50993552')
        @max_inventory = false
        @last_pull_name = nil
        @dothistimeout_calls = []
        @next_results = []
        @echoed = []
        @exited = false
        @sleep_calls = []
      end

      # Queues a value dothistimeout should return on its next call --
      # search_pile's `next`-driven retries can call it more than once in a
      # single example (e.g. a "search again" retry before it succeeds).
      def queue_result(value)
        (@next_results ||= []) << value
      end

      def dothistimeout(command, _timeout, _pattern)
        @dothistimeout_calls << command
        @next_results.shift
      end

      def dbg(_msg); end

      def echo(msg)
        @echoed << msg
      end

      def exit(*)
        @exited = true
        throw :search_pile_exit
      end

      def sleep(seconds)
        @sleep_calls << seconds
      end

      def waitrt?
        false
      end
    end

    module_eval(SEARCH_PILE_SRC, SOURCE_PATH)

    def self.run
      catch(:search_pile_exit) { search_pile }
    end
  end
end

RSpec.describe 'pilepull.lic reward tracking' do
  def rewards_logic
    PilePullRewardsSpec::RewardsLogic
  end

  def handle_loot
    PilePullRewardsSpec::HandleLoot
  end

  def fake_hand
    PilePullRewardsSpec::HandleLoot::FakeHand
  end

  def search_pile
    PilePullRewardsSpec::SearchPile
  end

  describe 'Rewards.canonical_name_for' do
    {
      'runner contract'         => 'locker runner contract',
      'Guild voucher pack'      => "Adventurer's Guild voucher pack",
      'Guilds voucher pack'     => 'Elanthian Guilds voucher pack',
      'nexus orb'               => 'swirling nexus orb',
      'blue orb'                => 'shimmering blue orb',
      'stamped voucher booklet' => 'creased stamped voucher booklet'
    }.each do |truncated, canonical|
      it "recovers #{truncated.inspect} (a fragment actually seen from GameObj) to #{canonical.inspect}" do
        expect(rewards_logic.canonical_name_for(truncated)).to eq(canonical)
      end
    end

    it 'leaves an already-full name alone' do
      expect(rewards_logic.canonical_name_for('locker runner contract')).to eq('locker runner contract')
    end

    it 'does not guess at a genuinely ambiguous fragment' do
      # Could be the uncommon swirling or the rare potent variant -- guessing
      # would silently corrupt data rather than fix it.
      expect(rewards_logic.canonical_name_for('yellow-green potion')).to eq('yellow-green potion')
    end

    it 'passes nil through without raising' do
      expect(rewards_logic.canonical_name_for(nil)).to be_nil
    end
  end

  describe 'Rewards.tier_for' do
    after { rewards_logic::XMLData.game = nil }

    {
      'larger locker contract'          => 'common',
      'locker runner contract'          => 'common',
      'swirling yellow-green potion'    => 'uncommon',
      "Adventurer's Guild voucher pack" => 'uncommon',
      'Elanthian Guilds voucher pack'   => 'uncommon',
      'glowing orb'                     => 'rare',
      'swirling nexus orb'              => 'rare',
      'potent yellow-green potion'      => 'rare',
      'shimmering blue orb'             => 'epic',
      'small locker expansion contract' => 'epic',
      'shimmering violet orb'           => 'legendary'
    }.each do |name, tier|
      it "tiers #{name.inspect} as #{tier}" do
        rewards_logic::XMLData.game = 'GS'
        expect(rewards_logic.tier_for(name)).to eq(tier)
      end
    end

    it 'tiers the booklet as epic outside Shattered' do
      rewards_logic::XMLData.game = 'GS'
      expect(rewards_logic.tier_for('creased stamped voucher booklet')).to eq('epic')
    end

    it 'tiers the booklet one tier down (rare) specifically on Shattered (GSF)' do
      rewards_logic::XMLData.game = 'GSF'
      expect(rewards_logic.tier_for('creased stamped voucher booklet')).to eq('rare')
    end

    it 'does not apply the GSF booklet override to an unrelated item' do
      rewards_logic::XMLData.game = 'GSF'
      expect(rewards_logic.tier_for('glowing orb')).to eq('rare')
    end

    it 'returns unknown for an unrecognized item rather than raising' do
      rewards_logic::XMLData.game = 'GS'
      expect(rewards_logic.tier_for('a mysterious trinket')).to eq('unknown')
    end

    it 'returns unknown for nil' do
      expect(rewards_logic.tier_for(nil)).to eq('unknown')
    end
  end

  describe 'Rewards.record_item' do
    before { rewards_logic.reset! }

    it 'canonicalizes and tiers a truncated name before recording' do
      rewards_logic::XMLData.game = 'GS'
      rewards_logic.record_item('runner contract')
      expect(rewards_logic.record_calls).to eq(
        [{ type: 'item', item_name: 'locker runner contract', tier: 'common', quantity: 1 }]
      )
    end

    # This is the exact failure mode of bug #2: a nil name (what
    # GameObj[id] returned for a redeemed booklet/trashed orb) must not
    # silently vanish -- it must be visibly refused, not recorded as
    # anything.
    it 'refuses to record a nil item name' do
      rewards_logic.record_item(nil)
      expect(rewards_logic.record_calls).to be_empty
    end

    it 'refuses to record a blank item name' do
      rewards_logic.record_item('')
      expect(rewards_logic.record_calls).to be_empty
    end

    after { rewards_logic::XMLData.game = nil }
  end

  describe 'Rewards event bucketing' do
    it 'buckets January through June as the Feb/Mar event' do
      expect(rewards_logic.event_key_for(2026, 1)).to eq(20_261)
      expect(rewards_logic.event_key_for(2026, 6)).to eq(20_261)
    end

    it 'buckets July through December as the Aug/Sep event' do
      expect(rewards_logic.event_key_for(2026, 7)).to eq(20_262)
      expect(rewards_logic.event_key_for(2026, 12)).to eq(20_262)
    end

    it 'labels an event key with the year and the correct half' do
      expect(rewards_logic.label_for_key(20_261)).to eq('2026 Duskruin (Feb/Mar)')
      expect(rewards_logic.label_for_key(20_262)).to eq('2026 Duskruin (Aug/Sep)')
    end

    it 'labels a nil key without raising' do
      expect(rewards_logic.label_for_key(nil)).to eq('unknown event')
    end
  end

  describe 'handle_loot' do
    before { handle_loot.reset! }

    # Regression test for bug #1: `return` inside the 30.times wait block
    # unwinds handle_loot entirely, not just the block. If Rewards.record_item
    # were ever moved back below that wait loop, this example would start
    # failing because hands clearing immediately (the overwhelmingly common
    # case) would skip recording every time.
    it 'records the item even when hands clear on the very first check' do
      handle_loot::GameObj.right_hand = fake_hand.new('111', 'a larger locker contract')
      handle_loot.run
      expect(handle_loot::Rewards.recorded).to eq([['a larger locker contract', 1]])
    end

    # Regression test for bug #2: recording must not depend on re-reading the
    # item's name after the action, since that lookup returns nil once the
    # object has been destroyed (a redeemed booklet, a trashed orb).
    it 'records a booklet using the name captured before redeeming it' do
      handle_loot::GameObj.right_hand = fake_hand.new('222', 'a creased stamped voucher booklet')
      handle_loot.run
      expect(handle_loot::Rewards.recorded).to eq([['a creased stamped voucher booklet', 1]])
      expect(handle_loot.fput_calls).to include('redeem booklet')
    end

    it 'records a nexus orb using the name captured before trashing it' do
      handle_loot::GameObj.right_hand = fake_hand.new('333', 'a swirling nexus orb')
      handle_loot.run
      expect(handle_loot::Rewards.recorded).to eq([['a swirling nexus orb', 1]])
      expect(handle_loot.fput_calls).to include('trash my orb')
    end

    it 'stows a nexus orb instead of trashing it when keep_nexus is set' do
      handle_loot.keep_nexus = true
      handle_loot::GameObj.right_hand = fake_hand.new('333', 'a swirling nexus orb')
      handle_loot.run
      expect(handle_loot.fput_calls).to include('stow all')
      expect(handle_loot.fput_calls).not_to include('trash my orb')
    end

    it 'trashes an unwanted steel spoon' do
      handle_loot::GameObj.right_hand = fake_hand.new('444', 'a steel spoon')
      handle_loot.run
      expect(handle_loot.fput_calls).to include('trash my spoon')
    end

    it 'stows a steel spoon instead of trashing it when keep_spoon is set' do
      handle_loot.keep_spoon = true
      handle_loot::GameObj.right_hand = fake_hand.new('444', 'a steel spoon')
      handle_loot.run
      expect(handle_loot.fput_calls).to include('stow all')
      expect(handle_loot.fput_calls).not_to include('trash my spoon')
    end

    it 'stows anything else that has no special handling' do
      handle_loot::GameObj.right_hand = fake_hand.new('555', 'a locker runner contract')
      handle_loot.run
      expect(handle_loot.fput_calls).to eq(['stow all'])
    end

    it 'does not record the same item id twice' do
      handle_loot.stuck = true
      handle_loot::GameObj.right_hand = fake_hand.new('666', 'a larger locker contract')
      handle_loot.run
      expect(handle_loot::Rewards.recorded).to eq([['a larger locker contract', 1]])
    end

    it 'falls back to the "couldn\'t handle" exit path when hands never clear' do
      handle_loot.stuck = true
      handle_loot::GameObj.right_hand = fake_hand.new('777', 'a larger locker contract')
      handle_loot.run
      expect(handle_loot.exited).to be true
      expect(handle_loot.echoed.join).to match(/Couldn't handle item received/)
    end

    it 'never reaches the exit path when hands do clear' do
      handle_loot::GameObj.right_hand = fake_hand.new('888', 'a larger locker contract')
      handle_loot.run
      expect(handle_loot.exited).to be false
      expect(handle_loot.echoed).to be_empty
    end

    # GameObj.right_hand.name truncates a swirling and a potent yellow-green
    # potion to the exact same "yellow-green potion" fragment -- genuinely
    # ambiguous, and previously always landed as "unknown" tier. search_pile
    # parses the full name out of the search response text and stashes it in
    # @last_pull_name for handle_loot to prefer.
    it 'prefers the full name captured by search_pile over an ambiguous truncated hand name' do
      handle_loot.last_pull_name = 'swirling yellow-green potion'
      handle_loot::GameObj.right_hand = fake_hand.new('999', 'yellow-green potion')
      handle_loot.run
      expect(handle_loot::Rewards.recorded).to eq([['swirling yellow-green potion', 1]])
    end

    it 'clears last_pull_name after using it, so a later item cannot inherit a stale name' do
      handle_loot.last_pull_name = 'swirling yellow-green potion'
      handle_loot::GameObj.right_hand = fake_hand.new('999', 'yellow-green potion')
      handle_loot.run
      expect(handle_loot.last_pull_name).to be_nil
    end

    it 'falls back to the hand name when search_pile did not capture anything' do
      handle_loot::GameObj.right_hand = fake_hand.new('999', 'a locker runner contract')
      handle_loot.run
      expect(handle_loot::Rewards.recorded).to eq([['a locker runner contract', 1]])
    end
  end

  describe 'search_pile' do
    before do
      search_pile.reset!
      search_pile::Rewards.reset!
    end

    it 'records 1,000,000 silver spent on a successful search' do
      search_pile.queue_result(
        'You hand over 1,000,000 silver and search through a pile of mania prizes.  ' \
        'You pull a locker runner contract from within!'
      )
      expect(search_pile.run).to be true
      expect(search_pile::Rewards.calls).to eq([1_000_000])
    end

    {
      'swirling yellow-green potion'    => 'a',
      'potent yellow-green potion'      => 'a',
      'glowing orb'                     => 'a',
      'creased stamped voucher booklet' => 'a',
      "Adventurer's Guild voucher pack" => 'an',
      'Elanthian Guilds voucher pack'   => 'an'
    }.each do |pulled, article|
      it "captures the full pulled item name for #{pulled.inspect} from the search text" do
        search_pile.queue_result(
          "You hand over 1,000,000 silver and search through a pile of mania prizes.  " \
          "You pull #{article} #{pulled} from within!"
        )
        search_pile.run
        expect(search_pile.last_pull_name).to eq(pulled)
      end
    end

    # This is the actual bug this whole harness exists to catch: a truncated
    # GameObj.right_hand.name cannot tell these two apart, but the search
    # result text always spells out which one it was.
    it 'tells a swirling yellow-green potion apart from a potent one' do
      search_pile.queue_result(
        'You hand over 1,000,000 silver and search through a pile of mania prizes.  ' \
        'You pull a swirling yellow-green potion from within!'
      )
      search_pile.run
      swirling_name = search_pile.last_pull_name

      search_pile.reset!
      search_pile::Rewards.reset!
      search_pile.queue_result(
        'You hand over 1,000,000 silver and search through a pile of mania prizes.  ' \
        'You pull a potent yellow-green potion from within!'
      )
      search_pile.run
      potent_name = search_pile.last_pull_name

      expect([swirling_name, potent_name]).to eq(['swirling yellow-green potion', 'potent yellow-green potion'])
    end

    it 'clears any previous last_pull_name rather than raising when the text does not match the expected shape' do
      search_pile.last_pull_name = 'stale'
      search_pile.queue_result('You hand over 1,000,000 silver and search through a pile of mania prizes.')
      search_pile.run
      expect(search_pile.last_pull_name).to be_nil
    end

    it 'retries once told to search again within 30 seconds' do
      search_pile.queue_result(
        'In order to search through a pile of mania prizes, it will cost 1,000,000 silver.  ' \
        'If you want to give it a try SEARCH again within 30 seconds!'
      )
      search_pile.queue_result(
        'You hand over 1,000,000 silver and search through a pile of mania prizes.  ' \
        'You pull a larger locker contract from within!'
      )
      expect(search_pile.run).to be true
      expect(search_pile.dothistimeout_calls.length).to eq(2)
    end

    it 'returns false when out of silver, recording nothing' do
      search_pile.queue_result('You do not have enough silver to SEARCH through a pile of mania prizes.  You need 1,000,000 silver.')
      expect(search_pile.run).to be false
      expect(search_pile::Rewards.calls).to be_empty
    end

    it 'returns false the first time too many items blocks the search, to trigger cleanup once' do
      search_pile.queue_result('You have too many items to search.')
      expect(search_pile.run).to be false
      expect(search_pile.max_inventory).to be true
    end

    it 'gives up instead of looping forever if still too many items on the very next search' do
      search_pile.max_inventory = true
      search_pile.queue_result('You have too many items to search.')
      search_pile.run
      expect(search_pile.exited).to be true
    end
  end
end
