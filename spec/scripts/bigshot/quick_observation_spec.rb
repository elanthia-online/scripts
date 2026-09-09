# frozen_string_literal: true

module BigshotQuickObservationSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  module_eval(source[/^  class EncounterPolicy\n.*?^  end$/m])
  class Harness
    attr_accessor :targets, :reason

    def initialize
      @targets = []
      @BOON_CACHE = {}
      @BOONS_IGNORE = []
      @TARGETS = { 'rat' => 'b' }
      @HUNTING_COMMANDS = ['jab target']
      @QUICK_COMMANDS = ['attack target']
    end

    def bs_targets = targets
    def creature_backed?(target) = !target.creature.nil?
    def dead_or_gone?(target) = target.status == 'dead'
    def quick_safety_reason(wounded:) = wounded ? 'wounded.' : reason
  end
  %w[clean_value quick_compile_commands quick_observation quick_routine_map quick_policy quick_wound_observation].each do |method|
    Harness.class_eval(source[/^  def #{method}\(.*?^  end$/m])
  end
end

RSpec.describe 'Bigshot fresh Quick observations' do
  let(:engine) { BigshotQuickObservationSpec::Harness.new }
  let(:owner) { Object.new }
  let(:group) { double('native group', checked?: true, _members: []) }
  let(:xml) { double('XMLData', room_count: 10, game: 'GS4') }
  let(:gameobj) { double('GameObj', pcs: [], npcs: [], loot: []) }
  let(:settings) { { 'untargetable' => [] } }

  before do
    stub_const('BigshotQuickObservationSpec::Harness::XMLData', xml)
    stub_const('BigshotQuickObservationSpec::Harness::Room', double(current: double(id: 12)))
    stub_const('BigshotQuickObservationSpec::Harness::GameObj', gameobj)
    stub_const('BigshotQuickObservationSpec::Harness::CharSettings', settings)
    stub_const('BigshotQuickObservationSpec::Harness::Script', double(list: [owner]))
    stub_const('BigshotQuickObservationSpec::Harness::Game', double(closed?: false))
    stub_const('BigshotQuickObservationSpec::Harness::Char', double(name: 'Tester'))
    stub_const('BigshotQuickObservationSpec::Harness::Lich::Gemstone::Group', group)
  end

  def observe
    engine.quick_observation(session: 'run1', owner: owner)
  end

  def target(id: '1', type: 'npc', native: true, status: nil)
    creature = native ? double(crtr_flag?: true) : nil
    Struct.new(:id, :name, :noun, :type, :creature, :status).new(id, 'rat', 'rat', type, creature, status)
  end

  it 'reads native hostility and exact IDs without issuing target or group probes' do
    engine.targets = [target, target(id: '2', native: false)]
    expect(observe).to include(session: 'run1:GS4:Tester', owner: true, connected: true, safe: true)
    expect(observe[:targets]).to include(include(id: '1', hostile: true), include(id: '2', hostile: false))
  end

  it 'observes corpses from GameObj rather than requiring a surviving Creature record' do
    allow(gameobj).to receive(:npcs).and_return([target(id: '51', native: false, status: 'dead'),
                                                 target(id: '52', status: 'dead', type: 'escort'), target(id: '53')])
    allow(gameobj).to receive(:loot).and_return([double(id: '61')])
    expect(observe).to include(corpses: [{ id: '51' }], loot_ids: ['61'])
  end

  it 'keeps only verified members also present with the same ID and name' do
    member = Struct.new(:id, :noun).new('-7', 'Friend')
    allow(group).to receive(:_members).and_return([member])
    allow(gameobj).to receive(:pcs).and_return([member])
    expect(observe).to include(members: ['Friend'], member_records: [{ id: '-7', name: 'Friend' }])
    allow(group).to receive(:checked?).and_return(false)
    expect(observe).to include(members_verified: false, members: [])
    allow(group).to receive(:checked?).and_return(true)
    allow(gameobj).to receive(:pcs).and_return([Struct.new(:id, :noun).new('-8', 'Friend')])
    expect(observe[:members]).to be_empty
  end

  it 'holds rather than using a mixed-room snapshot' do
    allow(xml).to receive(:room_count).and_return(10, 11)
    expect(observe).to include(safe: false, safety_reason: 'room changed during observation.')
  end

  it 'reports cached exclusions and holds when configured boon exclusion data is unknown' do
    engine.targets = [target(type: 'npc,boon')]
    engine.instance_variable_set(:@BOONS_IGNORE, ['frenzy'])
    expect(observe).to include(safe: false, safety_reason: 'boon check required.')
    engine.instance_variable_set(:@BOON_CACHE, '1' => ['frenzy'])
    settings['untargetable'] << 'rat'
    expect(observe[:targets].first).to include(boon_ignored: true, untargetable: true)
  end

  it 'reports disconnection and lost ownership separately from room content' do
    allow(BigshotQuickObservationSpec::Harness::Script).to receive(:list).and_return([])
    allow(BigshotQuickObservationSpec::Harness::Game).to receive(:closed?).and_return(true)
    expect(observe).to include(owner: false, connected: false)
  end

  it 'reuses parsed A-J fallback without changing target mappings or command arrays' do
    mapping = engine.instance_variable_get(:@TARGETS).dup
    policy = engine.quick_policy('mode' => 'clear')
    expect(policy.commands(name: 'rat', noun: 'rat')).to eq(['jab target'])
    expect(engine.instance_variable_get(:@TARGETS)).to eq(mapping)
    engine.instance_variable_set(:@HUNTING_COMMANDS_B, ['grapple target'])
    expect(engine.quick_policy('mode' => 'clear').commands(name: 'rat', noun: 'rat')).to eq(['grapple target'])
  end

  it 'returns a detached immutable routine map without freezing the hunting profile' do
    commands = [[+'jab target', +'grapple target']]
    engine.instance_variable_set(:@HUNTING_COMMANDS, commands)
    engine.instance_variable_set(:@HUNTING_COMMANDS_B, [])
    routines = engine.quick_routine_map
    expect(routines.keys).to contain_exactly('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'quick')
    expect(routines['b']).to eq(commands)
    expect(routines['quick']).to eq(['attack target'])
    expect { routines['b'].first.first.replace('kick target') }.to raise_error(FrozenError)
    expect { routines['a'] << 'kick target' }.to raise_error(FrozenError)
    commands.first.first.replace('punch target')
    expect(routines['a'].first.first).to eq('jab target')
    expect(engine.quick_routine_map['a'].first.first).to eq('punch target')
  end

  it 'evaluates existing wound expressions on the engine under an observation-only scope' do
    native_owner = double(execution_guard_active?: false)
    allow(BigshotQuickObservationSpec::Harness::Script).to receive(:current).and_return(native_owner)
    engine.instance_variable_set(:@WOUNDED_EVAL, '@reason == "injury"')
    expect(native_owner).to receive(:with_execution_guard) do |callback, &block|
      expect(callback.call(nil)).to be(true)
      expect(callback.call('attack')).to be(false)
      block.call
    end
    engine.reason = 'injury'
    expect(engine.quick_wound_observation(owner: native_owner)).to be(true)
  end

  it 'does not nest scopes during guarded reads or hide broken wound expressions' do
    native_owner = double(execution_guard_active?: true)
    allow(BigshotQuickObservationSpec::Harness::Script).to receive(:current).and_return(native_owner)
    engine.instance_variable_set(:@WOUNDED_EVAL, 'nil')
    expect { engine.quick_wound_observation(owner: native_owner) }.to raise_error(ArgumentError, /unrelated/)
    engine.instance_variable_set(:@quick_native_scope, true)
    expect(engine.quick_wound_observation(owner: native_owner)).to be(false)
    engine.instance_variable_set(:@WOUNDED_EVAL, 'raise "bad wound expression"')
    expect { engine.quick_wound_observation(owner: native_owner) }.to raise_error('bad wound expression')
  end
end
