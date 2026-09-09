# frozen_string_literal: true

require_relative '../support/bigshot_quick_run_harness'

module BigshotQuickAreaSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  body = source[/^  class BSAreaRooms\n.*?^  end$/m]
  raise 'could not extract BSAreaRooms' unless body

  module_eval(body, __FILE__, __LINE__)

  MapRoom = Struct.new(:wayto, :timeto, :location)
  StringProc = Class.new do
    def initialize(&callback) = (@callback = callback)
    def call = @callback.call
  end

  # Offline command sink implementing the native owner's guard contract. Map
  # callbacks use it so an attempted command can never reach a game connection.
  class Owner < BigshotQuickRunSpec::Owner
    class Denied < StandardError; end
    attr_reader :writes

    def initialize
      super
      @writes = []
    end

    def with_execution_guard(policy)
      @policy = policy
      @denied = false
      check_execution_guard!
      result = yield
      check_execution_guard!
      result
    ensure
      @policy = nil
    end

    def check_execution_guard!(command: nil)
      @denied = true unless @policy.call(command).equal?(true)
      raise Denied if @denied
    end

    def emit(command)
      check_execution_guard!(command: command)
      @writes << command
    end
  end

  if ENV['LICH_EXECUTION_GUARD_ROOT']
    require File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script_execution_guard')
    native = File.read(File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script.rb')).gsub("\r\n", "\n")
    Owner.const_set(:ScriptExecutionGuard, Lich::Common::ScriptExecutionGuard)
    Owner.const_set(:EXECUTION_GUARD_MUTEX_INITIALIZER, Mutex.new)
    Owner.send(:remove_const, :Denied)
    Owner.const_set(:Denied, Lich::Common::ScriptExecutionGuard::Interrupted)
    %w[with_execution_guard execution_guard_active? check_execution_guard! execution_guard_mutex].each do |name|
      method_body = native[/^      def #{Regexp.escape(name)}(?:\([^\n]*\))?\n.*?^      end$/m]
      raise "could not extract native Script##{name}" unless method_body

      Owner.class_eval(method_body)
    end
  end
end

RSpec.describe 'Bigshot Quick profile area' do
  let(:owner) { BigshotQuickAreaSpec::Owner.new }
  let(:profile) { { 'hunting_room_id' => '100', 'hunting_boundaries' => '103' } }
  let(:rooms) do
    { 100 => map_room(101 => 0.5), 101 => map_room(100 => 0.5, 102 => 1, 103 => 1),
      102 => map_room(101 => 0.5), 103 => map_room(104 => 1), 104 => map_room }
  end
  let(:map) { double('native UID resolver') }
  let(:area) { BigshotQuickAreaSpec::BSAreaRooms.for_quick(profile, owner: owner) }

  def map_room(edges = {})
    BigshotQuickAreaSpec::MapRoom.new(edges.transform_keys(&:to_s).transform_values { 'north' },
                                      edges.transform_keys(&:to_s), 'Test hunting ground')
  end

  before do
    stub_const('BigshotQuickAreaSpec::Room', double('mapped rooms'))
    allow(BigshotQuickAreaSpec::Room).to receive(:[]) { |id| rooms[id] }
    stub_const('BigshotQuickAreaSpec::Map', map)
  end

  it 'builds the native connected room set without entering or expanding boundaries' do
    expect(area.area_rooms).to eq(Set[100, 101, 102])
    expect(area.boundaries).to eq(Set[103])
    expect(area.quick_status(102)).to eq(kind: :profile, start_room_id: 100, boundary_room_ids: [103],
                                         room_count: 3, room_id: 102, in_bounds: true)
    expect(area.quick_status(103)[:in_bounds]).to be(false)
    expect(area.quick_status(nil)[:in_bounds]).to be(false)
    expect(area.quick_status(999)[:in_bounds]).to be(false)
    expect(owner.writes).to be_empty
  end

  it 'offers only ordinary mapped in-area directions for bounded seek' do
    rooms[100] = map_room(101 => 1, 102 => 1, 103 => 1)
    rooms[100].wayto.merge!('101' => 'north', '102' => 'go gate', '103' => 'east')
    expect(area.quick_steps(100)).to eq([[101, 'north']])
    rooms[100].wayto['101'] = BigshotQuickAreaSpec::StringProc.new { raise 'must not run' }
    expect(area.quick_steps(100)).to be_empty
    expect(area.quick_steps(103)).to be_empty
  end

  it 'pins an immutable area and returns frozen membership observations' do
    expect(area).to be_frozen
    expect(area.area_rooms).to be_frozen
    expect(area.boundaries).to be_frozen
    status = area.quick_status(100)
    expect(status).to be_frozen
    expect(status[:boundary_room_ids]).to be_frozen
    rooms[102].wayto['104'] = 'north'
    rooms[102].timeto['104'] = 1
    expect(area.quick_status(104)[:in_bounds]).to be(false)
    expect { area.area_rooms << 104 }.to raise_error(FrozenError)
  end

  it 'uses the first native UID match for both the start and boundaries' do
    profile.merge!('hunting_room_id' => 'u123', 'hunting_boundaries' => 'u-456')
    expect(map).to receive(:ids_from_uid).with(123).and_return([100, 104])
    expect(map).to receive(:ids_from_uid).with(-456).and_return([103, 102])
    expect(area.start_room).to eq(100)
    expect(area.area_rooms).to eq(Set[100, 101, 102])
  end

  it 'rejects an unmapped first UID match instead of choosing a later result' do
    profile['hunting_room_id'] = 'u123'
    expect(map).to receive(:ids_from_uid).with(123).and_return([999, 100])
    expect { area }.to raise_error(ArgumentError, /unmapped room/)
  end

  it 'rejects a UID with no native matches' do
    profile['hunting_room_id'] = 'u123'
    expect(map).to receive(:ids_from_uid).with(123).and_return([])
    expect { area }.to raise_error(ArgumentError, /unmapped room/)
  end

  it 'admits numeric and numeric StringProc travel times but skips unavailable exits' do
    rooms[100] = map_room(101 => 0.5, 102 => BigshotQuickAreaSpec::StringProc.new { 1 },
                          104 => BigshotQuickAreaSpec::StringProc.new { nil }, 105 => '1')
    rooms[101] = map_room
    rooms[105] = map_room
    rooms[100].wayto['102'] = BigshotQuickAreaSpec::StringProc.new { raise 'wayto must not execute' }
    expect(area.area_rooms).to eq(Set[100, 101, 102])
    expect(owner.writes).to be_empty
  end

  it 'rejects a map predicate that tries to send a command' do
    rooms[100].timeto['101'] = BigshotQuickAreaSpec::StringProc.new { owner.emit('north'); 1 }
    expect { area }.to raise_error(BigshotQuickAreaSpec::Owner::Denied)
    expect(owner.writes).to be_empty
  end

  it 'retains command denial even when a map predicate rescues the interruption' do
    rooms[100].timeto['101'] = BigshotQuickAreaSpec::StringProc.new do
      owner.emit('north') rescue BigshotQuickAreaSpec::Owner::Denied
      1
    end
    expect { area }.to raise_error(BigshotQuickAreaSpec::Owner::Denied)
    expect(owner.writes).to be_empty
  end

  [nil, '', '0', '-1', '100garbage', '999'].each do |start|
    it "rejects invalid or unmapped start #{start.inspect}" do
      profile['hunting_room_id'] = start
      expect { area }.to raise_error(ArgumentError, /unmapped room/)
    end
  end

  [nil, '', 'invalid', '999', '100', '103,,104'].each do |boundaries|
    it "rejects missing, invalid, unmapped or overlapping boundaries #{boundaries.inspect}" do
      profile['hunting_boundaries'] = boundaries
      expect { area }.to raise_error(ArgumentError)
    end
  end

  it 'rejects an exit into a room absent from the native map' do
    rooms.delete(102)
    expect { area }.to raise_error(ArgumentError, /unmapped exit/)
  end

  [199, 200, 201].each do |count|
    it "#{count < 200 ? 'accepts' : 'rejects'} a connected set of #{count} rooms at the native limit" do
      rooms.clear
      (1..count).each { |id| rooms[id] = map_room(id < count ? { id + 1 => 1 } : {}) }
      rooms[1000] = map_room
      profile.merge!('hunting_room_id' => '1', 'hunting_boundaries' => '1000')
      if count < 200
        expect(area.area_rooms.size).to eq(count)
      else
        expect { area }.to raise_error(ArgumentError, /200 rooms/)
      end
    end
  end

  context 'during the native Quick controller lifecycle' do
    let(:settings) { { 'mode' => 'watch', 'max_actions' => 10, 'max_seconds' => 30 } }
    let(:target) { { id: '123', name: 'giant rat', noun: 'rat', hostile: true } }
    let(:snapshot) do
      { session: 'login', room_id: 100, room_epoch: 1, targets: [target], members: ['Friend'],
        safe: true, owner: true, connected: true }
    end
    let(:engine) { BigshotQuickRunSpec::Engine.new }
    let(:retreat) { nil }
    let(:policy) do
      BigshotQuickRunSpec::EncounterPolicy.new(settings, targets: { 'giant rat' => 'a' },
                                              routines: { 'a' => ['unarmed jab'] }, fallback: ['unarmed jab'])
    end
    let(:run) do
      BigshotQuickRunSpec::QuickRun.new(engine: engine, policy: policy, owner: owner, area: area,
                                        snapshot: -> { snapshot }, resolve_target: ->(_) { target },
                                        validate: ->(command) { command == 'unarmed jab' }, prefix: '>', retreat: retreat,
                                        trial: settings['mode'] == 'trial' ? { target_id: '123', actions: ['unarmed jab'] } : nil,
                                        clock: -> { 100.0 })
    end

    def move_to(room)
      snapshot[:room_id] = room
      snapshot[:room_epoch] += 1
    end

    it 'reports initial and updated membership through immutable cached status' do
      expect(run.status[:area]).to include(room_id: 100, in_bounds: true, room_count: 3)
      expect(run.status[:area]).to be_frozen
      run.tick
      move_to(101)
      expect(run.tick).to include(state: :running, actions: 2, area: include(room_id: 101, in_bounds: true))
    end

    [103, 104, 999, nil].each do |destination|
      it "stops before another action after entering #{destination.inspect}" do
        expect(run.tick[:actions]).to eq(1)
        move_to(destination)
        expect(run.tick).to include(state: :stopped, reason: 'profile_area_exit', actions: 1,
                                    area: include(room_id: destination, in_bounds: false))
        run.tick
        expect(engine.sends.size).to eq(1)
      end
    end

    it 'refuses combat when the initial room is outside the profile area' do
      move_to(104)
      expect(run.tick).to include(state: :stopped, reason: 'profile_area_exit', actions: 0)
      expect(engine.sends).to be_empty
    end

    %w[clear trial].each do |mode|
      it "pins #{mode} before the first tick when a profile area is supplied" do
        settings['mode'] = mode
        instance = run
        move_to(101)
        expect(instance.tick).to include(state: :stopped, reason: 'room_changed', actions: 0)
        expect(engine.sends).to be_empty
      end

      it "keeps #{mode} pinned to its initial room even inside the area" do
        settings['mode'] = mode
        instance = run
        instance.request('hold')
        instance.tick
        move_to(101)
        expect(instance.tick).to include(state: :stopped, reason: 'room_changed', actions: 0)
        expect(engine.sends).to be_empty
      end
    end

    it 'requires fresh assist evidence after following into another permitted room' do
      settings.merge!('mode' => 'assist', 'trigger' => 'leader', 'leader' => 'Friend', 'targeting' => 'assist-only')
      expect(run.observe_engagement(member: 'Friend', target_id: '123', room_id: 100, room_epoch: 1, at: 100.0)).to be(true)
      expect(run.tick[:actions]).to eq(1)
      move_to(101)
      expect(run.tick).to include(state: :running, actions: 1)
      expect(run.observe_engagement(member: 'Friend', target_id: '123', room_id: 100, room_epoch: 1, at: 100.0)).to be(false)
      expect(run.observe_engagement(member: 'Friend', target_id: '123', room_id: 101, room_epoch: 2, at: 100.0)).to be(true)
      expect(run.tick[:actions]).to eq(2)
    end

    it 'discards both granted and queued manual permissions across in-area movement' do
      settings['unknown'] = 'manual'
      target[:name] = 'unfamiliar creature'
      run.tick
      expect(run.request_engagement('123')[:accepted]).to be(true)
      expect(run.tick[:actions]).to eq(1)
      expect(run.request_engagement('123')[:accepted]).to be(true)
      move_to(101)
      expect(run.tick).to include(state: :running, actions: 1, control_error: 'engagement_stale_or_ineligible')
      expect(run.tick[:actions]).to eq(1)
      expect(run.request_engagement('123')[:accepted]).to be(true)
      expect(run.tick[:actions]).to eq(2)
    end

    it 'interrupts a multi-send native routine at the boundary before its next send' do
      engine.routine = lambda do |guard|
        guard.transmit('support') { engine.sends << 'support' }
        move_to(103)
        guard.transmit('attack #123') { engine.sends << 'attack #123' }
      end
      expect(run.tick).to include(state: :stopped, reason: 'profile_area_exit', actions: 1,
                                  area: include(room_id: 103, in_bounds: false))
      expect(engine.sends).to eq(['support'])
    end

    it 'interrupts an in-area crossing and lets watch choose anew on the next tick' do
      engine.routine = lambda do |guard|
        guard.transmit('support') { engine.sends << 'support' }
        move_to(101)
        guard.transmit('stale attack') { engine.sends << 'stale attack' }
      end
      expect(run.tick).to include(state: :running, actions: 1)
      expect(engine.sends).to eq(['support'])
      engine.routine = ->(guard) { guard.transmit('fresh attack') { engine.sends << 'fresh attack' } }
      expect(run.tick).to include(state: :running, actions: 2)
      expect(engine.sends).to eq(['support', 'fresh attack'])
    end

    context 'with an explicitly admitted retreat' do
      let(:retreat) do
        lambda do |&checkpoint|
          expect(checkpoint.call).to include(room_id: 100, escape_cancelled: nil)
          move_to(104)
          # Reuse the combat snapshot callback here: retreat authority, rather
          # than callback identity, permits the configured escape destination.
          expect(checkpoint.call).to include(room_id: 104, safe: true, escape_cancelled: nil)
          { outcome: :retreated, sends: 1, reason: 'retreated' }
        end
      end

      it 'allows retreat to leave the profile area and reports final membership' do
        run.tick
        expect(run.request('retreat')[:accepted]).to be(true)
        expect(run.tick).to include(state: :stopped, reason: 'retreated', actions: 1, escape_sends: 1,
                                    area: include(room_id: 104, in_bounds: false))
        expect(engine.sends.size).to eq(1)
      end
    end

    context 'without a configured area' do
      let(:area) { nil }

      it 'preserves the existing unscoped watch lifecycle and status shape' do
        run.tick
        move_to(104)
        expect(run.tick).to include(state: :running, actions: 2)
        expect(run.status).not_to have_key(:area)
      end
    end
  end
end
