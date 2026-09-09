# frozen_string_literal: true

module BigshotQuickReportingSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[EncounterPolicy EncounterController QuickRun].each do |name|
    body = source[/^  class #{name}\n.*?^  end$/m]
    raise "Missing #{name}" unless body
    module_eval(body)
  end
end

RSpec.describe 'Quick bounded run reporting' do
  let(:namespace) { BigshotQuickReportingSpec }
  let(:clock) { [100.0] }
  let(:settings) { { 'mode' => 'trial', 'max_actions' => 400, 'max_seconds' => 1000, 'max_ineffective' => 500 } }
  let(:target) { { id: '123', name: 'rat', noun: 'rat', hostile: true } }
  let(:snapshot) { { session: 'login', room_id: 42, room_epoch: 3, targets: [target], members: [], safe: true, owner: true, connected: true } }
  let(:policy) { namespace::EncounterPolicy.new(settings, targets: { 'rat' => 'a' }, routines: { 'a' => ['attack target'] }) }
  let(:trial) { { target_id: '123', actions: Array.new(110, 'attack target') } }
  let(:metadata) { { preset: +'invasion', profile: +'area', sequence: +'probe' } }
  let(:dispatch) { ->(**_request) { { outcome: :sent, sends: 2 } } }
  let(:controller) do
    namespace::EncounterController.new(policy: policy, snapshot: -> { snapshot }, dispatch: dispatch,
                                       trial: trial, report_metadata: metadata, clock: -> { clock.first })
  end

  it 'reports every discarded entry and separates actual sends from reserved action usage' do
    calls = 0
    allow(dispatch).to receive(:call) do
      sends = (calls % 10).zero? ? 0 : 2
      calls += 1
      { outcome: sends.zero? ? :skipped : :sent, sends: sends }
    end
    controller
    110.times { clock[0] += 0.1; controller.tick }
    report = controller.status
    expect(report).to include(state: :completed, reason: 'sequence_dispatched', actions: 209, sends: 198,
                              sends_unverified: 0, observations_total: 110, observations_dropped: 10,
                              observation_sequence_range: { first: 11, last: 110 })
    expect(report[:observations].length).to eq(100)
    expect(report[:observations].first).to include(sequence: 11, sends: 0, reserved_actions: 1, outcome: :skipped, room_id: 42, room_epoch: 3)
    expect(report[:observations].last).to include(sequence: 110, sends: 2, reserved_actions: 2, outcome: :sent)
    expect(report[:limits]).to eq(scope: :run, max_actions: 400, max_seconds: 1000.0, max_ineffective: 500)
    expect(report[:timing]).to include(clock: :monotonic, started_at: 100.0, deadline: 1100.0, ended_at: clock.first)
  end

  it 'retains unknown usage and dispatch exceptions without inventing zero sends' do
    allow(dispatch).to receive(:call).and_raise('fixture dispatch error')
    expect(controller.tick).to include(state: :held, observations_total: 1, sends: 0, sends_unverified: 1)
    expect(controller.status[:observations].first).to include(sends: nil, reserved_actions: 1, outcome: :unconfirmed, reason: 'dispatch_error')
  end

  it 'records invalid usage and over-budget results before holding' do
    allow(dispatch).to receive(:call).and_return(outcome: :sent, sends: nil)
    expect(controller.tick).to include(reason: 'dispatch_usage_unverified', observations_total: 1, sends_unverified: 1)
    controller.resume
    allow(dispatch).to receive(:call).and_return(outcome: :sent, sends: 500)
    expect(controller.tick).to include(reason: 'dispatch_budget_exceeded', observations_total: 2, sends: 500)
    expect(controller.status[:observations].last).to include(sends: 500, reserved_actions: 500, reason: 'dispatch_budget_exceeded')
  end

  it 'keeps configuration identity and terminal snapshots detached from callers and later time' do
    controller
    metadata[:preset].replace('changed')
    controller.tick
    controller.stop
    report = controller.status
    clock[0] += 10
    expect(controller.status).to eq(report)
    expect(report[:configuration]).to include(preset: 'invasion', profile: 'area', sequence: 'probe')
    expect { report[:configuration][:preset].replace('mutated') }.to raise_error(FrozenError)
    expect { report[:observations].first[:command].replace('mutated') }.to raise_error(FrozenError)
  end

  it 'does not label a watch run with a false global deadline' do
    settings['mode'] = 'watch'
    expect(controller.status[:timing][:deadline]).to be_nil
    expect(controller.status[:limits][:scope]).to eq(:target_visit)
    clock[0] = 150.0
    controller.tick
    expect(controller.status[:timing]).to include(started_at: 100.0, target_started_at: 150.0, deadline: 1150.0)
  end

  it 'retains dispatch identity even if controller room state changes before the result arrives' do
    settings['mode'] = 'watch'
    allow(dispatch).to receive(:call) do
      snapshot[:room_id] = 43
      snapshot[:room_epoch] = 4
      controller.synchronize_room(snapshot)
      { outcome: :interrupted, sends: 1, reason: 'room_id_changed' }
    end
    controller.tick
    expect(controller.status[:observations].first).to include(target_id: '123', room_id: 42, room_epoch: 3, sends: 1)
  end

  it 'retains resolved names without adding a new name length limit' do
    metadata[:preset] = 'a' * 400
    expect(controller.status[:configuration][:preset]).to eq('a' * 400)
  end

  it 'publishes reporting metadata through QuickRun without exposing mutable controller state' do
    run = namespace::QuickRun.new(engine: Object.new, policy: policy, owner: Object.new,
                                  snapshot: -> { snapshot }, resolve_target: ->(_id) { nil }, validate: ->(_command) { true },
                                  prefix: '>', trial: trial, report_metadata: metadata, clock: -> { clock.first })
    run.close
    final = Thread.new { run.status }.value
    metadata[:sequence].replace('changed')
    expect(final[:configuration][:sequence]).to eq('probe')
    expect(final).to be_frozen
    expect(final[:timing]).to be_frozen
    expect(final).to include(observations_total: 0, observations_dropped: 0, observation_sequence_range: { first: nil, last: nil })
  end
end
