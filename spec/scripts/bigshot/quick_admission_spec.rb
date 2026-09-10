# Extended Quick must never accidentally execute the legacy Quick entry point.
module BigshotQuickAdmissionSpec
  SOURCE = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  GATE = SOURCE[/^# Quick Combat admission gate:.*?^# End Quick Combat admission gate\.$/m]
  raise 'Quick admission gate missing' unless GATE

  def self.run(*args, others: [])
    context = Module.new
    script = Struct.new(:vars).new([args.join(' '), *args])
    context.const_set(:Script, Class.new do
      define_singleton_method(:current) { script }
      define_singleton_method(:list) { [script, *others] }
    end)
    messages = []
    context.define_singleton_method(:echo) { |message| messages << message }
    context.define_singleton_method(:exit) { throw :stopped, :stopped }
    result = catch(:stopped) { context.module_eval(GATE + "\nquick_extended ? :extended : :legacy") }
    [result, messages]
  end
end

RSpec.describe 'Quick Combat admission gate' do
  it 'defers recognized extended verbs and flags to the strict parser' do
    %w[clear watch assist trial seek status hold resume stop retreat help engage --profile --preset].each do |command|
      expect(BigshotQuickAdmissionSpec.run('quick', command)).to eq([:extended, []])
    end
    expect(BigshotQuickAdmissionSpec.run('QUICK', 'CLEAR').first).to eq(:extended)
    expect(BigshotQuickAdmissionSpec.run('encounter', 'clear').first).to eq(:stopped)
  end

  it 'does not change normal hunting or historical permissive quick arguments' do
    [[], ['quick'], %w[quick once], %w[quick single], %w[quick bounty], %w[quick giant rat],
     %w[quick solo], %w[quick once bounty], %w[quick clera], ['solo'], ['setup'], ['help'], ['head'], ['tail']].each do |args|
      expect(BigshotQuickAdmissionSpec.run(*args)).to eq([:legacy, []])
    end
  end

  it 'protects an exact published Quick owner before legacy startup can reset globals' do
    active = Object.new
    active.define_singleton_method(:quick_combat_runtime) { Object.new }
    expect(BigshotQuickAdmissionSpec.run('quick', others: [active]).first).to eq(:stopped)
    expect(BigshotQuickAdmissionSpec.run('solo', others: [active]).first).to eq(:stopped)
    expect(BigshotQuickAdmissionSpec.run('quick', 'status', others: [active]).first).to eq(:extended)
    expect(BigshotQuickAdmissionSpec.run('quick', others: [Object.new])).to eq([:legacy, []])
  end

  it 'defers profile writes, directories and global initialization for extensions' do
    source = BigshotQuickAdmissionSpec::SOURCE
    position = source.index(BigshotQuickAdmissionSpec::GATE)
    expect(position).to be < source.index('if !quick_extended && UserVars')
    expect(position).to be < source.index('# Global Variables')
    expect(position).to be < source.index('bs = Bigshot.new')
    expect(source).to include('bigshot_initialize_globals unless quick_extended')
    expect(source).to include('"bigshot_profiles")) unless quick_extended')
    startup = source[/^# Extended Quick startup:.*?^# End extended Quick startup\.$/m]
    expect(startup).to include('QuickStartup.call', 'rescue StandardError', '  exit')
    expect(source.index(startup)).to be < source.index('bs = Bigshot.new')
  end
end
