# frozen_string_literal: true

module BigshotQuickGroupInvalidationSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[EncounterPolicy EncounterController].each do |name|
    body = source[/^  class #{name}\n.*?^  end$/m]
    raise "Missing #{name}" unless body

    module_eval(body)
  end
end

RSpec.describe 'Quick group verification invalidation' do
  let(:settings) do
    { 'mode' => 'assist', 'unknown' => 'ignore', 'targeting' => 'assist-then-cleanup',
      'trigger' => 'any-group', 'safety_action' => 'hold' }
  end
  let(:targets) do
    %w[100 101].map { |id| { id: id, name: 'ogre', noun: 'ogre', hostile: true, dead: false } }
  end
  let(:snapshot) do
    { room_id: 42, room_epoch: 1, safe: true, members_verified: true,
      members: ['Ally'], targets: targets }
  end
  let(:clock) { [10.0] }
  let(:sent) { [] }
  let(:retreats) { [] }
  let(:controller) do
    policy = BigshotQuickGroupInvalidationSpec::EncounterPolicy.new(
      settings, targets: { 'ogre' => 'a' }, routines: { 'a' => ['attack target'] }, fallback: ['attack target']
    )
    BigshotQuickGroupInvalidationSpec::EncounterController.new(
      policy: policy, snapshot: -> { snapshot }, clock: -> { clock[0] },
      dispatch: ->(**request) { sent << request; :sent },
      retreat: -> { retreats << true; :retreated }
    )
  end

  def engage(id = '100', at: clock[0])
    controller.observe_engagement(member: 'Ally', target_id: id, room_id: 42, room_epoch: 1, at: at)
  end

  it 'revokes active cleanup permission before the next owner tick can run' do
    expect(engage).to be(true)
    controller.tick
    targets.shift
    expect(controller.execution_authorized?('101', snapshot)).to be(true)
    snapshot[:members_verified] = false
    expect(controller.execution_authorized?('101', snapshot)).to be(false)
    expect(controller.tick).to include(state: :held, reason: 'group_membership_unverified')
    expect(sent.size).to eq(1)
  end

  it 'revokes engaged and cleanup targets immediately when the verified authorizing member leaves' do
    engage
    controller.tick
    expect(controller.execution_authorized?('101', snapshot)).to be(true)
    snapshot[:members] = []
    expect(snapshot[:members_verified]).to be(true)
    expect(controller.execution_authorized?('100', snapshot)).to be(false)
    expect(controller.execution_authorized?('101', snapshot)).to be(false)
    expect(controller.tick).to include(state: :running)
    expect(sent.size).to eq(1)
    snapshot[:members] = ['Ally']
    controller.tick
    expect(sent.size).to eq(1)
    expect(engage).to be(true)
    controller.tick
    expect(sent.size).to eq(2)
  end

  it 'rejects a same-name replacement through native member IDs before dispatch' do
    snapshot[:member_records] = [{ id: '1', name: 'Ally' }]
    engage
    controller.tick
    snapshot[:member_records] = [{ id: '2', name: 'Ally' }]
    expect(controller.execution_authorized?('100', snapshot)).to be(false)
    expect(controller.execution_authorized?('101', snapshot)).to be(false)
    controller.tick
    expect(sent.size).to eq(1)
  end

  it 'requires fresh engagement after any roster change but ignores roster ordering' do
    snapshot[:members] = %w[Ally Other]
    engage
    snapshot[:members].reverse!
    expect(controller.execution_authorized?('101', snapshot)).to be(true)
    snapshot[:members] << 'NewMember'
    expect(controller.execution_authorized?('101', snapshot)).to be(false)
    controller.tick
    expect(sent).to be_empty
    expect(engage).to be(true)
    controller.tick
    expect(sent.size).to eq(1)
  end

  it 'accepts the first fresh new-roster attack without requiring a second initiation' do
    snapshot[:member_records] = [{ id: '-1', name: 'Ally' }]
    engage
    controller.tick
    clock[0] = 11.0
    snapshot[:members] << 'NewMember'
    snapshot[:member_records] << { id: '-2', name: 'NewMember' }
    expect(controller.observe_engagement(member: 'Ally', target_id: '101', room_id: 42, room_epoch: 1,
                                         at: 10.9, member_roster: [['-1', 'Ally'], ['-2', 'NewMember']])).to be(true)
    expect(controller.execution_authorized?('101', snapshot)).to be(true)
    controller.tick
    expect(sent.map { |request| request[:target_id] }).to eq(%w[100 101])
  end

  it 'revokes unknown group fallback when the verified room roster changes' do
    settings.merge!('mode' => 'watch', 'unknown' => 'group', 'fallback_commands' => 'attack target')
    targets.each { |target| target[:name] = target[:noun] = 'unfamiliar invader' }
    engage
    controller.tick
    snapshot[:members] = []
    expect(controller.execution_authorized?('100', snapshot)).to be(false)
    controller.tick
    expect(sent.size).to eq(1)
  end

  it 'requires verified GROUP, explicit resume and fresh engagement after invalidation' do
    engage
    controller.tick
    targets.shift
    clock[0] += 1
    snapshot[:members_verified] = false
    controller.tick
    expect(engage('101')).to be(false)
    snapshot[:members_verified] = true
    expect(controller.tick).to include(state: :held, reason: 'group_membership_unverified')
    clock[0] += 1
    controller.resume
    controller.tick
    expect(sent.size).to eq(1)
    expect(engage('101', at: 10.0)).to be(false)
    expect(engage('101')).to be(true)
    controller.tick
    expect(sent.map { |request| request[:target_id] }).to eq(%w[100 101])
  end

  it 'does not allow resume to restore permission while membership is still unverified' do
    engage
    snapshot[:members_verified] = false
    controller.tick
    controller.resume
    expect(controller.tick).to include(state: :held, reason: 'group_membership_unverified')
    expect(sent).to be_empty
  end

  it 'also holds group-based unknown fallback in a non-assist mode' do
    settings.merge!('mode' => 'watch', 'unknown' => 'group')
    controller.tick
    snapshot[:members_verified] = false
    expect(controller.execution_authorized?('100', snapshot)).to be(false)
    expect(controller.tick).to include(state: :held, reason: 'group_membership_unverified')
    expect(sent.size).to eq(1)
  end

  it 'does not impose group verification on ordinary clear or watch policies' do
    settings.merge!('mode' => 'watch', 'unknown' => 'ignore')
    snapshot[:members_verified] = false
    expect(controller.tick).to include(state: :running)
    expect(sent.size).to eq(1)
    expect(controller.execution_authorized?('100', snapshot)).to be(true)
  end

  it 'preserves the older synthetic snapshot contract when verification is absent' do
    snapshot.delete(:members_verified)
    expect(engage).to be(true)
    controller.tick
    expect(sent.size).to eq(1)
  end

  it 'does not suppress a configured safety retreat when membership also becomes invalid' do
    settings['safety_action'] = 'retreat'
    engage
    snapshot.merge!(members_verified: false, safe: false, safety_reason: 'wounded')
    expect(controller.tick).to include(state: :stopped, reason: 'retreated')
    expect(retreats).to eq([true])
    expect(sent).to be_empty
  end
end
