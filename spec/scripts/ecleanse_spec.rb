# frozen_string_literal: true

require_relative '../spec_helper'
require 'securerandom'
require 'stringio'

# Spec for ecleanse.lic's disarm tracking (UserVars.last_disarm) and the
# RECOVER ITEM search loop. ecleanse.lic can't be required standalone, so the
# real method bodies are extracted and evaluated under Harness::Ecleanse::Action
# and System, against stubs that stand in for the game. The expected game text
# comes from character logs of the 2026-11-05 lost-handaxe incident.
module EcleanseSpec
  SOURCE_PATH = find_lic_source('ecleanse.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH)

  ACTION_METHODS = %w[
    record_disarm queue_recover disarm_list disarm_tracked? disarm_add disarm_remove
    disarm_remove_room disarm_remove_found spied_item same_item? disarm_report disarm_recover recovered? recover
  ].freeze

  ACTION_SRC = ACTION_METHODS.map { |name| extract_lic_method(SOURCE, name, source_path: SOURCE_PATH) }.join("\n")
  SET_HOOKS_SRC = extract_lic_method(SOURCE, 'set_hooks', source_path: SOURCE_PATH)
  DISARM_CONSTANTS_SRC = extract_from_source(SOURCE, /DISARM_MAX = \d+\n.*?DISARM_LOCK \|\|= Mutex\.new/m, label: 'DISARM constants', source_path: SOURCE_PATH)

  Hand = Struct.new(:id, :noun, :name)
  EMPTY_HAND = Hand.new(nil, nil, 'Empty')
  FakeRoom = Struct.new(:id, :title)
  FakeSpell = Struct.new(:num) do
    def known? = false
    def active? = false
  end

  module Harness
    UserVars = LichStub::UserVars

    class << self
      attr_accessor :held, :downstream_priority, :recover_regex, :current_room, :right_hand, :left_hand, :rooms, :replies, :commands, :notes, :downstream, :upstream, :dying, :dead
    end

    def self.reset!
      self.current_room = FakeRoom.new(34183, ['[Kresh Warrens, Hewn Tunnel]'])
      self.right_hand = EMPTY_HAND
      self.left_hand = EMPTY_HAND
      self.rooms = { 34183 => current_room }
      self.replies = []
      self.commands = []
      self.notes = []
      self.dying = []
      self.dead = false
      self.held = []
      $fill_hands_actions = []
    end

    # Lich::Stash's stack: each empty_hands pushes one frame of gets, and each
    # fill_hands pops the newest frame and runs it. A get with no free hand does nothing.
    def self.stash_held
      frame = held.map { |item| proc { held << item if held.size < 2 } }
      held.clear
      $fill_hands_actions.push(frame)
    end

    module Room
      def self.current = Harness.current_room
      def self.[](id) = Harness.rooms.fetch(id) { raise "looked up room #{id.inspect}" unless id.is_a?(Integer) }
    end

    module GameObj
      def self.right_hand = Harness.right_hand
      def self.left_hand = Harness.left_hand
    end

    module Spell
      def self.[](num) = FakeSpell.new(num)
    end

    module Feat
      def self.weapon_bonding = 0
    end

    module ReadyList
      def self.valid? = true
    end

    module Script
      def self.current = Struct.new(:name).new('ecleanse')
    end

    module DownstreamHook
      def self.add(_name, hook, priority: 0)
        Harness.downstream_priority = priority
        Harness.downstream = hook
      end

      def self.remove(_name) = nil
    end

    module UpstreamHook
      def self.add(_name, hook) = Harness.upstream = hook
      def self.remove(_name) = nil
    end

    module Ecleanse
      # Only what v2.3.6's Data had: it survives a script restart, so an upgrade
      # mid-session runs this code against a Data built by the older version.
      Data = Struct.new(:settings, :recover_stuff, :recover_stuff_seq, :event_stack, :creature, :hive_trap_room)

      class << self
        attr_accessor :data
      end

      module Util
        def self.msg(_type, text) = Harness.notes << text
        def self.wait_rt = nil

        def self.get_command(command, regex)
          Harness.commands << command
          Harness.recover_regex = regex
          reply = Harness.replies.shift || []
          reply.each { |line| Harness.held << line[/(\w+) and recover it!/, 1] if line.include?('and recover it!') }
          reply
        end

        def self.able_to_cast = false
      end

      module System
        def self.scripts_pause = Harness.commands << :pause
        def self.scripts_resume = Harness.commands << :resume
      end

      module Action
        def self.go2(_room) = Harness.commands << :go2
        def self.settle_room = nil
        def self.change_stance(_stance) = nil

        def self.empty_hands
          Harness.commands << :empty_hands
          Harness.stash_held
        end

        def self.fill_hands
          Harness.commands << :fill_hands
          $fill_hands_actions.pop&.each(&:call)
        end

        def self.kneeling? = true
        def self.standing? = true
        def self.dead? = Harness.dead
        def self.exit = raise('recover must not exit the daemon')
        def self.fput(command) = Harness.commands << command
      end
    end

    module_eval <<~RUBY, __FILE__, __LINE__ + 1
      module Ecleanse
        module Action
          #{DISARM_CONSTANTS_SRC}
          #{ACTION_SRC}
        end

        module System
          def self.before_dying(&block) = Harness.dying << block
          #{SET_HOOKS_SRC}
        end
      end
    RUBY
  end
end

RSpec.describe 'ecleanse run more than once in a session' do
  # Each extracted piece is the real source, evaluated twice into one module the
  # way a second ;ecleanse re-evaluates the file.
  def run_twice(source, edited_source = source)
    target = Module.new
    warnings = StringIO.new
    original = [$stderr, $VERBOSE]
    $stderr = warnings
    $VERBOSE = true
    target.module_eval(source)
    target.module_eval(edited_source)
    [target, warnings.string]
  ensure
    $stderr, $VERBOSE = original
  end

  let(:source) { EcleanseSpec::SOURCE }
  let(:action_guard) { source[/^    %i\[DISARM_MAX\]\.each.*$/] }
  let(:action_constants) { "#{action_guard}\n#{EcleanseSpec::DISARM_CONSTANTS_SRC}" }
  let(:capped_collection) { extract_lic_module(source, 'CappedCollection', kind: 'class') }

  it 'does not warn about CappedCollection constants' do
    _target, warnings = run_twice(capped_collection)

    expect(warnings).not_to include('already initialized')
  end

  it 'does not warn about Action constants' do
    _target, warnings = run_twice(action_constants)

    expect(warnings).not_to include('already initialized')
  end

  it 'picks up a changed limit rather than keeping the first run\'s value' do
    target, = run_twice(action_constants, action_constants.sub('DISARM_MAX = 30', 'DISARM_MAX = 50'))

    expect(target.const_get(:DISARM_MAX)).to eq(50)
  end

  it 'keeps the same lock' do
    target = Module.new
    target.module_eval(action_constants)
    lock = target.const_get(:DISARM_LOCK)
    target.module_eval(action_constants)

    expect(target.const_get(:DISARM_LOCK)).to equal(lock)
  end
end

RSpec.describe 'ecleanse disarm tracking' do
  let(:harness) { EcleanseSpec::Harness }
  let(:action) { harness::Ecleanse::Action }
  let(:user_vars) { LichStub::UserVars }

  def spy(name) = ['You intently search the area, sifting through the rocks and stones.', "You spy a #{name} and recover it!", 'Roundtime: 5 sec.']

  def items = action.disarm_list.map { |entry| entry[:item] }

  before do
    user_vars.reset!
    harness.reset!
    harness::Ecleanse.data = harness::Ecleanse::Data.new({ recover_disarmed: true }, {}, 0, [])
    $lich_char_regex = Regexp.union(',', ';')
  end

  describe 'the saved list' do
    it 'saves what was lost, where and when' do
      action.disarm_add('handaxe')

      entry = user_vars.last_disarm.first
      expect(entry).to include(item: 'handaxe', room: 34183, title: '[Kresh Warrens, Hewn Tunnel]')
      expect(entry[:at]).to be_within(5).of(Time.now.to_i)
    end

    it 'reads the room number older versions stored as an empty list, and replaces it' do
      user_vars.last_disarm = 34183
      expect(action.disarm_list).to eq([])

      action.disarm_add('handaxe')
      expect(items).to eq(['handaxe'])
    end

    it 'cycles out the oldest once 30 are saved' do
      32.times { |n| action.disarm_add("weapon#{n}") }

      expect(items.size).to eq(30)
      expect(items.first).to eq('weapon2')
      expect(items.last).to eq('weapon31')
    end

    it 'gives two disarms in the same second their own entries' do
      first = action.disarm_add('broadsword')
      second = action.disarm_add('handaxe')

      action.disarm_remove(first)
      expect(action.disarm_list.map { |entry| entry[:id] }).to eq([second])
    end

    it 'is not corrupted by a disarm landing while another is being removed' do
      ids = Array.new(30) { |n| action.disarm_add("weapon#{n}") }
      adder = Thread.new { 15.times { |n| action.disarm_add("new#{n}") } }
      ids.first(15).each { |id| action.disarm_remove(id) }
      adder.join

      expect(items).to include(*Array.new(15) { |n| "new#{n}" })
    end
  end

  describe '.spied_item / .same_item?' do
    it 'reads the plain game line' do
      expect(action.spied_item(spy('xazkruvrixis broadsword'))).to eq('a xazkruvrixis broadsword')
    end

    it 'prefers the noun on the XML line, including nouns with spaces' do
      line = 'You spy a <a exist="123" noun="Hammer of Kai">Hammer of Kai</a> and recover it!'
      expect(action.spied_item([line])).to eq('Hammer of Kai')
    end

    it 'returns nil when nothing was recovered' do
      expect(action.spied_item(['You find nothing recoverable.'])).to be_nil
    end

    it 'tells the handaxe from the broadsword' do
      expect(action.same_item?('a xazkruvrixis handaxe', 'handaxe')).to be(true)
      expect(action.same_item?('a xazkruvrixis broadsword', 'handaxe')).to be(false)
      expect(action.same_item?('a xazkruvrixis handaxes', 'handaxe')).to be(false)
    end
  end

  describe '.recover' do
    it 'keeps searching when it finds an earlier disarm, and clears both (21:38 incident)' do
      action.disarm_add('broadsword')
      key = action.record_disarm('handaxe')
      harness.replies = [spy('xazkruvrixis broadsword'), spy('xazkruvrixis handaxe')]

      action.recover(key)

      expect(harness.commands.count('recover item')).to eq(2)
      expect(user_vars.last_disarm).to eq([])
    end

    it 'skips a queued recovery whose weapon already turned up during another search' do
      first = action.record_disarm('broadsword')
      second = action.record_disarm('handaxe')
      harness.replies = [spy('xazkruvrixis handaxe'), spy('xazkruvrixis broadsword')]

      action.recover(first)
      commands_after_first = harness.commands.dup
      action.recover(second)

      expect(user_vars.last_disarm).to eq([])
      expect(harness.commands).to eq(commands_after_first)
    end

    it 'leaves a found weapon with no saved entry alone and keeps looking' do
      key = action.record_disarm('handaxe')
      harness.replies = [spy('old falchion'), spy('xazkruvrixis handaxe')]

      action.recover(key)

      expect(harness.commands.count('recover item')).to eq(2)
      expect(user_vars.last_disarm).to eq([])
    end

    it 'only clears a found weapon from the room it was found in' do
      elsewhere = harness.current_room
      harness.current_room = EcleanseSpec::FakeRoom.new(999, ['[Elsewhere]'])
      action.disarm_add('broadsword')
      harness.current_room = elsewhere
      key = action.record_disarm('handaxe')
      harness.replies = [spy('xazkruvrixis broadsword'), spy('xazkruvrixis handaxe')]

      action.recover(key)

      expect(items).to eq(['broadsword'])
    end

    it 'stops at once when too injured to search, keeps the entry and restores the hands (18:57 incident)' do
      key = action.record_disarm('broadsword')
      harness.replies = [["You're not in any condition to be searching around!"]]

      action.recover(key)

      expect("You're not in any condition to be searching around!").to match(harness.recover_regex)
      expect(harness.commands.count('recover item')).to eq(1)
      expect(harness.commands.count(:fill_hands)).to eq(1)
      expect(items).to eq(['broadsword'])
      expect(harness.notes.last).to include('disarmrecover')
    end

    it 'keeps the entry when ten searches come up empty' do
      key = action.record_disarm('handaxe')
      harness.replies = Array.new(10) { ['You continue to intently search the area, sifting through the rocks and stones.'] }

      action.recover(key)

      expect(harness.commands.count('recover item')).to eq(10)
      expect(items).to eq(['handaxe'])
    end

    it 'forgets every disarm saved for a room the game says has nothing to recover' do
      elsewhere = harness.current_room
      harness.current_room = EcleanseSpec::FakeRoom.new(999, ['[Elsewhere]'])
      action.disarm_add('falchion')
      harness.current_room = elsewhere
      action.disarm_add('broadsword')
      key = action.record_disarm('handaxe')
      harness.replies = [['You find nothing recoverable.']]

      action.recover(key)

      expect(harness.commands.count('recover item')).to eq(1)
      expect(items).to eq(['falchion'])
    end

    it 'only forgets the searched-for disarm when the room is unmapped' do
      harness.current_room = EcleanseSpec::FakeRoom.new(nil, [])
      action.disarm_add('broadsword')
      key = action.record_disarm('handaxe')
      harness.replies = [['You find nothing recoverable.']]

      action.recover(key)

      expect(items).to eq(['broadsword'])
    end

    it 'keeps trying when "nothing recoverable" comes from outside the disarm room' do
      key = action.record_disarm('handaxe')
      harness.current_room = EcleanseSpec::FakeRoom.new(999, ['[Elsewhere]'])
      harness.replies = Array.new(10) { ['You find nothing recoverable.'] }

      action.recover(key)

      expect(harness.commands.count('recover item')).to eq(10)
      expect(items).to eq(['handaxe'])
    end

    context 'when the search finds an earlier disarm and has to stash it to keep going' do
      let(:replies) do
        [
          spy('xazkruvrixis broadsword'),
          ['In order to recover something, you need a free hand.'],
          spy('xazkruvrixis handaxe')
        ]
      end

      it 'gives what was being held the free hand, leaving the found weapon stowed' do
        harness.held = ['shield']
        key = action.record_disarm('handaxe')
        harness.replies = replies

        action.recover(key)

        expect(harness.held).to contain_exactly('handaxe', 'shield')
        expect($fill_hands_actions).to eq([])
      end

      it 'ends up holding both weapons when nothing else was being held (21:38 incident)' do
        key = action.record_disarm('handaxe')
        harness.replies = replies

        action.recover(key)

        expect(harness.held).to contain_exactly('handaxe', 'broadsword')
        expect($fill_hands_actions).to eq([])
      end
    end
  end

  describe '.record_disarm' do
    it 'tracks nothing when recovery is turned off' do
      harness::Ecleanse.data.settings[:recover_disarmed] = false

      expect(action.record_disarm('handaxe')).to be_nil
      expect(user_vars.last_disarm).to be_nil
    end
  end

  describe '.disarm_report' do
    it 'lists what is still lost, newest first' do
      action.disarm_add('broadsword')
      action.disarm_add('handaxe')

      action.disarm_report

      expect(harness.notes.map { |note| note[/\w+/] }).to eq(%w[handaxe broadsword])
      expect(harness.notes.first).to include('Room 34183 [Kresh Warrens, Hewn Tunnel] - 0 min ago')
    end

    it 'says so when nothing is saved' do
      action.disarm_report

      expect(harness.notes).to eq([' No unrecovered disarms.'])
    end
  end

  describe '.disarm_recover' do
    it 'goes back for the most recent disarm' do
      action.disarm_add('broadsword')
      action.disarm_add('handaxe')
      harness.replies = [spy('xazkruvrixis handaxe')]

      action.disarm_recover

      expect(harness.commands).to include(:go2, 'recover item')
      expect(items).to eq(['broadsword'])
    end

    it 'says so when nothing is saved' do
      action.disarm_recover

      expect(harness.commands).to eq([])
      expect(harness.notes.last).to include('No unrecovered disarms')
    end

    it 'does not go anywhere while dead' do
      action.disarm_add('handaxe')
      harness.dead = true

      action.disarm_recover

      expect(harness.commands).to eq([])
      expect(items).to eq(['handaxe'])
    end

    it 'never looks up a nil room' do
      harness.current_room = EcleanseSpec::FakeRoom.new(nil, nil)
      action.disarm_add('handaxe')

      action.disarm_recover

      expect(harness.commands).to eq([])
      expect(harness.notes.last).to include("Can't find the room")
    end
  end

  describe 'the game and client hooks' do
    let(:data) { harness::Ecleanse.data }

    before { harness::Ecleanse::System.set_hooks }

    it 'watches for disarms ahead of other scripts\' hooks' do
      expect(harness.downstream_priority).to eq(100)
    end

    it 'saves a ground disarm as soon as the game reports it' do
      line = %(You swing your <a exist="1" noun="handaxe">xazkruvrixis handaxe</a> at a chitinous kiramon myrmidon.  The weapon rebounds off of the hardened chitin of the myrmidon's exoskeleton and is wrenched from your hand.  It slides along the ground and disappears into the shadows!)

      harness.downstream.call(line)

      expect(items).to eq(['handaxe'])
      expect(data.event_stack.map { |event| event[:event] }).to eq([:recover])
    end

    it 'does not save webbed or telekinetic disarms, which RECOVER ITEM cannot fetch later' do
      harness.downstream.call(%(The webbing entangles your <a exist="1" noun="handaxe">handaxe</a>, rendering it useless))
      harness.downstream.call(%(Your <a exist="1" noun="handaxe">handaxe</a> tears free from your hands and floats))

      expect(action.disarm_list).to eq([])
      expect(data.event_stack.map { |event| event[:event] }).to eq(%i[recover_weapon_webbing telekinetic_recover])
    end

    [';ecleanse disarmrecover', '<c>;ecleanse disarmrecover', ',ecleanse disarmrecover', ';force ecleanse disarmrecover'].each do |typed|
      it "takes #{typed.inspect} for the running script" do
        expect(harness.upstream.call(typed)).to be_nil
        expect(data.event_stack).to eq([:disarm_recover])
      end
    end

    it 'queues one retry however many times it is typed' do
      2.times { harness.upstream.call(';ecleanse disarmrecover') }

      expect(data.event_stack).to eq([:disarm_recover])
    end

    [';ecleanse last disarm', ';force ecleanse last disarm'].each do |typed|
      it "takes #{typed.inspect} for the running script" do
        expect(harness.upstream.call(typed)).to be_nil
        expect(data.event_stack).to eq([:disarm_report])
      end
    end

    [';ecleanse list', ';bigshot disarmrecover', ';bigshot last disarm', 'recover item'].each do |typed|
      it "passes #{typed.inspect} through" do
        expect(harness.upstream.call(typed)).to eq(typed)
        expect(data.event_stack).to eq([])
      end
    end
  end
end
