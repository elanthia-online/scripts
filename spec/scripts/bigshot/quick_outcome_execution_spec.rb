# frozen_string_literal: true

require_relative '../../support/bigshot_quick_native_cmd_support'

module BigshotQuickNativeCmdSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  module_eval(source[/^  class QuickOutcomeEvidence\n.*?^  end$/m], __FILE__, __LINE__)
end

# Production command execution and controller; only transport, game observations
# and the native observer publication are fixtures. Native parsing is separately
# replay-tested, not inferred from these handcrafted event contracts.
RSpec.describe 'Quick native execution outcome integration' do
  let(:owner) { BigshotQuickNativeCmdSpec::Owner.new }
  let(:engine) { BigshotQuickNativeCmdSpec::Engine.new(owner) }
  let(:npc) { Struct.new(:id, :name, :noun).new('123', 'giant rat', 'rat') }
  let(:context) { { connection_id: 1, game: 'GSIV', character: 'Probe', room_epoch: 1 } }
  let(:callbacks) { [] }
  let(:tracker) { double('native tracker') }
  let(:settings) { { 'mode' => 'watch', 'max_actions' => 20, 'max_seconds' => 30, 'max_ineffective' => 2 } }
  let(:snapshot) do
    { session: 'login', room_id: 100, room_epoch: 1, owner: true, connected: true, safe: true,
      targets: [{ id: '123', name: 'giant rat', noun: 'rat', hostile: true }], members: [] }
  end
  let(:policy) do
    BigshotQuickNativeCmdSpec::EncounterPolicy.new(settings, targets: { 'giant rat' => 'a' },
                                                             routines: { 'a' => ['attack target'] })
  end
  let(:retreats) { [] }
  let(:run) do
    BigshotQuickNativeCmdSpec::QuickRun.new(engine: engine, policy: policy, owner: owner,
                                            snapshot: -> { snapshot }, resolve_target: ->(_id) { npc },
                                            validate: ->(_command) { true }, prefix: '>',
                                            retreat: -> { retreats << true; :retreated })
  end

  before do
    stub_const('BigshotQuickNativeCmdSpec::Lich', Module.new)
    stub_const('BigshotQuickNativeCmdSpec::Lich::Gemstone', Module.new)
    stub_const('BigshotQuickNativeCmdSpec::Lich::Gemstone::Combat', Module.new)
    stub_const('BigshotQuickNativeCmdSpec::Lich::Gemstone::Combat::Tracker', tracker)
    allow(tracker).to receive(:enabled?).and_return(true)
    allow(tracker).to receive(:observation_context) { context.dup.freeze }
    allow(tracker).to receive(:on) do |type, &callback|
      raise 'wrong observer type' unless type == :attack
      callbacks << callback
      callback
    end
    allow(tracker).to receive(:off) { |callback| callbacks.delete(callback) }
    BigshotQuickNativeCmdSpec::Script.current = owner
    BigshotQuickNativeCmdSpec::Spell.entries = { 1201 => BigshotQuickNativeCmdSpec::NativeSpell.new(1201, owner, known: false) }
    %i[debug_msg check_for_deaders_prone escape_rooms waitrt? waitcastrt? change_stance].each do |method|
      allow(engine).to receive(method)
    end
    allow(engine).to receive(:dead_or_gone?).and_return(false)
    allow(engine).to receive(:valid_target?).with(npc).and_return(true)
    allow(engine).to receive(:still_targetable?).with('123').and_return(true)
    allow(engine).to receive(:standing?).and_return(true)
    @batch = 0
    @workers = []
    @saved_ambusher = $ambusher_here
    $ambusher_here = nil
  end

  after do
    @workers.each(&:join)
    run.close
    BigshotQuickNativeCmdSpec::Script.current = nil
    BigshotQuickNativeCmdSpec::Spell.entries = nil
    $ambusher_here = @saved_ambusher
    expect(callbacks).to be_empty
    expect(owner.execution_guard_active?).to be(false)
  end

  def publish(outcome, **overrides)
    @batch += 1
    event = { name: :attack, _attack_born: true, _uid: 0, root_uid: 0, parent_uid: nil,
              target: { id: '123' }, attacker: nil, outcomes: [outcome], hits: [], statuses: [], flares: [],
              source: context.merge(sequence: @batch, received_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)),
              observation_batch: { id: @batch, index: 0, size: 1 } }.merge(overrides)
    callbacks.dup.each { |callback| callback.call(:attack, event) }
  end

  it 'counts real command dispatches with observed misses toward the configured hold threshold' do
    owner.on_send = ->(_wire) { publish(:miss) }
    expect(run.tick).to include(state: :running, actions: 1)
    expect(run.tick).to include(state: :held, reason: 'ineffective_limit', actions: 2)
    expect(owner.wires).to eq(['>attack #123', '>attack #123'])
  end

  it 'uses the configured retreat adapter at the observed ineffective threshold' do
    settings['ineffective_action'] = 'retreat'
    owner.on_send = ->(_wire) { publish(:warded) }
    run.tick
    expect(run.tick).to include(state: :stopped, reason: 'retreated')
    expect(retreats).to eq([true])
  end

  it 'resets the failed-attack counter on correlated positive native evidence' do
    outcomes = %i[miss hit miss miss]
    owner.on_send = ->(_wire) { publish(outcomes.shift) }
    3.times { expect(run.tick[:state]).to eq(:running) }
    expect(run.tick).to include(state: :held, reason: 'ineffective_limit')
  end

  it 'does not count a nearby player hit as success or reset the failed-attack counter' do
    count = 0
    owner.on_send = lambda do |_wire|
      count += 1
      if count == 2
        publish(:hit, attacker: { id: '-456', name: 'Friend' }, foreign_caster: true)
      else
        publish(:miss)
      end
    end
    2.times { expect(run.tick[:state]).to eq(:running) }
    expect(run.tick).to include(state: :held, reason: 'ineffective_limit')
  end

  it 'keeps missing evidence uncertain and releases the observer on stop during the wait' do
    owner.on_send = ->(_wire) { run.request('stop') }
    expect(run.tick[:state]).to eq(:stopped)
    expect(retreats).to be_empty
    expect(owner.wires).to eq(['>attack #123'])
  end

  it 'does not treat a miss with a damaging flare as a wholly ineffective attack' do
    owner.on_send = ->(_wire) { publish(:miss, flares: [{ hits: [{ damage: 10 }], outcomes: [] }]) }
    3.times { expect(run.tick[:state]).to eq(:running) }
    expect(retreats).to be_empty
  end

  it 'waits cooperatively for a delayed native observation rather than immediately returning sent' do
    owner.on_send = lambda do |_wire|
      @workers << Thread.new do
        sleep(0.02)
        publish(:miss)
      end
    end
    expect(run.tick[:observations].last).to include(outcome: :ineffective, evidence_reason: :native_failure_observed)
    expect(run.tick).to include(state: :held, reason: 'ineffective_limit')
  end

  it 'does not classify an incompletely emitted native batch as a failure' do
    settings['max_ineffective'] = 1
    owner.on_send = ->(_wire) { publish(:miss, observation_batch: { id: 1, index: 0, size: 2 }) }
    result = run.tick
    expect(result[:state]).to eq(:running)
    expect(result[:observations].last).to include(outcome: :sent, evidence_reason: :evidence_pending)
    expect(retreats).to be_empty
  end

  it 'refuses future sends if required tracking is disabled after startup admission' do
    engine.instance_variable_set(:@quick_outcome_required, true)
    allow(tracker).to receive(:enabled?).and_return(false)
    expect(run.tick).to include(state: :held, reason: 'outcome_observation_unavailable')
    expect(owner.wires).to be_empty
  end

  it 'interrupts a native multi-command routine if required tracking disappears between writes' do
    engine.instance_variable_set(:@quick_outcome_required, true)
    identity = { session: 'login', room_id: 100, room_epoch: 1, target_id: '123' }
    guard = BigshotQuickNativeCmdSpec::QuickGuard.new(identity: identity, max_sends: 5, max_seconds: 10,
                                                      snapshot: -> { identity.merge(owner: true, connected: true, safe: true, authorized: true, target_valid: true, control: :running) })
    owner.on_send = ->(_wire) { allow(tracker).to receive(:enabled?).and_return(false) }
    expect { engine.quick_execute(['attack target', 'attack target'], npc, guard: guard, owner: owner, prefix: '>') }
      .to raise_error(BigshotQuickNativeCmdSpec::QuickGuard::Interrupted, /outcome_observation_unavailable/)
    expect(owner.wires).to eq(['>attack #123'])
  end
end
