# frozen_string_literal: true

require_relative '../../support/bigshot_quick_native_cmd_support'

RSpec.describe 'Quick eLoot owner-thread API integration' do
  let(:namespace) { BigshotQuickNativeCmdSpec }
  let(:owner) { namespace::Owner.new }
  let(:engine) { namespace::Engine.new(owner) }
  let(:api) { Module.new }
  let(:clock) { [100.0] }
  let(:identity) { { session: 'login', room_id: 100, room_epoch: 1, target_id: 'loot' } }
  let(:observed) { identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running) }
  let(:guard) { namespace::QuickGuard.new(snapshot: -> { observed }, identity: identity, max_sends: 5, max_seconds: 20, clock: -> { clock.first }) }
  let(:calls) { [] }
  let(:children) { [] }
  let(:child) do
    instance = Struct.new(:done, :success, :kills).new(false, true, [])
    instance.define_singleton_method(:join) { |_timeout| self if done }
    instance.define_singleton_method(:completed_successfully?) { success }
    instance.define_singleton_method(:kill_sync) { |timeout:| kills << timeout; self.done = true; self }
    instance
  end
  let(:on_wait) { -> {} }

  before do
    namespace::Script.current = owner
    stub_const('BigshotQuickNativeCmdSpec::ELoot', api)
    owner.singleton_class.attr_accessor :silent, :want_downstream, :want_downstream_xml
    owner.silent, owner.want_downstream, owner.want_downstream_xml = false, true, false
    allow(owner).to receive(:child_scripts) { children }
    allow(owner).to receive(:execution_sleep) do |duration|
      clock[0] += duration
      on_wait.call
      owner.check_execution_guard!
    end
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock.first }
    allow(namespace::Script).to receive(:start_child).with('eloot', '--load-room-api', quiet: true) do
      children << child
      child
    end
    requests = calls
    api.define_singleton_method(:restore_room_hands) { |**| { outcome: :complete } }
    api.define_singleton_method(:room_loot) do |**arguments|
      requests << arguments.merge(thread: Thread.current, guarded: arguments[:owner].execution_guard_active?)
      { outcome: :complete }.freeze
    end
  end

  after do
    namespace::Script.current = nil
    expect(owner.execution_guard_active?).to be(false)
    expect([owner.silent, owner.want_downstream, owner.want_downstream_xml]).to eq([false, true, false])
  end

  def publish_api(version = 1)
    api.const_set(:ROOM_LOOT_API_VERSION, version)
  end

  def execute(command = 'loot #123')
    engine.quick_loot_execute(command, guard: guard, owner: owner, prefix: '>')
  end

  it 'reuses an available eLoot API without starting any script or issuing a direct loot command' do
    publish_api
    expect(execute).to eq(outcome: :complete, sends: 0)
    expect(calls.first).to include(corpse_ids: ['123'], floor: false, owner: owner, script_name: 'eloot', thread: Thread.current, guarded: true)
    expect(calls.first[:corpse_ids]).to be_frozen
    expect(calls.first[:corpse_ids].first).to be_frozen
    expect(namespace::Script).not_to have_received(:start_child)
    expect(owner.wires).to be_empty
  end

  it 'requests floor collection without implicitly authorizing any corpse' do
    publish_api
    execute('loot room')
    expect(calls.first).to include(corpse_ids: [], floor: true)
  end

  context 'when definitions are not loaded yet' do
    let(:on_wait) do
      -> { publish_api; child.done = true }
    end

    it 'starts only the exact definitions-only child and waits for successful teardown before calling the API' do
      expect(execute).to eq(outcome: :complete, sends: 0)
      expect(namespace::Script).to have_received(:start_child).once
      expect(child.kills).to be_empty
      expect(calls.length).to eq(1)
      expect(owner.wires).to be_empty
    end

    it 'does not accept a capability published by a failed child' do
      child.success = false
      expect { execute }.to raise_error(ArgumentError, /room API version 1/)
      expect(calls).to be_empty
    end
  end

  it 'fails explicitly when the native start refuses instead of using a preexisting named script' do
    unrelated = Object.new
    children << unrelated
    allow(namespace::Script).to receive(:start_child).and_return(nil)
    expect { execute }.to raise_error(ArgumentError, /could not start/)
    expect(children).to eq([unrelated])
    expect(calls).to be_empty
  end

  it 'refuses native lifecycle capability absence before starting the loader' do
    allow(owner).to receive(:respond_to?).and_call_original
    allow(owner).to receive(:respond_to?).with(:child_scripts).and_return(false)
    expect { execute }.to raise_error(ArgumentError, /exact-child/)
    expect(namespace::Script).not_to have_received(:start_child)
  end

  it 'bounds the definition load and joins exact-child cleanup before returning failure' do
    expect { execute }.to raise_error(ArgumentError, /loader timed out/)
    expect(child.done).to be(true)
    expect(child.kills).to eq([5])
    expect(calls).to be_empty
    expect(owner.wires).to be_empty
  end

  { control: [:held, 'held'], room_epoch: [2, 'room_epoch_changed'], safe: [false, 'safety_unverified'] }.each do |key, (value, reason)|
    context "when #{key} changes during loading" do
      let(:on_wait) { -> { observed[key] = value } }

      it 'cancels without starting API work and tears down only its exact child' do
        expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /#{reason}/)
        expect(child.done).to be(true)
        expect(child.kills).to eq([5])
        expect(calls).to be_empty
        expect(owner.wires).to be_empty
      end
    end
  end

  it 'charges initialization and helper sends, and restores stream flags after native cancellation' do
    publish_api
    state = observed
    api.define_singleton_method(:room_loot) do |owner:, **|
      owner.silent, owner.want_downstream, owner.want_downstream_xml = true, false, true
      owner.emit('>inventory')
      state[:control] = :stopped
      owner.emit('>search #123')
    end
    expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /stopped/)
    expect(owner.wires).to eq(['>inventory'])
    expect(guard.sends).to eq(1)
  end

  it 'does not treat a swallowed native interruption as successful eLoot completion' do
    publish_api
    state = observed
    api.define_singleton_method(:room_loot) do |owner:, **|
      state[:control] = :held
      begin
        owner.emit('>search #123')
      rescue StandardError
        { outcome: :complete }.freeze
      end
    end
    expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /held/)
    expect(owner.wires).to be_empty
  end

  it 'restores native stream flags after an unexpected eLoot error without claiming completion' do
    publish_api
    api.define_singleton_method(:room_loot) do |owner:, **|
      owner.silent, owner.want_downstream, owner.want_downstream_xml = true, false, true
      raise 'fixture failure'
    end
    expect { execute }.to raise_error(RuntimeError, 'fixture failure')
  end

  it 'requires an explicit completion result, including for zero-send exclusions' do
    publish_api
    api.define_singleton_method(:room_loot) { |**| nil }
    expect { execute }.to raise_error(ArgumentError, /did not confirm completion/)
  end

  it 'shows recognized eLoot refusal text while propagating failure for machine status' do
    publish_api
    refusal = Class.new(StandardError)
    api.const_set(:RoomScopeError, refusal)
    api.define_singleton_method(:room_loot) { |**| raise refusal, 'All configured containers are full.' }
    expect(engine).to receive(:echo).with('Quick eLoot: All configured containers are full.')
    expect { execute }.to raise_error(refusal, /containers are full/)
  end
end
