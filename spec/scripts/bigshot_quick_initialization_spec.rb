module BigshotQuickInitializationSpec
  SOURCE = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")

  def self.extract(pattern)
    SOURCE[pattern] || raise("could not extract #{pattern}")
  end

  class Harness
    class EncounterSettings; end
    class Group; end

    module UserVars
      class << self
        attr_accessor :op
      end
    end

    module CharSettings
      class << self
        attr_accessor :values

        def [](key)
          values[key]
        end

        def []=(key, value)
          values[key] = value
        end
      end
    end

    module Char
      def self.name
        'Tester'
      end
    end

    module Combat
      module Tracker
        class << self
          attr_accessor :enables

          def enabled?
            false
          end

          def enable!
            self.enables += 1
          end
        end
      end
    end

    module Lich
      module Util
        class << self
          attr_accessor :commands

          def quiet_command_xml(command, *)
            commands << command
          end
        end
      end

      module Gemstone
        module Experience
          def self.percent_fxp
            12
          end
        end
      end
    end

    class BSAreaRooms
      class << self
        attr_accessor :builds
      end

      def initialize(*); end

      def build
        self.class.builds += 1
      end
    end

    def name
      Char.name
    end

    def calls
      @calls ||= []
    end

    def load_settings
      { 'hunting_commands' => ['split_xx', []], 'targets' => ['targets', nil],
        'hunting_scripts' => ['split', []], 'hunting_room_id' => ['', 4],
        'hunting_boundaries' => ['split', []], 'oom' => ['to_i', 0] }
    end

    %i[check_required_values initialize_command_data initialize_boon_data convert_from_uid dead_man_switch].each do |method|
      define_method(method) { calls << method }
    end

    def check_mind
      calls << :check_mind
      12
    end

    def before_dying(&block)
      calls << :before_dying
      @cleanup = block
    end

    def debug_msg(*); end
    def echo(*); end
  end

  Harness::EncounterSettings.class_eval(extract(/^    def self.copy\(value\).*?^    end$/m))
  group_source = SOURCE[/^  class Group\n.*?(?=^  class )/m]
  %w[initialize set_leader leader_name size].each do |method|
    body = group_source[/^    def #{method}(?:\([^\n]*\))?\n.*?^    end$/m]
    raise "could not extract Group##{method}" unless body
    Harness::Group.class_eval(body)
  end
  Harness.class_eval(extract(/^  def initialize\(options = nil, group = nil, quick_profile: nil\).*?^  end$/m))
  Harness.class_eval(extract(/^  def set_value\(.*?^  end$/m))
  Harness.class_eval(extract(/^  def clean_value\(.*?^  end$/m))
end

RSpec.describe 'Bigshot detached Quick initialization' do
  subject(:harness_class) { BigshotQuickInitializationSpec::Harness }
  let(:profile) do
    { 'hunting_commands' => 'unarmed jab, 903(m20)(x2)', 'targets' => 'giant rat(b)',
      'hunting_scripts' => 'dangerous-script', 'boons_ignore' => ['frenzy'], 'oom' => '25' }
  end

  around do |example|
    saved = [$bigshot, $bigshot_quick, $bigshot_status, $bigshot_debug]
    $bigshot_quick, $bigshot_status, $bigshot_debug = false, :original, false
    harness_class::UserVars.op = { 'hunting_commands' => 'attack target', 'oom' => '10' }
    harness_class::CharSettings.values = { 'untargetable' => %w[statue statue], 'debug_file' => false }
    harness_class::Combat::Tracker.enables = 0
    harness_class::Lich::Util.commands = []
    harness_class::BSAreaRooms.builds = 0
    example.run
  ensure
    $bigshot, $bigshot_quick, $bigshot_status, $bigshot_debug = saved
  end

  it 'constructs the same combat engine with a detached profile and local solo group' do
    instance = harness_class.new(nil, nil, quick_profile: profile)
    expect(instance.calls).to eq(%i[initialize_command_data initialize_boon_data])
    expect(instance.instance_variable_get(:@HUNTING_COMMANDS)).to eq(['unarmed jab', '903(m20)', '903(m20)'])
    expect(instance.instance_variable_get(:@TARGETS)).to eq('giant rat' => 'b')
    expect(instance.instance_variable_get(:@OOM)).to eq(25)
    expect(instance.instance_variable_get(:@followers).size).to eq(1)
    expect(instance.instance_variable_get(:@group).leader_name).to eq('Tester')
    expect(instance.instance_variable_get(:@BANDIT_NOUN_REGEX)).to match('brigand')
    expect(instance.instance_variable_get(:@BLUNT_REGEX)).to match('battle hammer')
  end

  it 'does not persist caches, enable tracking, send group commands or install hunt cleanup' do
    harness_class::UserVars.op.freeze
    harness_class::CharSettings.values['debug_file'] = true
    harness_class::CharSettings.values.freeze
    instance = harness_class.new(['quick clear bounty'], nil, quick_profile: profile)
    expect(instance.calls).not_to include(:before_dying, :dead_man_switch, :check_required_values, :convert_from_uid, :check_mind)
    expect(harness_class::Lich::Util.commands).to be_empty
    expect(harness_class::Combat::Tracker.enables).to eq(0)
    expect(harness_class::BSAreaRooms.builds).to eq(0)
    expect(instance.instance_variable_get(:@DEBUG_FILE)).to be(false)
    expect(instance.instance_variable_get(:@BOUNTY_MODE)).to be_nil
    expect(harness_class::CharSettings.values['untargetable']).to eq(%w[statue statue])
  end

  it 'copies nested profile data and never replaces the selected saved profile' do
    saved = harness_class::UserVars.op
    instance = harness_class.new(quick_profile: profile)
    profile['boons_ignore'].first.replace('changed')
    profile['hunting_commands'].replace('changed')
    expect(instance.instance_variable_get(:@BOONS_IGNORE)).to eq(['frenzy'])
    expect(instance.instance_variable_get(:@quick_profile)['hunting_commands']).to start_with('unarmed jab')
    expect(harness_class::UserVars.op).to equal(saved)
  end

  it 'allows an empty detached profile to receive existing combat defaults' do
    instance = harness_class.new(quick_profile: {})
    expect(instance.instance_variable_get(:@OOM)).to eq(0)
    expect(instance.instance_variable_get(:@HUNTING_COMMANDS)).to eq([])
    expect(instance.calls).to eq(%i[initialize_command_data initialize_boon_data])
  end

  it 'rejects invalid detached input before changing the active engine' do
    previous = $bigshot
    expect { harness_class.new(quick_profile: []) }.to raise_error(ArgumentError, /mapping/)
    expect($bigshot).to equal(previous)
  end

  it 'preserves legacy initialization and normalizes its persistent target cache as before' do
    group = Struct.new(:leader_name).new('Leader')
    instance = harness_class.new(['solo'], group)
    expect(instance.calls).to eq(%i[check_required_values initialize_command_data initialize_boon_data convert_from_uid check_mind dead_man_switch before_dying])
    expect(harness_class::Lich::Util.commands).to eq(['group'])
    expect(harness_class::Combat::Tracker.enables).to eq(1)
    expect(harness_class::BSAreaRooms.builds).to eq(1)
    expect(harness_class::CharSettings.values['untargetable']).to eq(['statue'])
    expect(instance.instance_variable_get(:@OOM)).to eq(10)
    expect(instance.instance_variable_get(:@followers)).to be_nil
    expect(instance.instance_variable_get(:@leader)).to eq('Leader')
  end

  it 'lets set_value explicitly read a supplied profile without changing its default source' do
    instance = harness_class.new(quick_profile: profile)
    instance.set_value('oom', 'to_i', 0, { 'oom' => '75' })
    expect(instance.instance_variable_get(:@OOM)).to eq(75)
    instance.set_value('oom', 'to_i', 0)
    expect(instance.instance_variable_get(:@OOM)).to eq(25)
  end
end
