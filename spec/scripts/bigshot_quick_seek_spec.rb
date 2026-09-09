# frozen_string_literal: true

require_relative '../support/bigshot_quick_run_harness'

module BigshotQuickSeekSpec
  class Owner
    def execution_guard_active? = !@guard.nil?

    def with_execution_guard(guard)
      raise 'nested guard' if @guard
      @guard = guard
      check_execution_guard!
      result = yield
      check_execution_guard!
      result
    ensure
      @guard = nil
    end

    def check_execution_guard!(command: nil)
      raise 'denied' unless @guard.call(command)
    end

    def execution_sleep(_seconds)
      check_execution_guard!
      raise 'unexpected wait in fixture'
    end
  end

  if ENV['LICH_EXECUTION_GUARD_ROOT']
    require File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script_execution_guard')
    native = File.read(File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script.rb')).gsub("\r\n", "\n")
    Owner.const_set(:ScriptExecutionGuard, Lich::Common::ScriptExecutionGuard)
    Owner.const_set(:EXECUTION_GUARD_MUTEX_INITIALIZER, Mutex.new)
    %w[with_execution_guard execution_guard_active? check_execution_guard! execution_guard_mutex].each do |name|
      body = native[/^      def #{Regexp.escape(name)}(?:\([^\n]*\))?\n.*?^      end$/m]
      raise "missing native #{name}" unless body
      Owner.class_eval(body)
    end
  end
end

RSpec.describe BigshotQuickRunSpec::QuickSeek do
  let(:clock) { [10.0] }
  let(:owner) { BigshotQuickSeekSpec::Owner.new }
  let(:snapshot) do
    { session: 'test-session', room_id: 100, room_epoch: 1, safe: true,
      owner: true, connected: true, control: :running, eligible_target: false }
  end
  let(:area) { double('profile area') }
  let(:writes) { [] }
  let(:movement) do
    lambda do |direction|
      owner.check_execution_guard!(command: ">#{direction}")
      writes << direction
      snapshot[:room_id] = 101
      snapshot[:room_epoch] += 1
      true
    end
  end
  let(:seek) do
    described_class.new({ 'max_actions' => 20, 'max_seconds' => 60 }, area: area, owner: owner,
                        prefix: '>', movement: movement, clock: -> { clock.first })
  end

  def step
    seek.call(snapshot: snapshot.dup) { snapshot.dup }
  end

  before do
    stub_const('BigshotQuickRunSpec::Script', double('Script', current: owner))
    allow(area).to receive(:valid?) { |id| [100, 101, 102].include?(id) }
    allow(area).to receive(:quick_steps).with(100).and_return([[101, 'north'], [102, 'east']])
    allow(area).to receive(:quick_steps).with(101).and_return([[100, 'south'], [102, 'east']])
  end

  it 'sends exactly one mapped direction and verifies arrival' do
    expect(step).to eq(outcome: :moved)
    expect(writes).to eq(['north'])
    expect(seek.status).to include(steps: 1, sends: 1, max_steps: 12, max_seconds: 30)
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'does not move when a target is already eligible' do
    snapshot[:eligible_target] = true
    expect(step).to include(outcome: :found, reason: 'seek_target_found')
    expect(writes).to be_empty
  end

  it 'hands off when a target appears immediately before the send' do
    allow(area).to receive(:quick_steps) { snapshot[:eligible_target] = true; [[101, 'north']] }
    expect(step).to include(outcome: :found)
    expect(writes).to be_empty
  end

  it 'accepts an eligible arrival without issuing another movement command' do
    original = movement
    seeker = described_class.new({}, area: area, owner: owner, prefix: '>', clock: -> { clock.first },
                                 movement: ->(direction) { original.call(direction); snapshot[:eligible_target] = true })
    expect(seeker.call(snapshot: snapshot.dup) { snapshot.dup }).to eq(outcome: :found)
    expect(writes).to eq(['north'])
  end

  it 'rejects unrelated command helpers and retries without counting them as sent' do
    %w[stand south north].each do |extra|
      snapshot.merge!(room_id: 100, room_epoch: 1)
      seeker = described_class.new({}, area: area, owner: owner, prefix: '>', movement: lambda { |direction|
        owner.check_execution_guard!(command: ">#{direction}")
        owner.check_execution_guard!(command: ">#{extra}")
      })
      expect(seeker.call(snapshot: snapshot.dup) { snapshot.dup }).to include(outcome: :interrupted, reason: 'seek_command_denied')
      expect(seeker.status[:sends]).to eq(1)
    end
  end

  it 'denies commands from travel-time callbacks before any step is admitted' do
    allow(area).to receive(:quick_steps) { owner.check_execution_guard!(command: '>north'); [[101, 'north']] }
    expect(step).to include(outcome: :interrupted)
    expect(writes).to be_empty
  end

  it 'rejects unexpected displacement, including another in-area room' do
    allow(area).to receive(:quick_steps) { snapshot[:room_id] = 102; [[101, 'north']] }
    expect(step).to include(outcome: :interrupted, reason: 'seek_unexpected_displacement')
    expect(writes).to be_empty
  end

  it 'stops at an area exit without moving' do
    snapshot[:room_id] = 999
    expect(step).to include(outcome: :interrupted, reason: 'profile_area_exit')
    expect(writes).to be_empty
  end

  it 'rejects missing identity, unsafe, disconnected, lost-owner and held states' do
    { session: nil, room_epoch: nil, safe: false, owner: false, connected: false, control: :held }.each do |key, value|
      previous = snapshot[key]
      snapshot[key] = value
      seeker = described_class.new({}, area: area, owner: owner, prefix: '>', movement: movement)
      expect(seeker.call(snapshot: snapshot.dup) { snapshot.dup }[:outcome]).to eq(:interrupted), key.to_s
      snapshot[key] = previous
    end
    expect(writes).to be_empty
  end

  it 'stops when there is no supported exit' do
    allow(area).to receive(:quick_steps).and_return([])
    expect(step).to include(reason: 'seek_no_exit')
    expect(writes).to be_empty
  end

  it 'reports an unexpected exception location without including its message' do
    failure = RuntimeError.new('private runtime details')
    failure.set_backtrace(['/private/path/native.rb:42:in movement'])
    allow(area).to receive(:quick_steps).and_raise(failure)
    expect(step).to include(reason: 'seek_execution_error')
    expect(seek.status[:error]).to eq(class: 'RuntimeError', location: 'native.rb:42:in movement')
    expect(seek.status.to_s).not_to include('private runtime details', '/private/path')
    expect(writes).to be_empty
  end

  it 'does not reset the total search deadline across steps' do
    expect(step[:outcome]).to eq(:moved)
    clock[0] += 30
    expect(step).to include(reason: 'seek_time_limit')
    expect(writes.size).to eq(1)
  end

  it 'does not retry a timed-out movement' do
    seeker = described_class.new({}, area: area, owner: owner, prefix: '>', clock: -> { clock.first },
                                 movement: ->(direction) { owner.check_execution_guard!(command: ">#{direction}"); clock[0] += 3 })
    expect(seeker.call(snapshot: snapshot.dup) { snapshot.dup }).to include(reason: 'seek_move_unconfirmed')
    expect(seeker.status[:sends]).to eq(1)
  end

  it 'caps the search at the smaller configured action limit' do
    seeker = described_class.new({ 'max_actions' => 1 }, area: area, owner: owner, prefix: '>', movement: movement)
    expect(seeker.call(snapshot: snapshot.dup) { snapshot.dup }[:outcome]).to eq(:moved)
    expect(seeker.call(snapshot: snapshot.dup) { snapshot.dup }).to include(reason: 'seek_step_limit')
  end
end

RSpec.describe 'Quick seek encounter handoff' do
  let(:snapshot) { { session: 'test', room_id: 100, room_epoch: 1, safe: true, owner: true, connected: true, targets: [] } }
  let(:target) { { id: '123', name: 'giant rat', hostile: true } }
  let(:searches) { [] }
  let(:attacks) { [] }
  let(:cleanups) { [] }
  let(:controller) do
    policy = BigshotQuickRunSpec::EncounterPolicy.new({ 'mode' => 'seek' }, targets: { 'giant rat' => 'a' }, routines: { 'a' => ['attack target'] })
    BigshotQuickRunSpec::EncounterController.new(policy: policy, snapshot: -> { snapshot.dup },
                                                 dispatch: ->(**args) { attacks << args; { outcome: :effective, sends: 1 } },
                                                 seek: ->(observed) { searches << observed; { outcome: :moved } },
                                                 after_clear: ->(**args) { cleanups << args; { outcome: :complete } })
  end

  it 'searches without cleanup, follows the search room, then clears once and never searches again' do
    expect(controller.tick[:state]).to eq(:running)
    expect(cleanups).to be_empty
    snapshot.merge!(room_id: 101, room_epoch: 2, targets: [target])
    expect(controller.tick[:actions]).to eq(1)
    snapshot[:targets] = []
    expect(controller.tick).to include(state: :completed, reason: 'room_clear')
    controller.tick
    expect(searches.size).to eq(1)
    expect(attacks.size).to eq(1)
    expect(cleanups.size).to eq(1)
  end

  it 'pins the combat room after selecting a target, even if it subsequently leaves' do
    snapshot[:targets] = [target]
    controller.tick
    snapshot.merge!(room_id: 101, room_epoch: 2, targets: [])
    expect(controller.tick).to include(state: :stopped, reason: 'room_changed')
    expect(searches).to be_empty
    expect(cleanups).to be_empty
  end

  it 'does not search while held or after stop' do
    controller.hold
    controller.tick
    controller.stop
    controller.tick
    expect(searches).to be_empty
  end

  it 'does not resume searching if a discovered target leaves before the next combat tick' do
    seek = ->(_scene) { snapshot.merge!(room_id: 101, room_epoch: 2); { outcome: :found } }
    controller.instance_variable_set(:@seek, seek)
    expect(controller.tick[:state]).to eq(:running)
    expect(controller.tick).to include(state: :completed, reason: 'room_clear')
    expect(attacks).to be_empty
  end
end

RSpec.describe 'QuickRun with the bounded native seek adapter' do
  let(:owner) { BigshotQuickSeekSpec::Owner.new }
  let(:scene) { { session: 'synthetic', room_id: 100, room_epoch: 1, safe: true, owner: true, connected: true, targets: [] } }
  let(:area) { double('area') }
  let(:writes) { [] }
  let(:settings) { { 'mode' => 'seek', 'max_actions' => 10, 'max_seconds' => 30 } }
  let(:policy) { BigshotQuickRunSpec::EncounterPolicy.new(settings, targets: { 'giant rat' => 'a' }, routines: { 'a' => ['attack target'] }) }
  let(:engine) { double('native combat') }
  let(:movement) do
    lambda do |direction|
      owner.check_execution_guard!(command: ">#{direction}")
      writes << direction
      scene.merge!(room_id: 101, room_epoch: 2, targets: [{ id: '123', name: 'giant rat', hostile: true }])
    end
  end
  let(:seeker) { BigshotQuickRunSpec::QuickSeek.new(settings, area: area, owner: owner, prefix: '>', movement: movement) }
  let(:run) do
    BigshotQuickRunSpec::QuickRun.new(engine: engine, policy: policy, owner: owner, snapshot: -> { scene.dup },
                                      resolve_target: ->(_id) { Object.new }, validate: ->(_command) { true }, prefix: '>', area: area, seek: seeker)
  end

  before do
    stub_const('BigshotQuickRunSpec::Script', double('Script', current: owner))
    allow(area).to receive(:valid?) { |id| [100, 101].include?(id) }
    source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
    %w[quick_wound_observation quick_seek_execute].each do |name|
      body = source[/^  def #{name}\(.*?^  end$/m]
      engine.singleton_class.class_eval(body) if body
    end
    stub_const('Script', double('native owner', current: owner))
    allow(area).to receive(:quick_steps).with(100).and_return([[101, 'north']])
    allow(area).to receive(:quick_status) { |id| { kind: :profile, start_room_id: 100, boundary_room_ids: [102], room_count: 2, room_id: id, in_bounds: [100, 101].include?(id) } }
    allow(engine).to receive(:quick_execute) do |_command, _target, guard:, **_kwargs|
      guard.transmit('attack #123') { writes << 'attack #123' }
      scene[:targets] = []
      { outcome: :effective, sends: guard.sends }
    end
  end

  it 'locally finds a target, attacks in the arrival room, then releases the run' do
    expect(run.tick).to include(state: :running, room_id: 101)
    expect(run.tick[:actions]).to eq(1)
    expect(run.tick).to include(state: :completed, reason: 'room_clear')
    run.close
    expect(writes).to eq(['north', 'attack #123'])
    expect(run.status[:search]).to include(steps: 1, sends: 1)
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'checks the real saved wound expression within the seek guard and releases its scope' do
    engine.instance_variable_set(:@WOUNDED_EVAL, 'false')
    allow(run).to receive(:run_snapshot).and_wrap_original do |original, *args|
      engine.quick_wound_observation(owner: owner)
      original.call(*args)
    end
    expect(run.tick).to include(state: :running, room_id: 101)
    expect(writes).to eq(['north'])
    expect(engine.instance_variable_get(:@quick_seek_owner)).to be_nil
    owner.with_execution_guard(->(_wire) { true }) do
      expect { engine.quick_wound_observation(owner: owner) }.to raise_error(ArgumentError, /unrelated/)
    end
  end

  it 'releases seek observation ownership when the adapter raises' do
    failing_seek = ->(**_args) { raise 'adapter failed' }
    expect { engine.quick_seek_execute(failing_seek, snapshot: scene, owner: owner) {} }.to raise_error('adapter failed')
    expect(engine.instance_variable_get(:@quick_seek_owner)).to be_nil
  end

  it 'still stops movement when the saved wound check becomes unsafe' do
    engine.instance_variable_set(:@WOUNDED_EVAL, '@test_wounded')
    allow(area).to receive(:quick_steps) { engine.instance_variable_set(:@test_wounded, true); [[101, 'north']] }
    allow(run).to receive(:run_snapshot).and_wrap_original do |original, *args|
      wounded = engine.quick_wound_observation(owner: owner)
      original.call(*args).merge(safe: !wounded, safety_reason: wounded ? 'wounded' : nil)
    end
    expect(run.tick).to include(state: :stopped, reason: 'wounded')
    expect(writes).to be_empty
    expect(engine.instance_variable_get(:@quick_seek_owner)).to be_nil
  end

  it 'applies a stop queued during movement before any send, without launching combat' do
    allow(area).to receive(:quick_steps) { run.request('stop'); [[101, 'north']] }
    expect(run.tick).to include(state: :stopped, reason: 'manual_stop')
    expect(writes).to be_empty
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'holds before movement and resumes only on the same verified scene' do
    once = true
    allow(area).to receive(:quick_steps) do
      if once
        once = false
        run.request('hold')
      end
      [[101, 'north']]
    end
    expect(run.tick).to include(state: :held, reason: 'manual_hold')
    expect(writes).to be_empty
    run.request('resume')
    expect(run.tick[:state]).to eq(:running)
    expect(writes).to eq(['north'])
  end
end
