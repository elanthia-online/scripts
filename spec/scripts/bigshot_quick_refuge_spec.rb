# frozen_string_literal: true

require_relative '../support/bigshot_quick_walk_harness'
require_relative '../support/bigshot_quick_run_harness'

RSpec.describe 'Supervised Quick refuge outings' do
  let(:world) do
    { session: 'login', room_id: 100, room_epoch: 1, stable: true,
      alive: true, owner: true, connected: true, destination_safe: true,
      safe: true, targets: [], members: [], members_verified: true }
  end
  let(:hands) { { hands: ['123', nil], standing: true } }
  let(:owner) { BigshotQuickRunSpec::Owner.new }
  let(:engine) { BigshotQuickRunSpec::Engine.new }
  let(:clock) { [100.0] }
  let(:authority) { [true] }
  let(:moves) { [] }
  let(:loot) { nil }
  let(:area) do
    double(quick_status: { kind: 'profile', in_bounds: true }, valid?: true)
  end
  let(:outbound) do
    lambda do |&checkpoint|
      observed = checkpoint.call
      next { outcome: :unconfirmed, reason: observed[:escape_cancelled] || 'owner_lost' } unless observed[:owner] && !observed[:escape_cancelled]
      moves << :outbound
      world[:room_id] = 200
      world[:room_epoch] += 1
      { outcome: :retreated, sends: 1 }
    end
  end
  let(:homeward) do
    lambda do |&checkpoint|
      observed = checkpoint.call
      next { outcome: :unconfirmed, reason: 'owner_lost' } unless observed[:owner]
      moves << :return
      world[:room_id] = 100
      world[:room_epoch] += 1
      { outcome: :retreated, sends: 1 }
    end
  end
  let(:run) do
    settings = { 'mode' => 'clear', 'max_actions' => 10, 'max_seconds' => 30 }
    policy = BigshotQuickRunSpec::EncounterPolicy.new(settings, targets: {}, routines: {})
    BigshotQuickRunSpec::QuickRun.new(engine: engine, policy: policy, owner: owner,
                                      snapshot: -> { world.dup }, retreat_snapshot: -> { world.dup },
                                      resolve_target: ->(_) {}, validate: ->(_) { true }, prefix: '>', area: area,
                                      clock: -> { clock.first }, loot: loot, execution_window: { work_deadline: 120.0, cleanup_deadline: 130.0 },
                                      refuge: { room_id: 100, return_deadline: 150.0, outbound: outbound,
                                                return_walk: homeward, equipment: -> { hands.dup } })
  end

  before do
    owner.define_singleton_method(:stopping?) { false }
    run.activate_supervised(valid: -> { authority.first })
  end

  it 'keeps work completion separate until it has returned with original hands' do
    expect(run.tick[:refuge]).to include(phase: 'working', returned: false)
    result = run.tick
    expect(moves).to eq(%i[outbound return])
    expect(result[:state]).to eq(:completed)
    expect(result[:work_result]).to include(state: :completed, reason: 'room_clear')
    expect(result[:refuge]).to include(room_id: 100, returned: true, equipment_restored: true, phase: 'finished')
  end

  it 'returns on ordinary stop while retaining the stopped work result' do
    run.tick
    run.request('stop')
    result = run.tick
    expect(moves).to eq(%i[outbound return])
    expect(result[:work_result]).to include(state: :stopped, reason: 'manual_stop')
    expect(result[:refuge][:returned]).to be(true)
  end

  it 'does not move after hard authority revocation' do
    run.tick
    authority[0] = false
    result = run.tick
    expect(moves).to eq([:outbound])
    expect(result[:refuge][:returned]).to be(false)
    expect(result[:state]).to eq(:stopped)
  end

  it 'does not label swapped hands as successful equipment recovery' do
    run.tick
    hands[:hands] = ['999', nil]
    result = run.tick
    expect(result[:refuge][:equipment_restored]).to be(false)
    expect(result[:state]).to eq(:stopped)
    expect(moves).to eq([:outbound])
  end

  it 'cannot return after the frozen return deadline' do
    run.tick
    clock[0] = 150.0
    result = run.tick
    expect(moves).to eq([:outbound])
    expect(result[:refuge][:returned]).to be(false)
  end

  it 'refuses departure if the original hands change while waiting for activation' do
    hands[:hands] = ['999', nil]
    result = run.tick
    expect(result[:state]).to eq(:stopped)
    expect(result[:refuge][:equipment_restored]).to be(false)
  end

  it 'returns on a held safety failure instead of waiting indefinitely in the field' do
    run.tick
    world.merge!(safe: false, safety_reason: 'wounded')
    result = run.tick
    expect(moves).to eq(%i[outbound return])
    expect(result[:work_result]).to include(state: :held, reason: 'wounded')
    expect(result[:refuge][:returned]).to be(true)
  end

  it 'does not claim a completed handoff if the native loop closes unexpectedly' do
    run.tick
    run.close
    expect(run.status).to include(state: :stopped, reason: 'refuge_outing_incomplete')
    expect(run.status[:refuge][:returned]).to be(false)
  end

  it 'attempts bounded native return after an ordinary loop exception without disguising failed work' do
    source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
    loop_method = source[/^    def quick_run_loop\(.*?^    end$/m]
    runner = Object.new
    runner.singleton_class.class_eval(loop_method)
    runner.define_singleton_method(:with_quick_controls) { |*, **, &block| block.call }
    owner.define_singleton_method(:execution_sleep) { |_| }
    iterations = 0
    expect do
      runner.quick_run_loop(run, owner: owner) do
        iterations += 1
        raise 'ordinary test failure' if iterations == 2
      end
    end.to raise_error(RuntimeError, 'ordinary test failure')
    expect(moves).to eq(%i[outbound return])
    expect(run.status[:work_result]).to include(state: :stopped, reason: 'execution_error')
    expect(run.status[:refuge][:returned]).to be(true)
  end

  it 'does not recover an ordinary failure by bypassing hard authority revocation' do
    run.tick
    authority[0] = false
    run.fail('execution_error')
    expect(run.status[:refuge][:returned]).to be(false)
    expect(moves).to eq([:outbound])
  end

  context 'through the production native walking adapter' do
    let(:owner) { BigshotQuickWalkSpec::Owner.new }
    let(:map) { double('directed map') }
    let(:movement) do
      lambda do |command|
        owner.emit(">#{command}")
        world[:room_id] = command == 'north' ? 200 : 100
        world[:room_epoch] += 1
        world[:destination_safe] = world[:room_id] == 100
      end
    end
    let(:outbound) do
      BigshotQuickWalkSpec::QuickRetreatWalk.new({ 'max_actions' => 36, 'max_seconds' => 20 },
                                                 destinations: ['200'], owner: owner, prefix: '>', movement: movement, map: map,
                                                 clock: -> { clock.first }, allowed_rooms: [100, 200], max_steps: 12,
                                                 absolute_deadline: 120.0, require_safe_destination: false)
    end
    let(:homeward) do
      BigshotQuickWalkSpec::QuickRetreatWalk.new({ 'max_actions' => 36, 'max_seconds' => 20 },
                                                 destinations: ['100'], owner: owner, prefix: '>', movement: movement, map: map,
                                                 clock: -> { clock.first }, allowed_rooms: [100, 200], max_steps: 12,
                                                 absolute_deadline: 150.0)
    end

    before do
      stub_const('BigshotQuickWalkSpec::Script', double(current: owner))
      allow(map).to receive(:[]).with(100).and_return(BigshotQuickWalkSpec::Room.new({ '200' => 'north' }, { '200' => 0.1 }))
      allow(map).to receive(:[]).with(200).and_return(BigshotQuickWalkSpec::Room.new({ '100' => 'south' }, { '100' => 0.1 }))
      allow(map).to receive(:dijkstra).with(100, 200, static_only: true).and_return([{ 200 => 100 }, { 100 => 0, 200 => 0.1 }])
      allow(map).to receive(:dijkstra).with(200, 100, static_only: true).and_return([{ 100 => 200 }, { 200 => 0, 100 => 0.1 }])
    end

    it 'moves out and back through separately guarded native scopes' do
      expect(run.tick[:refuge][:phase]).to eq('working')
      expect(run.tick[:refuge]).to include(returned: true, equipment_restored: true,
                                           outbound_sends: 1, return_sends: 1,
                                           outbound_reason: 'retreated', return_reason: 'retreated')
      expect(owner.writes).to eq(['>north', '>south'])
      expect(owner).not_to be_execution_guard_active
    end

    it 'allows no return write after hard revocation even though work completed' do
      run.tick
      authority[0] = false
      expect(run.tick[:refuge][:returned]).to be(false)
      expect(owner.writes).to eq(['>north'])
    end
  end

  context 'with an interrupted eLoot equipment recovery' do
    let(:loot) { BigshotQuickRunSpec::QuickLoot.new({ 'loot' => 'off' }, character: 'Tester') }

    it 'permits only the equipment reserve after a graceful stop and verifies original hands before returning' do
      run.tick
      hands[:hands] = ['123', '999']
      equipment = hands
      recovery = []
      engine.define_singleton_method(:quick_loot_restore) do |guard:, **|
        guard.transmit('put #999 in #888') { recovery << :sheath; equipment[:hands] = ['123', nil] }
        { outcome: :complete }
      end
      run.request('stop')
      result = run.tick
      expect(recovery).to eq([:sheath])
      expect(result[:refuge]).to include(returned: true, equipment_restored: true)
      expect(result[:work_result][:reason]).to eq('manual_stop')
    end

    it 'does not trust a successful eLoot return value when hand IDs remain wrong' do
      run.tick
      hands[:hands] = ['123', '999']
      engine.define_singleton_method(:quick_loot_restore) { |**| { outcome: :complete } }
      result = run.tick
      expect(result[:refuge]).to include(returned: false, equipment_restored: false)
      expect(moves).to eq([:outbound])
    end

    it 'does not begin equipment writes after the frozen cleanup deadline' do
      run.tick
      hands[:hands] = ['123', '999']
      clock[0] = 130.0
      expect(engine).not_to receive(:quick_loot_restore)
      expect(run.tick[:refuge][:returned]).to be(false)
    end
  end
end
