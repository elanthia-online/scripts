# frozen_string_literal: true

require_relative '../../support/bigshot_quick_walk_harness'

# Production route adapter with synthetic world/map/helper observations, not a
# live walk. The native static Dijkstra implementation has its own map tests.
RSpec.describe BigshotQuickWalkSpec::QuickRetreatWalk do
  let(:owner) { BigshotQuickWalkSpec::Owner.new }
  let(:now) { [100.0] }
  let(:world) do
    { session: +'login', room_id: 100, room_epoch: 1, stable: true,
      owner: true, connected: true, alive: true, destination_safe: false }
  end
  let(:settings) { { 'max_actions' => 6, 'max_seconds' => 1 } }
  let(:rooms) do
    { 100 => BigshotQuickWalkSpec::Room.new({ '150' => +'north' }, { '150' => 0.5 }),
      150 => BigshotQuickWalkSpec::Room.new({ '200' => +'go gate' }, { '200' => 0.5 }),
      200 => BigshotQuickWalkSpec::Room.new({}, {}) }
  end
  let(:map) { double('static native map') }
  let(:destinations) { %w[200 999] }
  let(:restrictions) { {} }
  let(:movement) do
    lambda do |command|
      owner.emit(">#{command}")
      world[:room_id] = world[:room_id] == 100 ? 150 : 200
      world[:room_epoch] += 1
      world[:destination_safe] = world[:room_id] == 200
    end
  end
  let(:adapter) do
    described_class.new(settings, destinations: destinations, owner: owner, prefix: '>', movement: movement,
                        map: map, clock: -> { now.first }, **restrictions)
  end

  before do
    stub_const('BigshotQuickWalkSpec::Script', double(current: owner))
    allow(map).to receive(:[]) { |id| rooms[id] }
    allow(map).to receive(:dijkstra).with(100, nil, static_only: true).and_return(
      [{ 150 => 100, 200 => 150 }, { 100 => 0, 150 => 0.5, 200 => 1.0 }]
    )
    owner.on_sleep = ->(seconds) { now[0] += seconds }
  end

  def retreat(&observation)
    adapter.call { observation ? observation.call : world.dup }
  end

  it 'reuses the static native pathfinder and confirms every edge before the explicit refuge' do
    expect(retreat).to eq(outcome: :retreated, sends: 2, reason: 'retreated')
    expect(owner.writes).to eq(['>north', '>go gate'])
    expect(map).to have_received(:dijkstra).once.with(100, nil, static_only: true)
    expect(owner).not_to be_execution_guard_active
  end

  context 'with supervised route restrictions' do
    let(:restrictions) { { allowed_rooms: [100, 150, 200], max_steps: 12, absolute_deadline: 100.5 } }

    it 'admits directed routes without sending or entering a native scope' do
      expect(adapter.admit_route!(100)).to be(true)
      expect(owner.writes).to be_empty
      expect(owner).not_to be_execution_guard_active
    end

    it 'rejects a path crossing a room outside the pinned area' do
      restrictions[:allowed_rooms] = [100, 200]
      expect { adapter.admit_route!(100) }.to raise_error(described_class::Interrupted, /outside_area/)
      expect(owner.writes).to be_empty
    end

    it 'rejects an outbound-only one-way map before departure' do
      allow(map).to receive(:dijkstra).with(150, nil, static_only: true).and_return([{}, { 150 => 0 }])
      expect { adapter.admit_route!(150) }.to raise_error(described_class::Interrupted, /unavailable/)
      expect(owner.writes).to be_empty
    end

    it 'caps route edges separately from helper sends' do
      restrictions[:max_steps] = 1
      expect { adapter.admit_route!(100) }.to raise_error(described_class::Interrupted, /action_limit/)
    end

    it 'honors the fixed phase deadline even when its ordinary walk budget remains' do
      now[0] = 100.4
      instance = adapter
      now[0] = 100.6
      expect(instance.call { world.dup }).to include(outcome: :unconfirmed, reason: 'retreat_time_limit')
      expect(owner.writes).to be_empty
    end

    it 'allows arrival into the hunting area without calling it a safe refuge' do
      restrictions[:require_safe_destination] = false
      allow(movement).to receive(:call).and_wrap_original do |method, command|
        method.call(command)
        world[:destination_safe] = false
      end
      expect(retreat).to include(outcome: :retreated)
    end
  end

  it 'chooses the nearest reachable explicitly configured destination, never a guessed room' do
    destinations.replace(%w[200 150])
    allow(movement).to receive(:call).and_wrap_original do |method, command|
      method.call(command)
      world[:destination_safe] = true
    end
    expect(retreat).to eq(outcome: :retreated, sends: 1, reason: 'retreated')
    expect(world[:room_id]).to eq(150)
  end

  it 'can prove an already configured refuge with zero movement and no route lookup' do
    world.merge!(room_id: 200, destination_safe: true)
    expect(retreat).to eq(outcome: :retreated, sends: 0, reason: 'already_at_refuge')
    expect(map).not_to have_received(:dijkstra)
    expect(owner.writes).to be_empty
  end

  it 'rejects cyclic, broken and unreachable predecessor results before movement' do
    [{ 200 => 150, 150 => 200 }, { 200 => nil }, { 200 => 4, 4 => 100 }, {}].each do |previous|
      allow(map).to receive(:dijkstra).and_return([previous, { 200 => 1 }])
      expect(retreat[:reason]).to eq('retreat_route_invalid')
    end
    allow(map).to receive(:dijkstra).and_return([{}, {}])
    expect(retreat[:reason]).to eq('retreat_route_unavailable')
    expect(owner.writes).to be_empty
  end

  it 'permits no planning send and refuses displacement during route lookup' do
    allow(map).to receive(:dijkstra) { owner.emit('>north') }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 0, reason: 'retreat_command_denied')
    allow(map).to receive(:dijkstra) do
      world[:room_epoch] += 1
      [{ 150 => 100, 200 => 150 }, { 200 => 1 }]
    end
    expect(retreat).to eq(outcome: :unconfirmed, sends: 0, reason: 'retreat_unexpected_displacement')
    expect(owner.writes).to be_empty
  end

  it 'rejects missing route support, unstable origin and unsafe existing refuge' do
    allow(map).to receive(:dijkstra).and_return(nil)
    expect(retreat[:reason]).to eq('retreat_route_unavailable')
    world[:stable] = false
    expect(retreat[:reason]).to eq('retreat_origin_unverified')
    world.merge!(room_id: 200, stable: true, destination_safe: false)
    expect(retreat[:reason]).to eq('retreat_destination_unsafe')
    expect(owner.writes).to be_empty
  end

  it 'rejects executable or unsafe string edges before any send without calling them' do
    executable = proc { raise 'route code must not execute' }
    [executable, 'sell all', 'drop sword', ';go2 200', "north\nlook", 'go gate;look'].each do |edge|
      rooms[150].wayto['200'] = edge
      expect(retreat[:reason]).to eq('retreat_route_unsupported')
    end
    rooms[150].wayto['200'] = 'go gate'
    rooms[150].timeto['200'] = executable
    expect(retreat[:reason]).to eq('retreat_route_unsupported')
    expect(owner.writes).to be_empty
  end

  it 'freezes planned commands while giving native move a disposable mutable copy' do
    allow(movement).to receive(:call).and_wrap_original do |method, command|
      rooms[150].wayto['200'].replace('drop sword') if command == 'north'
      method.call(command)
      command.replace('discarded helper scratch')
    end
    expect(retreat[:outcome]).to eq(:retreated)
    expect(owner.writes).to eq(['>north', '>go gate'])
  end

  it 'allows bounded stand, unhide and derived open but no arbitrary supporting command' do
    allow(movement).to receive(:call).and_wrap_original do |method, command|
      owner.emit('>stand') if command == 'north'
      owner.emit('>unhide') if command == 'north'
      owner.emit('>open gate') if command == 'go gate'
      method.call(command)
    end
    expect(retreat).to eq(outcome: :retreated, sends: 5, reason: 'retreated')
  end

  it 'denies inventory, banking, spells and unplanned changed directions' do
    ['>get sword', '>withdraw 100 silver', '>incant 130', '>east', '>open chest'].each do |wire|
      allow(movement).to receive(:call) { owner.emit(wire) }
      expect(retreat).to eq(outcome: :unconfirmed, sends: 0, reason: 'retreat_command_denied')
    end
    expect(owner.writes).to be_empty
  end

  it 'refuses every later send after unexpected movement and does not reroute' do
    allow(movement).to receive(:call) do |command|
      owner.emit(">#{command}")
      world.merge!(room_id: 999, room_epoch: 2, destination_safe: true)
      owner.emit('>north')
    end
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_unexpected_displacement')
    expect(owner.writes).to eq(['>north'])
  end

  it 'does not mistake same-room refresh or unchanged epoch for expected movement' do
    allow(movement).to receive(:call) { |command| owner.emit(">#{command}"); world[:room_epoch] += 1 }
    expect(retreat[:reason]).to eq('retreat_unexpected_displacement')
    world[:room_epoch] = 1
    allow(movement).to receive(:call) { |command| owner.emit(">#{command}"); world[:room_id] = 150 }
    expect(retreat[:reason]).to eq('retreat_unexpected_displacement')
  end

  it 'waits through transient room parsing but never sends from an unstable observation' do
    allow(movement).to receive(:call).and_wrap_original do |method, command|
      method.call(command)
      world[:stable] = false
    end
    owner.on_sleep = ->(seconds) { now[0] += seconds; world[:stable] = true }
    expect(retreat[:outcome]).to eq(:retreated)
  end

  it 'rejects attempted retry sends while room state is unstable' do
    allow(movement).to receive(:call) do |command|
      owner.emit(">#{command}")
      world[:stable] = false
      owner.emit(">#{command}")
    end
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_observation_unverified')
  end

  it 'copies session identity and prevents every new send after deadline expiry' do
    allow(movement).to receive(:call) do |command|
      owner.emit(">#{command}")
      world[:session].replace('replaced')
      owner.emit(">#{command}")
    end
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'session_changed')
    world[:session] = 'login'
    allow(movement).to receive(:call) do |command|
      owner.emit(">#{command}")
      now[0] += 1
      owner.emit(">#{command}")
    end
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_time_limit')
  end

  it 'bounds a no-progress native helper and counts each accepted retry' do
    settings['max_actions'] = 2
    allow(movement).to receive(:call) { |command| owner.emit(">#{command}") }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_time_limit')
    now[0] = 100
    allow(movement).to receive(:call) { |command| 3.times { owner.emit(">#{command}") } }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 2, reason: 'retreat_action_limit')
  end

  it 'returns promptly on native false or nil with verified unchanged room' do
    [false, nil].each do |value|
      allow(movement).to receive(:call) { |command| owner.emit(">#{command}"); value }
      expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_move_failed')
      expect(now.first).to eq(100)
    end
  end

  it 'can confirm already observed expected arrival despite an opaque false movement result' do
    allow(movement).to receive(:call).and_wrap_original do |method, command|
      method.call(command)
      false
    end
    expect(retreat).to eq(outcome: :retreated, sends: 2, reason: 'retreated')
  end

  it 'honors stop even if the movement helper swallows native interruption' do
    allow(movement).to receive(:call) do |command|
      owner.emit(">#{command}")
      world[:escape_cancelled] = 'manual_stop'
      begin
        owner.check_execution_guard!
      rescue BigshotQuickWalkSpec::Owner::Denied
        world.merge!(room_id: 200, room_epoch: 2, destination_safe: true)
      end
    end
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'manual_stop')
    expect(owner.writes).to eq(['>north'])
  end

  it 'requires session, ownership, survival and destination safety proof after walking' do
    [[:owner, false, 'owner_lost'], [:connected, false, 'disconnected'],
     [:alive, false, 'retreat_survival_unverified'], [:session, 'other', 'session_changed'],
     [:destination_safe, false, 'retreat_destination_unsafe']].each do |key, value, reason|
      world.replace(session: 'login', room_id: 100, room_epoch: 1, stable: true,
                    owner: true, connected: true, alive: true, destination_safe: false)
      allow(movement).to receive(:call).and_wrap_original do |method, command|
        method.call(command)
        world[key] = value if world[:room_id] == 200
      end
      expect(retreat[:reason]).to eq(reason)
    end
  end
end
