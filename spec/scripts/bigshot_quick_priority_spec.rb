# frozen_string_literal: true

require_relative '../support/bigshot_quick_native_cmd_support'

module BigshotQuickPrioritySpec
  class Engine < BigshotQuickNativeCmdSpec::Engine
    CharSettings = { 'untargetable' => [] }.freeze
    source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
    %w[priority priority_rank priority_matchers].each do |name|
      class_eval(source[/^  def #{name}(?:\([^\n]*\))?\n.*?^  end$/m])
    end
  end
end

RSpec.describe 'Quick policy targeting through the native priority command gate' do
  let(:owner) { BigshotQuickNativeCmdSpec::Owner.new }
  let(:engine) { BigshotQuickPrioritySpec::Engine.new(owner) }
  let(:rat) { Struct.new(:id, :name, :noun).new('1', 'rat', 'rat') }
  let(:ogre) { Struct.new(:id, :name, :noun).new('2', 'ogre', 'ogre') }
  let(:settings) { { 'mode' => 'assist', 'trigger' => 'leader', 'leader' => 'Ally', 'targeting' => 'assist-only' } }
  let(:world) do
    { session: 'login', room_id: 42, room_epoch: 1, safe: true, owner: true, connected: true,
      members_verified: true, members: ['Ally'],
      targets: [rat, ogre].map { |npc| { id: npc.id, name: npc.name, noun: npc.noun, hostile: true, dead: false } } }
  end
  let(:patterns) { { 'rat' => 'a', 'ogre' => 'a' } }
  let(:run) do
    policy = BigshotQuickNativeCmdSpec::EncounterPolicy.new(settings, targets: patterns, routines: { 'a' => ['attack target'] }, fallback: ['attack target'])
    BigshotQuickNativeCmdSpec::QuickRun.new(
      engine: engine, policy: policy, owner: owner, snapshot: -> { world },
      resolve_target: ->(id) { [rat, ogre].find { |npc| npc.id == id } },
      validate: ->(command) { command == 'attack target' }, prefix: '>', clock: -> { 100.0 }
    )
  end

  before do
    BigshotQuickNativeCmdSpec::Script.current = owner
    BigshotQuickNativeCmdSpec::Spell.entries = { 1201 => BigshotQuickNativeCmdSpec::NativeSpell.new(1201, owner, known: false) }
    engine.instance_variable_set(:@PRIORITY, true)
    engine.instance_variable_set(:@TARGETS, patterns)
    %i[debug_msg check_for_deaders_prone escape_rooms waitrt? waitcastrt? change_stance].each { |method| allow(engine).to receive(method) }
    allow(engine).to receive(:bs_targets).and_return([rat, ogre])
    allow(engine).to receive(:invalid_target_with_boons).and_return(false)
    allow(engine).to receive(:dead_or_gone?).and_return(false)
    allow(engine).to receive(:still_targetable?).and_return(true)
    allow(engine).to receive(:valid_target?).and_return(true)
    allow(engine).to receive(:standing?).and_return(true)
    @saved_bandits = $bigshot_bandits
    $bigshot_bandits = false
  end

  after do
    BigshotQuickNativeCmdSpec::Script.current = nil
    BigshotQuickNativeCmdSpec::Spell.entries = nil
    $bigshot_bandits = @saved_bandits
  end

  it 'attacks an engaged lower-ranked target without choosing the unengaged priority creature' do
    expect(engine.priority(ogre)).to be(false)
    expect(run.observe_engagement(member: 'Ally', target_id: '2', room_id: 42, room_epoch: 1, at: 100.0)).to be(true)
    expect(run.tick).to include(state: :running, target_id: '2', actions: 1)
    expect(owner.wires).to eq(['>attack #2'])
  end

  it 'executes manually authorized unfamiliar fallback despite a higher-ranked known creature' do
    settings.merge!('unknown' => 'manual', 'fallback_commands' => 'attack target')
    patterns.delete('ogre')
    run.tick
    expect(run.request_engagement('2')[:accepted]).to be(true)
    expect(run.tick).to include(state: :running, target_id: '2', actions: 1)
    expect(owner.wires).to eq(['>attack #2'])
  end

  it 'preserves the legacy native command veto outside a Quick scope' do
    engine.cmd('attack target', ogre)
    expect(owner.wires).to be_empty
    expect(engine.priority(rat)).to be(true)
  end

  it 'cancels the native scope when the verified roster changes during an attack' do
    run.observe_engagement(member: 'Ally', target_id: '2', room_id: 42, room_epoch: 1, at: 100.0)
    owner.on_send = ->(_) { world[:members] = [] }
    expect(run.tick[:state]).to eq(:held)
    expect(owner.wires).to eq(['>attack #2'])
    expect(owner.execution_guard_active?).to be(false)
    run.tick
    expect(owner.wires).to eq(['>attack #2'])
  end

  it 'still rejects a different target from a nested native Quick priority check' do
    guard = double('active guard', checkpoint!: true)
    engine.instance_variable_set(:@quick_native_scope, true)
    engine.instance_variable_set(:@quick_guard, guard)
    engine.instance_variable_set(:@quick_target, ogre)
    expect(engine.priority(rat)).to be(false)
    expect(engine.priority(ogre)).to be(true)
    expect(guard).to have_received(:checkpoint!).twice
  end
end
