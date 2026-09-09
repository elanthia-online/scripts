# frozen_string_literal: true

require_relative '../../spec_helper'
require 'ostruct'
require 'tmpdir'

RSpec.describe 'eLoot guarded room API' do
  let(:source_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(source_path) }
  let(:owner) do
    Object.new.tap do |value|
      value.define_singleton_method(:execution_guard_active?) { true }
      value.define_singleton_method(:check_execution_guard!) { true }
      value.define_singleton_method(:execution_sleep) { |_seconds| true }
      value.define_singleton_method(:name) { 'bigshot' }
    end
  end
  let(:script_class) do
    Class.new do
      class << self
        attr_accessor :current, :list
      end
    end
  end
  let(:harness) do
    namespace = Module.new
    namespace.const_set(:Script, script_class)
    namespace.const_set(:LICH_VERSION, '5.21.0')
    namespace.define_singleton_method(:before_dying) { |&block| (@cleanup ||= []) << block }
    namespace.define_singleton_method(:cleanup) { @cleanup.each(&:call); @cleanup.clear }
    loader = Struct.new(:name, :vars).new('eloot', ['--load-room-api'])
    loader.define_singleton_method(:inspect) { 'version: 1.2.3 required: Lich >= 5.19.0' }
    script_class.current = loader
    script_class.list = [loader]
    hide_const('Gtk') if defined?(Gtk)
    begin
      namespace.module_eval(source, source_path)
    rescue SystemExit
      namespace.cleanup
    end
    script_class.current = owner
    namespace
  end
  let(:api) { harness.const_get(:ELoot) }
  let(:calls) { [] }
  let(:corpse) { Struct.new(:id).new('123') }
  let(:data) do
    OpenStruct.new(version: '1.2.3', settings: { track_full_sacks: true, skin_enable: true, keep_closed: true },
                   right_hand: nil, left_hand: nil, pool_command: true)
  end

  def prepare_world
    harness.const_set(:Status, Object.new.tap { |value| value.define_singleton_method(:dead?) { false } })
    harness.const_set(:Spell, Object.new.tap { |value| value.define_singleton_method(:[]) { |_| Struct.new(:active?).new(false) } })
    harness.const_set(:Group, Object.new.tap { |value| value.define_singleton_method(:checked?) { true } })
    harness.const_set(:GameObj, OpenStruct.new(dead: [corpse, Struct.new(:id).new('999')], right_hand: :sword, left_hand: :shield))
    api.class_variable_set(:@@data, data)
    api.instance_variable_set(:@room_inventory_ready, true)
    api.define_singleton_method(:disk_usage) {}
    api.define_singleton_method(:reset_disk_full) { |**| }
    log = calls
    api.define_singleton_method(:use_coin_hand) { log << :coins }
    api::Loot.define_singleton_method(:skin) { |items| log << [:skin, items.map(&:id)] }
    api::Loot.define_singleton_method(:search) { |items| log << [:search, items.map(&:id)] }
    api::Loot.define_singleton_method(:room) { log << :floor }
    api::Inventory.define_singleton_method(:return_hands) { log << :hands }
    api::Inventory.define_singleton_method(:close_sell_containers) { log << :close }
  end

  def run_room(**overrides)
    api.room_loot(corpse_ids: ['123'].freeze, floor: false, owner: owner, **overrides)
  end

  it 'loads the entire production file without entering normal startup' do
    expect(api::ROOM_LOOT_API_VERSION).to eq(1)
    expect(api.data).to be_nil
    expect(api.instance_variable_get(:@room_api_lease)).to be_nil
    expect(api.instance_variable_get(:@room_api_versions)).to eq('eloot' => '1.2.3')
  end

  it 'passes only authorized corpses through normal skin/search and restores hands without a floor sweep' do
    prepare_world
    result = run_room
    expect(result).to eq(outcome: :complete)
    expect(result).to be_frozen
    expect(calls).to eq([[:skin, ['123']], [:search, ['123']], :coins, :hands, :close])
    expect([data.right_hand, data.left_hand]).to eq([:sword, :shield])
    expect(api.room_scope?).to be_falsey
  end

  it 'uses the same room pickup routine when floor cleanup is requested' do
    prepare_world
    run_room(floor: true)
    expect(calls).to include(:floor)
  end

  it 'restores the borrowed skinning tool after an interrupted room pass without resuming loot' do
    prepare_world
    sword = Struct.new(:id).new('10')
    knife = Struct.new(:id).new('11')
    empty = Struct.new(:id).new(nil)
    sheath = Struct.new(:id).new('12')
    harness::GameObj.right_hand = sword
    harness::GameObj.left_hand = empty
    harness.const_set(:Room, OpenStruct.new(current: OpenStruct.new(id: 100)))
    harness.const_set(:XMLData, OpenStruct.new(room_count: 1))
    harness.const_set(:ReadyList, OpenStruct.new(ready_list: { skin_weapon: knife, skin_sheath: sheath }))
    harness.const_set(:StowList, OpenStruct.new(stow_list: { default: sheath }))
    allow(api).to receive(:standing?).and_return(true)
    world = harness::GameObj
    api::Loot.define_singleton_method(:skin) do |_items|
      world.left_hand = knife
      raise 'command budget exhausted'
    end
    expect { run_room(recoverable: true) }.to raise_error('command budget exhausted')
    expect(api::Inventory).to receive(:store_item).with(sheath, knife, true) { harness::GameObj.left_hand = empty }
    expect(api.restore_room_hands(owner: owner)).to eq(outcome: :complete)
    expect(harness::GameObj.left_hand.id).to be_nil
    expect(calls).to eq([:hands])
    expect { api.restore_room_hands(owner: owner) }.to raise_error(api::RoomScopeError, /recovery/)
  end

  it 'refuses recovery after displacement or for a different owner before any inventory helper' do
    prepare_world
    harness.const_set(:Room, OpenStruct.new(current: OpenStruct.new(id: 101)))
    harness.const_set(:XMLData, OpenStruct.new(room_count: 2))
    api.instance_variable_set(:@room_recovery, { owner: owner, data: data, room: 100, epoch: 1 })
    expect { api.restore_room_hands(owner: owner) }.to raise_error(api::RoomScopeError, /context changed/)
    expect { api.restore_room_hands(owner: Object.new) }.to raise_error(api::RoomScopeError, /recovery/)
    expect(calls).to be_empty
  end

  %i[arrives observed missing revoked moved].each do |response|
    it "never duplicates an uncertain sheath command when the delayed response is #{response}" do
      prepare_world
      sword = Struct.new(:id).new('10')
      knife = Struct.new(:id, :name).new('11', 'test knife')
      empty = Struct.new(:id).new(nil)
      sheath = Struct.new(:id, :name, :contents).new('12', 'test sheath', [])
      world = harness::GameObj
      world.right_hand, world.left_hand = sword, empty
      harness.const_set(:Room, OpenStruct.new(current: OpenStruct.new(id: 100)))
      harness.const_set(:XMLData, OpenStruct.new(room_count: 1))
      harness.const_set(:ReadyList, OpenStruct.new(ready_list: { skin_weapon: knife, skin_sheath: sheath }))
      harness.const_set(:StowList, OpenStruct.new(stow_list: { default: sheath }))
      allow(api).to receive(:standing?).and_return(true)
      allow(api).to receive(:msg)
      wires = []
      allow(api).to receive(:get_command) do |command, _pattern|
        wires << command
        raise 'interrupted waiting for sheath response' if wires.length == 1

        world.left_hand = empty
        []
      end
      inventory = api::Inventory
      api::Loot.define_singleton_method(:skin) do |_items|
        world.left_hand = knife
        inventory.store_item(sheath, knife, true)
      end
      expect { run_room(recoverable: true) }.to raise_error('interrupted waiting for sheath response')
      world.left_hand = empty if response == :observed
      # The original XML hand update arrives during a guarded observation wait.
      sleeps = []
      room = harness::Room.current
      owner.define_singleton_method(:execution_sleep) do |seconds|
        sleeps << seconds
        world.left_hand = empty if response == :arrives
        room.id = 101 if response == :moved
      end
      owner.define_singleton_method(:check_execution_guard!) do
        raise 'revoked' if response == :revoked && !sleeps.empty?
        true
      end
      case response
      when :observed
        expect(api.restore_room_hands(owner: owner)).to eq(outcome: :complete)
        expect(sleeps).to be_empty
      when :arrives
        expect(api.restore_room_hands(owner: owner)).to eq(outcome: :complete)
        expect(sleeps.length).to eq(1)
      when :missing
        expect { api.restore_room_hands(owner: owner) }.to raise_error(api::RoomScopeError, /refusing duplicate/)
        expect(sleeps.sum).to be_within(0.001).of(2)
      when :revoked
        expect { api.restore_room_hands(owner: owner) }.to raise_error('revoked')
      when :moved
        expect { api.restore_room_hands(owner: owner) }.to raise_error(api::RoomScopeError, /context changed/)
      end
      expect(wires).to eq(['_drag #11 #12'])
    end
  end

  it 'does not stow an unrelated new item held during recovery' do
    prepare_world
    harness.const_set(:Room, OpenStruct.new(current: OpenStruct.new(id: 100)))
    harness.const_set(:XMLData, OpenStruct.new(room_count: 1))
    empty = Struct.new(:id).new(nil)
    sword = Struct.new(:id).new('10')
    harness::GameObj.right_hand = sword
    harness::GameObj.left_hand = Struct.new(:id).new('99')
    api.instance_variable_set(:@room_recovery, { owner: owner, data: data, room: 100, epoch: 1,
                                               scope: { owner: owner }, right: sword, left: empty, tools: [] })
    expect(api::Inventory).not_to receive(:store_item)
    expect { api.restore_room_hands(owner: owner) }.to raise_error(api::RoomScopeError, /Unexpected held item/)
    expect(calls).to be_empty
    expect(api.room_scope?).to be_falsey
  end

  it 'retains the real room filters, exclusion precedence, and native single-item pickup choice' do
    original = api::Loot.method(:room)
    prepare_world
    api::Loot.define_singleton_method(:room, original)
    ruby = OpenStruct.new(id: '20', name: 'ruby', noun: 'ruby', type: 'gem')
    topaz = OpenStruct.new(id: '21', name: 'topaz', noun: 'topaz', type: 'gem')
    harness::GameObj.loot = [ruby, topaz]
    harness.const_set(:Bounty, OpenStruct.new(task: OpenStruct.new(heirloom?: false)))
    data.settings.merge!(loot_types: ['gem'], loot_keep: ['ruby', 'topaz'], unlootable: [], crumbly: [])
    data.reject_loot_names = ['nothing']
    data.reject_loot_nouns = ['nothing']
    data.disk_nouns_regex = /disk/
    data.loot_exclude_regex = /topaz/
    data.loot_keep_regex = /nothing/
    data.allowed_special_types = []
    data.all_loot_categories = ['gem']
    allow(api).to receive(:msg)
    allow(api::Inventory).to receive(:open_loot_containers)
    allow(api::Inventory).to receive(:free_hand)
    expect(api::Inventory).to receive(:single_loot).with(ruby)
    expect(api::Inventory).not_to receive(:single_loot).with(topaz)
    expect(api::Loot).not_to receive(:loot_all)
    run_room(floor: true)
  end

  it 'initializes with the eLoot profile and explicit eLoot version, never Bigshot metadata' do
    prepare_world
    api.class_variable_set(:@@data, nil)
    profile = { loot_types: ['gem'] }
    expect(api).to receive(:waitrt?)
    expect(api).to receive(:load_profile).and_return(profile)
    expect(api).to receive(:load).with(profile) do
      expect(api.get_script_version).to eq('1.2.3')
      api.class_variable_set(:@@data, data)
    end
    expect(api).to receive(:set_inventory) { api.instance_variable_set(:@room_inventory_ready, true) }
    run_room
  end

  it 'loads and writes ordinary defaults when the first eLoot profile does not yet exist' do
    prepare_world
    api.class_variable_set(:@@data, nil)
    harness.const_set(:Char, OpenStruct.new(name: 'OfflineFixture'))
    harness.const_set(:XMLData, OpenStruct.new(game: 'GSIV'))
    lich = Module.new
    messaging = Module.new
    messaging.define_singleton_method(:msg) { |*_| }
    lich.const_set(:Messaging, messaging)
    harness.const_set(:Lich, lich)
    expect(messaging).to receive(:msg).with('info', /Loading defaults/)
    allow(api).to receive(:waitrt?)
    expect(api).to receive(:load).with(api.defaults_hash) { api.class_variable_set(:@@data, data) }
    expect(api).to receive(:set_inventory) { api.instance_variable_set(:@room_inventory_ready, true) }
    Dir.mktmpdir('eloot-room-profile-') do |directory|
      harness.const_set(:DATA_DIR, directory)
      run_room
      expect(File.read(File.join(directory, 'GSIV', 'OfflineFixture', 'eloot.yaml'))).to include('loot_types')
    end
  end

  it 'requires the current owner and active native guard before initialization' do
    expect { run_room(owner: Object.new) }.to raise_error(api::RoomScopeError, /current guarded/)
    allow(owner).to receive(:execution_guard_active?).and_return(false)
    expect { run_room }.to raise_error(api::RoomScopeError, /current guarded/)
    expect(api.data).to be_nil
  end

  it 'discards partially initialized data after an inventory failure and retries initialization' do
    prepare_world
    api.instance_variable_set(:@room_inventory_ready, false)
    allow(api).to receive(:waitrt?)
    allow(api).to receive(:load_profile).and_return({})
    allow(api).to receive(:load) { api.class_variable_set(:@@data, data) }
    expect(api).to receive(:set_inventory).ordered.and_raise(api::RoomScopeError, 'inventory unavailable')
    expect { run_room }.to raise_error(api::RoomScopeError, /inventory unavailable/)
    expect(api.data).to be_nil
    expect(api).to receive(:set_inventory).ordered do
      api.instance_variable_set(:@room_inventory_ready, true)
    end
    expect(run_room).to eq(outcome: :complete)
  end

  it 'preserves separate fresh corpse observations in ordinary skin and search calls' do
    prepare_world
    allow(api).to receive(:sleep)
    allow(api::Loot).to receive(:skin) { |_| harness::GameObj.dead = [] }
    expect(api::Loot).to receive(:search).with([])
    api.loot
  end

  it 'rejects malformed corpse IDs and nonboolean floor choices' do
    [[].freeze, ['0'].freeze, ['#123'].freeze, ['1;look'].freeze, [Object.new].freeze].each do |ids|
      expect { run_room(corpse_ids: ids) }.to raise_error(ArgumentError)
    end
    expect { run_room(floor: 'yes') }.to raise_error(ArgumentError)
  end

  it 'releases only its own lease and refuses overlapping room or standalone work' do
    prepare_world
    token = Object.new
    api.acquire_room_lease(token)
    api.release_room_lease(Object.new)
    expect { run_room }.to raise_error(api::RoomScopeError, /already running/)
    expect { harness.module_eval(source, source_path) }.to raise_error(api::RoomScopeError, /already running/)
    api.release_room_lease(token)
    expect(run_room).to eq(outcome: :complete)
  end

  it 'unwinds the scope on cancellation without issuing hand-restoration commands' do
    prepare_world
    allow(api::Loot).to receive(:search).and_raise(api::RoomScopeError, 'cancelled')
    expect { run_room }.to raise_error(api::RoomScopeError, 'cancelled')
    expect(calls).not_to include(:hands, :close)
    expect(api.instance_variable_get(:@room_api_lease)).to be_nil
    expect(api.room_scope?).to be_falsey
  end

  it 'makes all three module receivers sleep through the guarded owner only in scope' do
    prepare_world
    expect(owner).to receive(:execution_sleep).with(0.2)
    expect(owner).to receive(:execution_sleep).with(0.1).twice
    allow(api::Loot).to receive(:search) do
      api::Loot.sleep(0.1)
      api::Inventory.sleep(0.1)
    end
    run_room
    expect(api.sleep(0)).to eq(0)
  end

  it 'blocks sell, travel, banking, and box processing before their first side effect' do
    prepare_world
    allow(api::Loot).to receive(:search) do
      [-> { api.go2('gemshop') }, -> { api.sell }, -> { api::Sell.sell },
       -> { api.silver_deposit }, -> { api::Loot.box_loot(nil) }, -> { api::Sell.pool }].each do |operation|
        expect(&operation).to raise_error(api::RoomScopeError, /cannot/)
      end
    end
    run_room
  end

  it 'seeds the current disk without installing a persistent parser hook' do
    original = api.method(:disk_usage)
    prepare_world
    api.define_singleton_method(:disk_usage, original)
    data.settings[:use_disk] = true
    harness.const_set(:Disk, OpenStruct.new(mine: Struct.new(:id).new('44')))
    allow(harness::GameObj).to receive(:[]).with('44').and_return(:disk)
    run_room
    expect(data.disk).to eq(:disk)
  end

  it 'does not swallow sticky cancellation in inventory retries' do
    prepare_world
    harness.const_set(:StowList, OpenStruct.new(stow_list: { default: :bag }))
    data.sacks_full = {}
    item = OpenStruct.new(name: 'ruby', type: 'gem')
    allow(api).to receive(:msg)
    allow(api::Inventory).to receive(:single_drag_box).and_return(false)
    allow(api::Inventory).to receive(:stunned?).and_return(false)
    error = Class.new(StandardError)
    allow(api::Inventory).to receive(:store_item) do
      allow(owner).to receive(:check_execution_guard!).and_raise(error, 'cancelled')
      raise error, 'cancelled'
    end
    allow(api::Loot).to receive(:search) { api::Inventory.single_drag(item) }
    expect { run_room }.to raise_error(error, 'cancelled')
    expect(api.instance_variable_get(:@room_api_lease)).to be_nil
  end

  it 'does not start or use a file logger for a debug-file profile during room cleanup' do
    prepare_world
    data.settings[:debug_file] = true
    data.debug_logger = nil
    expect(api::DebugLogger).not_to receive(:new)
    allow(api::Loot).to receive(:search) { api.msg(type: 'debug', text: 'room pass') }
    expect(run_room).to eq(outcome: :complete)
    expect(data.settings[:debug_file]).to be(true)
  end

  it 'does not swallow sticky cancellation in command retries' do
    prepare_world
    util = Module.new
    lich = Module.new
    lich.const_set(:Util, util)
    harness.const_set(:Lich, lich)
    error = Class.new(StandardError)
    util.define_singleton_method(:issue_command) { |*_, **_| }
    allow(util).to receive(:issue_command) do
      allow(owner).to receive(:check_execution_guard!).and_raise(error, 'cancelled')
      raise error, 'cancelled'
    end
    allow(api::Loot).to receive(:search) { api.get_command('look', /look/) }
    expect { run_room }.to raise_error(error, 'cancelled')
  end

  it 'does not swallow sticky cancellation in coin-container retries' do
    original = api.method(:use_coin_hand)
    prepare_world
    api.define_singleton_method(:use_coin_hand, original)
    data.coin_hand = OpenStruct.new(id: '40')
    data.coin_bag = OpenStruct.new(id: '41')
    allow(api).to receive(:msg)
    allow(api).to receive(:silver_check).and_return(1)
    allow(api::Inventory).to receive(:free_hand)
    util = Module.new
    lich = Module.new
    lich.const_set(:Util, util)
    harness.const_set(:Lich, lich)
    error = Class.new(StandardError)
    util.define_singleton_method(:issue_command) { |*_, **_| }
    allow(util).to receive(:issue_command) do
      allow(owner).to receive(:check_execution_guard!).and_raise(error, 'cancelled')
      raise error, 'cancelled'
    end
    expect { run_room }.to raise_error(error, 'cancelled')
  end

  it 'turns full containers into an actionable error without pausing or selling ingots' do
    prepare_world
    bag = OpenStruct.new(name: 'bag')
    harness.const_set(:StowList, OpenStruct.new(stow_list: { default: bag }))
    data.sacks_full = {}
    item = OpenStruct.new(name: 'gold ingot', type: 'gem')
    allow(api).to receive(:msg)
    allow(api::Inventory).to receive(:single_drag_box).and_return(false)
    allow(api::Inventory).to receive(:stunned?).and_return(false)
    allow(api::Inventory).to receive(:store_item).and_return(false)
    expect(owner).not_to receive(:pause)
    expect(api::Sell).not_to receive(:handle_ingot)
    allow(api::Loot).to receive(:search) { api::Inventory.single_drag(item) }
    expect { run_room }.to raise_error(api::RoomScopeError, /full containers/)
  end

  it 'stows and restores occupied non-READY hands through the normal inventory methods' do
    original = api::Inventory.method(:return_hands)
    prepare_world
    api::Inventory.define_singleton_method(:return_hands, original)
    right = OpenStruct.new(id: '70', name: 'ruby')
    left = OpenStruct.new(id: '71', name: 'topaz')
    harness::GameObj.right_hand = right
    harness::GameObj.left_hand = left
    harness.const_set(:ReadyList, OpenStruct.new(ready_list: {}))
    data.original_readylist = []
    allow(api::Inventory).to receive(:checkright).and_return(true)
    allow(api::Inventory).to receive(:checkleft).and_return(true)
    expect(api::Inventory).not_to receive(:stow_ready_list)
    expect(api::Inventory).not_to receive(:return_ready_list)
    expect(api::Inventory).to receive(:single_drag).with(right)
    expect(api::Inventory).to receive(:single_drag).with(left)
    expect(api::Inventory).to receive(:drag).with(right, 'right')
    expect(api::Inventory).to receive(:drag).with(left, 'left')
    allow(api::Loot).to receive(:search) do
      api::Inventory.free_hands(both: true)
      harness::GameObj.right_hand = OpenStruct.new(id: nil)
      harness::GameObj.left_hand = OpenStruct.new(id: nil)
    end
    run_room
  end
end
