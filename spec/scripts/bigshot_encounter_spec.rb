# Exercise the actual inactive foundation without loading the Lich runtime.
module BigshotEncounterSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  classes = source.scan(/^  class Encounter(?:Policy|Controller)\n.*?^  end$/m)
  raise 'could not extract encounter foundation' unless classes.length == 2

  module_eval(classes.join("\n"), __FILE__, __LINE__)
end

RSpec.describe BigshotEncounterSpec::EncounterController do
  let(:known) { { id: '1', name: 'giant rat', noun: 'rat', hostile: true } }
  let(:unknown) { { id: '2', name: 'strange invader', noun: 'invader', hostile: true } }
  let(:settings) do
    { 'mode' => 'clear', 'trigger' => 'leader', 'leader' => 'Friend',
      'targeting' => 'assist-only', 'unknown' => 'ignore',
      'fallback_commands' => 'jab target', 'max_actions' => 3,
      'max_seconds' => 20, 'max_ineffective' => 2 }
  end
  let(:snapshot) { { room_id: 100, room_epoch: 1, targets: [known], members: ['Friend'], safe: true } }
  let(:sent) { [] }
  let(:retreats) { [] }
  let(:clock_value) { [100.0] }
  let(:policy) { BigshotEncounterSpec::EncounterPolicy.new(settings, targets: { 'giant rat' => 'a' }, routines: { 'a' => ['attack target'] }, fallback: ['jab target']) }
  let(:dispatcher) { ->(**request) { sent << request; :sent } }

  def controller(trial: nil, retreat: nil)
    described_class.new(policy: policy, snapshot: -> { snapshot }, dispatch: dispatcher,
                        clock: -> { clock_value.first }, trial: trial, retreat: retreat)
  end

  def engage(session, target = '1', member = 'Friend', at = clock_value.first)
    session.observe_engagement(member: member, target_id: target, room_id: snapshot[:room_id], room_epoch: snapshot[:room_epoch], at: at)
  end

  it 'uses the profile routine and finishes clear when its target disappears' do
    session = controller
    session.tick
    expect(sent.first).to include(command: 'attack target', target_id: '1', room_id: 100, deadline: 120.0)
    snapshot[:targets] = []
    expect(session.tick).to include(state: :completed, reason: 'room_clear', actions: 1)
  end

  it 'leaves the saved settings and profile unchanged' do
    original = Marshal.load(Marshal.dump(settings))
    controller.tick
    expect(settings).to eq(original)
  end

  it 'delegates profile syntax admission and advances routines independently of actual sends' do
    settings['max_actions'] = 5
    routines = { 'a' => ['force unarmed jab until 2', 'unarmed grapple'] }
    profile = BigshotEncounterSpec::EncounterPolicy.new(settings, targets: { 'giant rat' => 'a' }, routines: routines)
    session = described_class.new(policy: profile, snapshot: -> { snapshot }, clock: -> { clock_value.first },
                                  validate: ->(command) { routines['a'].include?(command) },
                                  dispatch: ->(**request) { sent << request; { outcome: :sent, sends: 2 } })
    session.tick
    session.tick
    expect(sent.map { |request| request[:command] }).to eq(routines['a'])
    expect(sent.map { |request| request[:max_actions] }).to eq([5, 3])
    expect(session.status[:actions]).to eq(4)
  end

  it 'does not call the executor for a routine rejected by its validator' do
    session = described_class.new(policy: policy, snapshot: -> { snapshot }, dispatch: dispatcher, validate: ->(_) { false })
    expect(session.tick[:state]).to eq(:held)
    expect(sent).to be_empty
  end

  it 'does not declare a trial complete after one multi-send action' do
    settings.merge!('mode' => 'trial', 'max_actions' => 5)
    session = described_class.new(policy: policy, snapshot: -> { snapshot },
                                  trial: { target_id: '1', actions: ['jab target', 'grapple target'] },
                                  dispatch: ->(**request) { sent << request; { outcome: :sent, sends: 2 } })
    expect(session.tick[:state]).to eq(:running)
    expect(session.tick).to include(state: :completed, reason: 'sequence_dispatched', actions: 4)
    expect(sent.map { |request| request[:command] }).to eq(['jab target', 'grapple target'])
  end

  it 'holds on unverified or excessive transport usage instead of claiming completion' do
    [{ outcome: :sent }, { outcome: :sent, sends: 99 }].each do |result|
      session = described_class.new(policy: policy, snapshot: -> { snapshot }, dispatch: ->(**_) { result })
      expect(session.tick[:state]).to eq(:held)
    end
  end

  it 'records skipped commands without claiming sends and still bounds repeated attempts' do
    settings['max_actions'] = 2
    session = described_class.new(policy: policy, snapshot: -> { snapshot },
                                  dispatch: ->(**_) { { outcome: :skipped, sends: 0 } })
    expect(session.tick).to include(state: :running, actions: 1)
    expect(session.tick).to include(state: :running, actions: 2)
    expect(session.status[:observations].map { |event| event[:outcome] }).to eq([:skipped, :skipped])
    expect(session.tick).to include(state: :held, reason: 'action_limit')
  end

  it 'treats unknown hostile targets separately and never permits friendly NPCs' do
    settings['unknown'] = 'manual'
    snapshot[:targets] = [unknown, known.merge(id: '3', hostile: false)]
    session = controller
    expect(session.engage('3')).to be(false)
    expect(session.engage('2')).to be(true)
    session.tick
    expect(sent.map { |request| request[:command] }).to eq(['jab target'])
  end

  it 'keeps explicit exclusions, untargetable and boon ignores above engagement' do
    settings.merge!('mode' => 'assist', 'unknown' => 'group', 'excluded_creatures' => 'strange invader')
    snapshot[:targets] = [unknown, known.merge(untargetable: true), known.merge(id: '3', boon_ignored: true)]
    session = controller
    %w[1 2 3].each { |id| expect(engage(session, id)).to be(false) }
    session.tick
    expect(sent).to be_empty
  end

  it 'requires exact current member and target evidence and rejects stale or future evidence' do
    settings['mode'] = 'assist'
    session = controller
    expect(engage(session, '1', 'Stranger')).to be(false)
    expect(engage(session, 'giant rat')).to be(false)
    expect(engage(session, '1', 'Friend', 99)).to be(false)
    expect(engage(session, '1', 'Friend', 101)).to be(false)
    session.tick
    expect(sent).to be_empty
    expect(engage(session)).to be(true)
    session.tick
    expect(sent.size).to eq(1)
  end

  it 'allows any current member only when that trigger is selected' do
    settings.merge!('mode' => 'assist', 'trigger' => 'any-group')
    snapshot[:members] << 'Other'
    expect(engage(controller, '1', 'Other')).to be(true)
  end

  it 'does not turn group permission for one unknown into permission for every unknown' do
    settings.merge!('mode' => 'assist', 'unknown' => 'group', 'targeting' => 'assist-then-cleanup')
    snapshot[:targets] = [unknown, unknown.merge(id: '3')]
    session = controller
    engage(session, '2')
    session.tick
    snapshot[:targets].shift
    session.tick
    expect(sent.map { |request| request[:target_id] }).to eq(['2'])
  end

  it 'clears engagement on room changes and requires fresh permission after resume' do
    settings['mode'] = 'assist'
    session = controller
    engage(session)
    snapshot[:room_id] = 101
    session.tick
    expect(sent).to be_empty
    engage(session)
    session.hold
    session.resume
    session.tick
    expect(sent).to be_empty
  end

  it 'stops clear on movement but lets watch wait and use the new room' do
    session = controller
    session.tick
    snapshot[:room_id] = 101
    expect(session.tick).to include(state: :stopped, reason: 'room_changed')
    settings['mode'] = 'watch'
    watch_policy = BigshotEncounterSpec::EncounterPolicy.new(settings, targets: { 'giant rat' => 'a' }, routines: { 'a' => ['attack target'] })
    watch = described_class.new(policy: watch_policy, snapshot: -> { snapshot }, dispatch: dispatcher)
    snapshot[:targets] = []
    expect(watch.tick[:state]).to eq(:running)
    snapshot[:room_id] = 102
    snapshot[:targets] = [known]
    watch.tick
    expect(sent.last[:room_id]).to eq(102)
  end

  it 'continues safety monitoring while held and uses only the injected retreat' do
    settings['safety_action'] = 'retreat'
    session = controller(retreat: -> { retreats << :requested; :retreated })
    session.hold
    snapshot[:safe] = false
    expect(session.tick).to include(state: :stopped, reason: 'retreated')
    expect(retreats).to eq([:requested])
    expect(sent).to be_empty
    session.tick
    expect(retreats.size).to eq(1)
  end

  it 'holds if safety information or room identity is unavailable' do
    snapshot.delete(:safe)
    expect(controller.tick[:state]).to eq(:held)
    snapshot[:safe] = true
    snapshot[:room_id] = nil
    expect(controller.tick).to include(state: :held, reason: 'room_unknown')
    expect(sent).to be_empty
  end

  it 'enforces action and monotonic time limits before dispatch' do
    session = controller
    4.times { session.tick }
    expect(sent.size).to eq(3)
    expect(session.status[:reason]).to eq('action_limit')
    session.resume
    session.tick
    expect(sent.size).to eq(3)
    timed = controller
    timed.tick
    clock_value[0] = 121
    expect(timed.tick[:reason]).to eq('time_limit')
    expect(sent.size).to eq(4)
  end

  context 'with explicitly ineffective outcomes' do
    let(:dispatcher) { ->(**request) { sent << request; :ineffective } }

    it 'holds after the configured number of ineffective actions' do
      session = controller
      3.times { session.tick }
      expect(sent.size).to eq(2)
      expect(session.status[:reason]).to eq('ineffective_limit')
    end
  end

  it 'runs a trial only for its explicit target and never finishes combat afterward' do
    settings['mode'] = 'trial'
    snapshot[:targets] = [known, unknown]
    session = controller(trial: { target_id: '2', actions: ['jab target', 'grapple target'] })
    3.times { session.tick }
    expect(session.status).to include(state: :completed, reason: 'sequence_dispatched', actions: 2)
    expect(sent.map { |request| request[:target_id] }).to eq(%w[2 2])
  end

  it 'rejects nested routines, unbounded macros and command injection before dispatch' do
    settings['mode'] = 'trial'
    ['script attack', 'force attack target until 101', 'jab target and kill target', "jab target\nkill target", 'jab target;kill target'].each do |command|
      expect { controller(trial: { target_id: '1', actions: [command] }) }.to raise_error(ArgumentError)
    end
    expect(sent).to be_empty
  end

  it 'counts uncertain dispatches and holds rather than retrying' do
    uncertain = described_class.new(policy: policy, snapshot: -> { snapshot }, dispatch: ->(**_) { nil })
    expect(uncertain.tick).to include(state: :held, reason: 'dispatch_unconfirmed', actions: 1)
  end

  it 'invalidates engagement on a same-room revisit and rejects evidence from its old epoch' do
    settings['mode'] = 'assist'
    session = controller
    engage(session)
    snapshot[:room_epoch] = 2
    session.tick
    expect(sent).to be_empty
    expect(session.observe_engagement(member: 'Friend', target_id: '1', room_id: 100, room_epoch: 1, at: 100)).to be(false)
  end

  it 'assists the observed target before higher ranked cleanup targets' do
    settings.merge!('mode' => 'assist', 'unknown' => 'group', 'targeting' => 'assist-then-cleanup')
    snapshot[:targets] = [known, unknown]
    session = controller
    engage(session, '2')
    session.tick
    expect(sent.first[:target_id]).to eq('2')
  end

  it 'clears room cleanup permission when combat ends before later creatures spawn' do
    settings.merge!('mode' => 'assist', 'targeting' => 'assist-then-cleanup')
    session = controller
    engage(session)
    session.tick
    snapshot[:targets] = [known.merge(dead: true)]
    session.tick
    snapshot[:targets] = [known.merge(id: '3')]
    session.tick
    expect(sent.size).to eq(1)
  end

  it 'reports a vanished trial target as stopped and preserves explicit exclusions' do
    settings.merge!('mode' => 'trial', 'excluded_creatures' => 'giant rat')
    expect(controller(trial: { target_id: '1', actions: ['jab target'] }).tick).to include(state: :stopped, reason: 'target_unavailable')
    expect(sent).to be_empty
  end

  it 'holds ownership after an unconfirmed retreat and does not retry automatically' do
    settings['safety_action'] = 'retreat'
    snapshot[:safe] = false
    session = controller(retreat: -> { retreats << :attempt; nil })
    3.times { session.tick }
    expect(session.status).to include(state: :held, reason: 'retreat_unconfirmed')
    expect(retreats).to eq([:attempt])
    expect(sent).to be_empty
  end

  it 'copies trial commands and settings so caller edits cannot change an active run' do
    settings['mode'] = 'trial'
    actions = ['jab target']
    session = controller(trial: { target_id: '1', actions: actions })
    actions.first.replace('script invalid')
    settings['mode'].replace('watch')
    expect(session.tick).to include(state: :completed, mode: 'trial', reason: 'sequence_dispatched')
    expect(sent.first[:command]).to eq('jab target')
  end
end
