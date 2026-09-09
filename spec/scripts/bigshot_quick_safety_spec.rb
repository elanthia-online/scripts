module BigshotQuickSafetySpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  safety = source[/^  def quick_safety_reason\(.*?^  end$/m]
  safety += "\n" + source[/^  def quick_environment_reason\n.*?^  end$/m]
  raise 'could not extract quick_safety_reason' unless safety

  Creature = Struct.new(:id, :name, :noun, :type, :status)

  class Harness
    module Char
      class << self
        attr_accessor :percent_encumbrance, :percent_mana
      end
    end

    module GameObj
      class << self
        attr_accessor :loot, :npcs
      end
    end

    module CharSettings
      def self.[](_key)
        @untargetable ||= []
      end
    end

    module Effects
      module Debuffs
        class << self
          attr_accessor :values

          def to_h
            values
          end

          def active?(name)
            values.key?(name)
          end
        end
      end
    end

    attr_accessor :targets, :pcs, :is_dead

    def initialize
      @OOM, @ENCUMBERED, @FLEE_COUNT = 20, 101, 2
      @CREEPING_DREAD, @CRUSHING_DREAD = 0, 0
      @ALWAYS_FLEE_FROM, @INVALID_TARGETS, @BOONS_FLEE, @BOONS_IGNORE = [], [], [], []
      @BOON_CACHE = {}
      @targets, @pcs = [], []
      Char.percent_mana = 100
      Char.percent_encumbrance = 0
      GameObj.loot = []
      GameObj.npcs = []
      CharSettings['untargetable'].clear
      Effects::Debuffs.values = {}
    end

    def configure(**values)
      values.each { |key, value| instance_variable_set("@#{key.to_s.upcase}", value) }
    end

    def dead?
      @is_dead
    end

    def bs_targets
      @targets
    end

    def dead_or_gone?(npc)
      npc.status.to_s.match?(/dead|gone/)
    end

    def checkpcs
      @pcs
    end

    # Any accidental call into an action-bearing old safety path fails.
    def method_missing(name, *)
      raise "unexpected side effect or dependency: #{name}"
    end
  end

  Harness.class_eval(safety, __FILE__, __LINE__)
end

RSpec.describe 'Bigshot extended Quick pure safety' do
  let(:harness) { BigshotQuickSafetySpec::Harness.new }
  let(:rat) { BigshotQuickSafetySpec::Creature.new('1', 'giant rat', 'rat', 'aggressive npc', '') }

  around do |example|
    saved = [$bigshot_quick, $bigshot_flee, $bigshot_should_rest, $bigshot_bandits, $bigshot_status, $rest_reason]
    $bigshot_quick, $bigshot_flee, $bigshot_should_rest, $bigshot_bandits = true, false, false, false
    $bigshot_status, $rest_reason = :original, 'original'
    example.run
  ensure
    $bigshot_quick, $bigshot_flee, $bigshot_should_rest, $bigshot_bandits, $bigshot_status, $rest_reason = saved
  end

  it 'returns no reason when healthy even when Quick is active' do
    expect(harness.quick_safety_reason).to be_nil
    expect([$bigshot_status, $rest_reason]).to eq([:original, 'original'])
  end

  it 'honors death and existing flee/rest signals without changing status' do
    harness.is_dead = true
    expect(harness.quick_safety_reason).to eq('dead.')
    harness.is_dead = false
    $bigshot_flee = true
    expect(harness.quick_safety_reason).to eq('flee requested.')
    $bigshot_flee, $bigshot_should_rest = false, true
    expect(harness.quick_safety_reason).to eq('$bigshot_should_rest was set to true.')
    expect([$bigshot_status, $rest_reason]).to eq([:original, 'original'])
  end

  it 'never evaluates arbitrary wound Ruby and requires its boolean observation' do
    harness.configure(wounded_eval: "raise 'must never evaluate'", use_wracking: true)
    expect(harness.quick_safety_reason).to eq('wound check required.')
    expect(harness.quick_safety_reason(wounded: true)).to eq('wounded.')
    expect(harness.quick_safety_reason(wounded: false)).to be_nil
    expect(harness.quick_safety_reason(wounded: 'false')).to eq('invalid wound observation.')
  end

  it 'preserves strict mana comparison and the negative disabled sentinel without wracking' do
    harness.configure(use_wracking: true)
    BigshotQuickSafetySpec::Harness::Char.percent_mana = 20
    expect(harness.quick_safety_reason).to be_nil
    BigshotQuickSafetySpec::Harness::Char.percent_mana = 19
    expect(harness.quick_safety_reason).to eq('out of mana.')
    harness.configure(oom: -1)
    expect(harness.quick_safety_reason).to be_nil
  end

  it 'preserves the inclusive encumbrance threshold' do
    harness.configure(encumbered: 50)
    BigshotQuickSafetySpec::Harness::Char.percent_encumbrance = 50
    expect(harness.quick_safety_reason).to eq('encumbered.')
  end

  it 'uses greater-than swarm count and applies lone-target only on entry' do
    harness.targets = [rat, rat.dup]
    expect(harness.quick_safety_reason).to be_nil
    harness.configure(lone_targets_only: true)
    expect(harness.quick_safety_reason(true)).to eq('swarm limit.')
    harness.targets << rat.dup
    expect(harness.quick_safety_reason).to eq('swarm limit.')
  end

  it 'excludes swarm exceptions without changing the target collection' do
    harness.configure(flee_count: 0, invalid_targets: ['rat'])
    harness.targets = [rat]
    expect(harness.quick_safety_reason).to be_nil
    expect(harness.targets).to eq([rat])
    harness.configure(invalid_targets: [])
    BigshotQuickSafetySpec::Harness::CharSettings['untargetable'] << rat.name
    expect(harness.quick_safety_reason).to be_nil
  end

  it 'keeps named flee rules above swarm exceptions and creature registration' do
    harness.configure(invalid_targets: ['rat'], always_flee_from: ['rat'])
    BigshotQuickSafetySpec::Harness::GameObj.npcs = [rat]
    expect(harness.quick_safety_reason).to eq('always-flee creature present.')
    harness.configure(always_flee_from: ['Stranger'])
    harness.pcs = ['Stranger']
    expect(harness.quick_safety_reason).to eq('always-flee player present.')
  end

  it 'reads boon cache only and does not confuse ignore with flee' do
    rat.type = 'boon,aggressive npc'
    harness.targets = [rat]
    harness.configure(boons_flee: ['frenzy'], boons_ignore: ['frenzy'], invalid_targets: ['rat'])
    expect(harness.quick_safety_reason).to eq('boon check required.')
    harness.configure(boon_cache: { '1' => ['frenzy'] })
    expect(harness.quick_safety_reason).to eq('flee boon present.')
    harness.configure(boon_cache: { '1' => [] })
    expect(harness.quick_safety_reason).to be_nil
  end

  it 'still counts ignored boons for swarms as ordinary hunting does' do
    harness.targets = [rat]
    harness.configure(flee_count: 0, boons_ignore: ['frenzy'])
    expect(harness.quick_safety_reason).to eq('swarm limit.')
  end

  it 'preserves the bandit swarm exception but keeps environmental dangers' do
    harness.configure(flee_count: 0, flee_clouds: true)
    harness.targets = [rat]
    $bigshot_bandits = true
    expect(harness.quick_safety_reason).to be_nil
    BigshotQuickSafetySpec::Harness::GameObj.loot = [BigshotQuickSafetySpec::Creature.new('9', 'poison cloud', 'cloud')]
    expect(harness.quick_safety_reason).to eq('dangerous cloud.')
  end

  it 'reads existing debuff limits without calling action-bearing helpers' do
    harness.configure(creeping_dread: 3, confusion: true)
    BigshotQuickSafetySpec::Harness::Effects::Debuffs.values = { 'Creeping Dread (3)' => true }
    expect(harness.quick_safety_reason).to eq('creeping dread limit.')
    BigshotQuickSafetySpec::Harness::Effects::Debuffs.values = { 'Confused' => true }
    expect(harness.quick_safety_reason).to eq('confusion debuff.')
  end

  it 'holds for invalid numeric thresholds instead of silently disabling safety' do
    [nil, '20', Float::INFINITY, Float::NAN].each do |invalid|
      harness.configure(oom: invalid)
      expect(harness.quick_safety_reason).to eq('invalid safety thresholds.')
    end
    harness.configure(oom: 20, flee_count: -1)
    expect(harness.quick_safety_reason).to eq('invalid safety thresholds.')
  end
end
