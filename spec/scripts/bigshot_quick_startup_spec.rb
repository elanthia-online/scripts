# frozen_string_literal: true

require 'yaml'
require 'json'
require 'open3'
require 'rbconfig'

module BigshotQuickStartupSpec
  SOURCE = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[EncounterSettings QuickRequest EncounterPolicy EncounterController QuickGuard QuickLoot QuickSeek QuickRun QuickRetreat130 QuickRetreatWalk QuickGo2Travel QuickStartup].each do |name|
    body = SOURCE[/^  class #{name}\n.*?^  end$/m]
    raise "could not extract #{name}" unless body

    module_eval(body, __FILE__, __LINE__)
  end

  class Owner
    attr_accessor :name, :active, :stopping

    def initialize(name = 'bigshot')
      @name = name
    end

    def execution_guard_active?
      !!@active
    end

    def stopping?
      !!@stopping
    end

    def with_execution_guard(_callback, **)
      yield
    end

    def execution_sleep(_seconds); end
  end

  class Engine
    attr_accessor :feed_available, :outcome_available, :after_tick, :loop_error
    attr_reader :calls, :wounds, :loop_options, :run, :snapshot

    def initialize
      @TARGETS = { 'giant rat' => 'a' }
      @HUNTING_COMMANDS = ['force unarmed jab until 2 (m50)']
      @calls, @wounds = [], []
      @feed_available = true
      @outcome_available = true
      @snapshot = { session: 'login', room_id: 1, room_epoch: 1, owner: true, connected: true,
                    safe: true, members: [], corpses: [], loot_ids: [],
                    targets: [{ id: '123', name: 'giant rat', noun: 'rat', hostile: true }] }
    end

    def quick_wound_observation(owner:)
      @wounds << owner
      false
    end

    def quick_observation(session:, owner:, wounded:)
      @snapshot.merge(session: session, wounded: wounded, owner: !owner.nil?)
    end

    def quick_attack_observation_available?
      @feed_available
    end

    def quick_outcome_observation_available?
      @outcome_available
    end

    def bs_targets
      @snapshot[:targets].map { |target| Struct.new(:id).new(target[:id]) }
    end

    def quick_execute(command, target, guard:, owner:, prefix:)
      @calls << [command, target.id, prefix]
      owner.active = true
      guard.transmit("attack ##{target.id}") { true }
      { outcome: :sent, sends: guard.sends }
    ensure
      owner.active = false
    end

    def quick_run_loop(run, owner:, **options)
      raise 'missing owner' unless owner

      @run, @loop_options = run, options
      raise 'loop failed' if @loop_error

      result = nil
      4.times do |index|
        run.request('stop') if index == 3
        result = run.tick
        @after_tick.call(run, index) if @after_tick
        break if %i[completed stopped].include?(result[:state])

        @snapshot[:targets] = []
      end
      result
    end
  end
  %w[clean_value quick_compile_commands quick_routine_map quick_policy].each do |name|
    Engine.class_eval(SOURCE[/^  def #{name}\(.*?^  end$/m], __FILE__, __LINE__)
  end
end

RSpec.describe BigshotQuickStartupSpec::QuickStartup do
  let(:owner) { BigshotQuickStartupSpec::Owner.new }
  let(:engine) { BigshotQuickStartupSpec::Engine.new }
  let(:running) { [owner] }
  let(:resets) { [] }
  let(:messages) { [] }
  let(:stored) { nil }
  let(:profile) { { 'profile_current' => 'ordinary' } }
  let(:factory) { Class.new }

  before do
    @previous_bigshot_debug = $bigshot_debug
    script = Class.new
    stub_const('BigshotQuickStartupSpec::Script', script)
    allow(script).to receive(:current).and_return(owner)
    allow(script).to receive(:list) { running }
    stub_const('BigshotQuickStartupSpec::Bigshot', factory)
    allow(factory).to receive(:new).with(quick_profile: profile).and_return(engine)
    hooks = Class.new
    allow(hooks).to receive(:add)
    allow(hooks).to receive(:remove)
    stub_const('BigshotQuickStartupSpec::UpstreamHook', hooks)
    character = Class.new
    allow(character).to receive(:name).and_return('Tester')
    stub_const('BigshotQuickStartupSpec::Char', character)
  end

  after do
    $bigshot_debug = @previous_bigshot_debug
  end

  def start(*argv, **options)
    described_class.call(argv, reset: -> { resets << true }, output: ->(message) { messages << message },
                         owner: owner, prefix: '>', stored: -> { stored }, profile: -> { profile }, directory: -> { '/unused' }, **options)
  end

  it 'admits a refuge beyond the hunting boundary using the existing map travel graph' do
    map = Class.new
    stub_const('BigshotQuickStartupSpec::Map', map)
    ids = (100..132).to_a
    rooms = ids.to_h do |id|
      adjacent = [id - 1, id + 1] & ids
      [id, Struct.new(:wayto, :timeto).new(
        adjacent.to_h { |to| [to.to_s, to > id ? 'north' : 'south'] },
        adjacent.to_h { |to| [to.to_s, 0.2] }
      )]
    end
    allow(map).to receive(:[]) { |id| rooms[id.to_i] }
    allow(map).to receive(:dijkstra) do |origin, *_args, **_options|
      previous = ids.reject { |id| id == origin }.to_h { |id| [id, id > origin ? id - 1 : id + 1] }
      [previous, ids.to_h { |id| [id, (id - origin).abs * 0.2] }]
    end
    area = double(area_rooms: [132], start_room: 132)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect do
      described_class.refuge_setup({ room_id: 100, return_deadline: now + 150 },
                                   window: { work_deadline: now + 100, cleanup_deadline: now + 110 },
                                   area: area, owner: owner, prefix: '>', engine: engine)
    end.not_to raise_error
    expect(area.area_rooms).to eq([132])
    expect(engine.calls).to be_empty
  end

  it 'admits an outbound route and directed return from every pinned area room before launching' do
    area = double(area_rooms: [200, 300], start_room: 200)
    outbound = double(admit_route!: true)
    homeward = double(admit_route!: true)
    adapter = BigshotQuickStartupSpec::QuickGo2Travel
    allow(adapter).to receive(:new).and_return(outbound, homeward)
    result = described_class.refuge_setup({ room_id: 100, return_deadline: 150.0 },
                                          window: { work_deadline: 120.0, cleanup_deadline: 130.0 },
                                          area: area, owner: owner, prefix: '>', engine: engine)
    expect(outbound).to have_received(:admit_route!).with(100).once
    [100, 200, 300].each { |room| expect(homeward).to have_received(:admit_route!).with(room).once }
    expect(result[:return_walk]).to equal(homeward)
    expect(engine.calls).to be_empty
  end

  it 'refuses the outing when any reachable work room has no admitted return route' do
    area = double(area_rooms: [200, 300], start_room: 200)
    outbound = double(admit_route!: true)
    homeward = double(admit_route!: true)
    allow(homeward).to receive(:admit_route!).with(300).and_raise(ArgumentError, 'one-way edge')
    allow(BigshotQuickStartupSpec::QuickGo2Travel).to receive(:new).and_return(outbound, homeward)
    expect do
      described_class.refuge_setup({ room_id: 100, return_deadline: 150.0 },
                                   window: { work_deadline: 120.0, cleanup_deadline: 130.0 },
                                   area: area, owner: owner, prefix: '>', engine: engine)
    end.to raise_error(ArgumentError, /one-way/)
    expect(owner).not_to respond_to(:quick_combat_runtime)
    expect(engine.calls).to be_empty
  end

  it 'handles help and idle controls without reading any profile or resetting globals' do
    %w[help status hold resume stop retreat].each do |command|
      start(command, stored: -> { raise 'settings read' }, profile: -> { raise 'profile read' }, directory: -> { raise 'path read' })
    end
    expect(resets).to be_empty
    expect(factory).not_to have_received(:new)
    expect(messages.first).to include('quick clear|watch|assist')
    expect(messages.last).to include('No active Quick Combat run')
  end

  it 'resolves opted-in profile area before engine creation or any reset' do
    area_class = Class.new
    stub_const('BigshotQuickStartupSpec::Bigshot::BSAreaRooms', area_class)
    allow(area_class).to receive(:for_quick).with(profile, owner: owner).and_raise(ArgumentError, 'bad area')
    expect { start('watch', '--area', 'profile') }.to raise_error(ArgumentError, 'bad area')
    expect(factory).not_to have_received(:new)
    expect(resets).to be_empty
    expect(engine.calls).to be_empty
  end

  it 'rejects an outside-area start before any group query, runtime publication or combat' do
    area_class = Class.new
    stub_const('BigshotQuickStartupSpec::Bigshot::BSAreaRooms', area_class)
    area = double('area', valid?: false)
    allow(area_class).to receive(:for_quick).with(profile, owner: owner).and_return(area)
    expect { start('watch', '--area', 'profile') }.to raise_error(ArgumentError, /start inside/)
    expect(engine.calls).to be_empty
    expect(owner).not_to respond_to(:quick_combat_runtime)
  end

  it 'passes the admitted area to the exact runtime and retained completion report' do
    area_class = Class.new
    stub_const('BigshotQuickStartupSpec::Bigshot::BSAreaRooms', area_class)
    proof = { kind: :profile, start_room_id: 1, boundary_room_ids: [3], room_count: 2, room_id: 1, in_bounds: true }.freeze
    area = double('area', valid?: true, quick_status: proof)
    allow(area_class).to receive(:for_quick).with(profile, owner: owner).and_return(area)
    expect(start('clear', '--area', 'profile')).to include(state: :completed, area: proof)
    expect(owner.quick_combat_result[:area]).to eq(proof)
    expect(engine.calls.size).to eq(1)
  end

  it 'requires explicit profile-area authority for seek before building the engine' do
    expect { start('seek') }.to raise_error(ArgumentError, /seek requires --area profile/)
    expect(factory).not_to have_received(:new)
    expect(resets).to be_empty
  end

  it 'publishes a seek run and immediately clears an eligible starting encounter without movement' do
    area_class = Class.new
    stub_const('BigshotQuickStartupSpec::Bigshot::BSAreaRooms', area_class)
    proof = { kind: :profile, start_room_id: 1, boundary_room_ids: [3], room_count: 2, room_id: 1, in_bounds: true }.freeze
    area = double('area', valid?: true, quick_status: proof)
    allow(area_class).to receive(:for_quick).with(profile, owner: owner).and_return(area)
    expect(start('seek', '--area', 'profile')).to include(state: :completed, mode: 'seek', area: proof)
    expect(owner.quick_combat_result[:search]).to include(steps: 0, sends: 0)
  end

  it 'rejects malformed arguments before settings reads or resets' do
    [%w[clera], %w[clear --typo x], %w[status extra], %w[once extra]].each do |argv|
      expect { start(*argv, stored: -> { raise 'settings read' }) }.to raise_error(ArgumentError)
    end
    expect(resets).to be_empty
    expect(factory).not_to have_received(:new)
  end

  it 'admits ownership before any settings reads and shared resets' do
    running << BigshotQuickStartupSpec::Owner.new('bigshot-testing')
    expect { start('clear', stored: -> { raise 'settings read' }) }.to raise_error(ArgumentError, /exclusive ownership/)
    expect(resets).to be_empty
  end

  it 'rejects missing owner, foreign current script, and an existing native scope' do
    running.clear
    expect { start('clear') }.to raise_error(ArgumentError, /exclusive ownership/)
    running << owner
    allow(BigshotQuickStartupSpec::Script).to receive(:current).and_return(Object.new)
    expect { start('clear') }.to raise_error(ArgumentError, /exclusive ownership/)
    allow(BigshotQuickStartupSpec::Script).to receive(:current).and_return(owner)
    owner.active = true
    expect { start('clear') }.to raise_error(ArgumentError, /active execution scope/)
    expect(resets).to be_empty
  end

  it 'requires native cancellation support before settings reads or reset' do
    owner = Struct.new(:name).new('bigshot')
    owner.define_singleton_method(:stopping?) { false }
    allow(BigshotQuickStartupSpec::Script).to receive(:current).and_return(owner)
    running.replace([owner])
    expect { start('clear', owner: owner) }.to raise_error(ArgumentError, /companion Lich/)
    expect(resets).to be_empty
  end

  it 'rechecks ownership after resolution and before resets' do
    reader = lambda do
      running << BigshotQuickStartupSpec::Owner.new('bigshot-copy')
      profile
    end
    expect { start('clear', profile: reader) }.to raise_error(ArgumentError, /exclusive ownership/)
    expect(resets).to be_empty
  end

  it 'refuses a stopping native owner before resetting globals or dispatching' do
    owner.stopping = true
    expect { start('clear') }.to raise_error(ArgumentError, /exclusive ownership/)
    expect(resets).to be_empty
    expect(factory).not_to have_received(:new)
    expect(engine.calls).to be_empty
  end

  it 'runs detached clear through the real controller and original engine syntax' do
    before = Marshal.dump(profile)
    expect(start('clear')).to include(state: :completed, reason: 'room_clear', actions: 1)
    expect(resets).to eq([true])
    expect(factory).to have_received(:new).with(quick_profile: profile)
    expect(engine.calls).to eq([['force unarmed jab until 2 (m50)', '123', '>']])
    expect(Marshal.dump(profile)).to eq(before)
    expect(engine.run.request('resume')).to include(accepted: false, reason: 'run_closed')
  end

  it 'revokes future dispatch when another Bigshot appears during the run' do
    engine.after_tick = lambda do |run, index|
      running << BigshotQuickStartupSpec::Owner.new('bigshot-other') if index.zero?
      run.request('resume') if index == 1
    end
    result = start('watch')
    expect(result[:state]).to eq(:stopped)
    expect(engine.calls.length).to eq(1)
  end

  it 'closes the actual run when the attached loop raises' do
    engine.loop_error = true
    expect { start('clear') }.to raise_error('loop failed')
    expect(engine.run.status).to include(state: :stopped, reason: 'execution_error', actions: 0)
    expect(engine.run.request('resume')).to include(accepted: false, reason: 'run_closed')
    expect(owner).not_to respond_to(:quick_combat_runtime)
    expect(owner.quick_combat_result).to eq(engine.run.status)
    expect(owner.quick_combat_result).to be_frozen
  end

  it 'retains accepted send accounting and the original exception after an unexpected loop failure' do
    original_error = RuntimeError.new('opaque adapter failure')
    engine.after_tick = ->(_run, _index) { raise original_error }
    expect { start('clear') }.to(raise_error { |error| expect(error).to equal(original_error) })
    expect(engine.run.status).to include(state: :stopped, reason: 'execution_error', actions: 1)
    expect(owner.quick_combat_result).to eq(engine.run.status)
    expect(owner.quick_combat_result[:observations]).to be_frozen
    expect(owner.quick_combat_result.to_s).not_to include('opaque adapter failure', 'manual_stop', 'retreated')
    expect(owner).not_to respond_to(:quick_combat_runtime)
    expect(engine.run.request('resume')).to include(accepted: false, reason: 'run_closed')
  end

  it 'publishes only this exact owner runtime for the duration of the owner loop' do
    snapshots = []
    engine.after_tick = ->(run, _index) { snapshots << owner.quick_combat_runtime.equal?(run) }
    expect(owner).not_to respond_to(:quick_combat_runtime)
    start('clear')
    expect(owner.quick_combat_result).to include(state: :completed, reason: 'room_clear', actions: 1)
    expect(owner.quick_combat_result).to be_frozen
    expect(owner.quick_combat_result[:observations]).to be_frozen
    expect { owner.quick_combat_result[:state] = :running }.to raise_error(FrozenError)
    expect(snapshots).to eq([true, true])
    expect(owner).not_to respond_to(:quick_combat_runtime)
  end

  it 'retains the same immutable failure on the exact native Script object without a live runtime handle' do
    skip 'Set LICH_EXECUTION_GUARD_ROOT to run the native Script result contract' unless ENV['LICH_EXECUTION_GUARD_ROOT']

    probe = <<~'RUBY'
      require 'json'
      LIB_DIR = File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib')
      $LOAD_PATH.unshift(LIB_DIR)
      require 'common/script'
      # Reuse this spec's source-extracted production classes and engine fixture
      # in an isolated process, without loading native constants into RSpec.
      fixture = File.read(ARGV.fetch(0)).split(/^RSpec.describe/).first
      eval(fixture, TOPLEVEL_BINDING, ARGV.fetch(0), 1)
      namespace = BigshotQuickStartupSpec
      native = Lich::Common::Script
      owner = native.allocate
      owner.instance_variable_set(:@name, 'bigshot')
      native.define_singleton_method(:current) { owner }
      native.define_singleton_method(:list) { [owner] }
      namespace.const_set(:Script, native)
      hooks = Module.new
      hooks.define_singleton_method(:add) { |*| }
      hooks.define_singleton_method(:remove) { |*| }
      namespace.const_set(:UpstreamHook, hooks)
      character = Module.new
      character.define_singleton_method(:name) { 'Probe' }
      namespace.const_set(:Char, character)
      engine = namespace::Engine.new
      engine.loop_error = true
      factory = Class.new
      factory.define_singleton_method(:new) { |**| engine }
      namespace.const_set(:Bigshot, factory)
      begin
        namespace::QuickStartup.call(['clear'], owner: owner, prefix: '>', reset: -> {}, output: ->(_) {},
                                     stored: -> {}, profile: -> { {} }, directory: -> { '/unused' })
      rescue StandardError => error
        caught = error.message
      end
      result = owner.quick_combat_result
      puts JSON.generate(native_owner: owner.instance_of?(native), reason: result[:reason], state: result[:state],
                         same_status: result == engine.run.status, immutable: result.frozen? && result[:observations].frozen?,
                         runtime_published: owner.respond_to?(:quick_combat_runtime), caught: caught)
    RUBY
    output, error, status = Open3.capture3(RbConfig.ruby, '-', __FILE__, stdin_data: probe)
    expect(status.success?).to be(true), error
    expect(JSON.parse(output)).to eq('native_owner' => true, 'reason' => 'execution_error', 'state' => 'stopped',
                                     'same_status' => true, 'immutable' => true, 'runtime_published' => false, 'caught' => 'loop failed')
  end

  it 'rejects a preexisting runtime publication instead of overwriting it' do
    existing = Object.new
    owner.define_singleton_method(:quick_combat_runtime) { existing }
    expect { start('clear') }.to raise_error(ArgumentError, /already published/)
    expect(resets).to be_empty
    expect(owner.quick_combat_runtime).to equal(existing)
  end

  it 'rejects a preexisting terminal result getter before resetting globals' do
    owner.define_singleton_method(:quick_combat_result) { :existing }
    expect { start('clear') }.to raise_error(ArgumentError, /result is already published/)
    expect(resets).to be_empty
    expect(owner.quick_combat_result).to eq(:existing)
  end

  it 'does not remove a replacement method installed by another owner of that method' do
    replacement = Object.new
    engine.after_tick = lambda do |_run, _index|
      owner.define_singleton_method(:quick_combat_runtime) { replacement }
    end
    start('clear')
    expect(owner.quick_combat_runtime).to equal(replacement)
    expect(engine.run.status[:state]).to eq(:completed)
  end

  it 'executes the real bottom dispatch and exits instead of falling through on errors' do
    startup = BigshotQuickStartupSpec::SOURCE[/^# Extended Quick startup:.*?^# End extended Quick startup\.$/m]
    script = Struct.new(:vars).new(['quick clera', 'quick', 'clera'])
    context = Module.new
    context.const_set(:Script, Class.new { define_singleton_method(:current) { script } })
    context.const_set(:Bigshot, Class.new)
    context.const_get(:Bigshot).const_set(:QuickStartup, described_class)
    output = []
    context.define_singleton_method(:echo) { |message| output << message }
    context.define_singleton_method(:bigshot_initialize_globals) { raise 'unexpected reset' }
    context.define_singleton_method(:exit) { throw :quick_exit, :exited }
    result = catch(:quick_exit) { context.module_eval("quick_extended = true\n" + startup); :fell_through }
    expect(result).to eq(:exited)
    expect(output).to eq(['Quick Combat did not finish: Unknown quick command: clera'])
  end

  it 'keeps trusted profile syntax but rejects explicit unsupported paths at admission' do
    ['901', '302 channel', 'incant 901', 'incant901', 'incant 901 closed', 'incant 1700 evoke cold', 'force unarmed jab until 2 (m50)', 'celerity fire', ['unarmed jab', 'unarmed punch (tier3)']].each do |command|
      expect(described_class.command_supported!(command)).to be(true)
    end
    ['script go2', 'force script child until 2 (m50)', '506 eachtarget attack target', 'north', 'go arch',
     'mstrike', 'berserk', 'incant', 'incant fire', 'incant 901 Fred', 'incant 901 #123', 'incant901open', 'incant 901 open', '302open', 'resonance 901 open', 'efury lightning', 'tether recast', 'leech target',
     '130', '130target', '930', '1020', '9720', '9825', 'caststop 130', 'symbol of return', 'sigil of escape',
     '302 open', 'attack Fred', 'attack #123', "attack target\nlook"].each do |command|
      expect { described_class.command_supported!(command) }.to raise_error(ArgumentError)
    end
  end

  it 'rejects unsupported configured routines before entering the loop' do
    engine.instance_variable_set(:@HUNTING_COMMANDS, ['eachtarget attack target'])
    expect { start('clear') }.to raise_error(ArgumentError, /unscoped loot/)
    expect(engine.run).to be_nil
    expect(engine.calls).to be_empty
  end

  it 'rejects leading-zero travel spell IDs using the same numeric conversion as native dispatch' do
    %w[130 930 1020 9720 9825].each do |id|
      ["00#{id}", "00#{id}target", "incant 00#{id}", "incant00#{id}", "caststop 00#{id}"].each do |command|
        [command, "force #{command} until 2 (m50)", "506 #{command}", "celerity force #{command} until 2"].each do |wrapped|
          expect { described_class.command_supported!(wrapped) }.to raise_error(ArgumentError, /Travel spells/)
        end
      end
    end
    ['00901', 'incant00901', 'incant 00901', 'caststop 00901', '506 incant00901'].each do |command|
      expect(described_class.command_supported!(command)).to be(true)
    end
  end

  it 'refuses a padded travel command in a configured native routine before executing any command' do
    engine.instance_variable_set(:@HUNTING_COMMANDS, ['901', 'force incant00130 until 2'])
    expect { start('clear') }.to raise_error(ArgumentError, /Travel spells/)
    expect(engine.run).to be_nil
    expect(engine.calls).to be_empty
  end

  [true, false].each do |enabled|
    it "restores saved debugging #{enabled ? 'on' : 'off'} after admitted global initialization" do
      engine.instance_variable_set(:@DEBUG_COMMANDS, enabled)
      $bigshot_debug = !enabled
      start('clear', reset: -> { resets << true; $bigshot_debug = false })
      expect(resets).to eq([true])
      expect($bigshot_debug).to be(enabled)
    end
  end

  it 'admits the same shared routine map used by policy, including A fallback and legacy quick' do
    settings = BigshotQuickStartupSpec::EncounterSettings::DEFAULTS
    engine.instance_variable_set(:@HUNTING_COMMANDS, ['jab target'])
    engine.instance_variable_set(:@QUICK_COMMANDS, ['grapple target'])
    [['b', ['punch target']], ['b', []], ['b', nil], ['quick', nil]].each do |routine, commands|
      engine.instance_variable_set(:@TARGETS, 'giant rat' => routine)
      engine.instance_variable_set(:@HUNTING_COMMANDS_B, commands)
      admitted = []
      allow(described_class).to receive(:command_supported!).and_wrap_original do |original, command|
        admitted << command
        original.call(command)
      end
      described_class.admit_routines!(engine, settings, nil)
      expect(admitted).to eq(engine.quick_policy(settings).commands(name: 'giant rat', noun: 'rat'))
      expect(engine.instance_variable_get(:@HUNTING_COMMANDS_B)).to equal(commands)
    end
  end

  it 'rejects explicit warrior all sweeps while preserving targeted cries' do
    ['bellow all', 'growl all', 'cry all', 'warcry bellow all', 'force growl all until 2 (m50)'].each do |command|
      expect { described_class.command_supported!(command) }.to raise_error(ArgumentError, /room-wide warrior/)
    end
    %w[bellow growl cry].each do |command|
      expect(described_class.command_supported!(command)).to be(true)
    end
  end

  it 'compiles detached trial editor lines with the native profile cleaner before publishing the runtime' do
    state = { 'trials' => { 'probe' => { 'actions' => ['attack target and jab target', 'grapple target(x2)'] } } }
    original = Marshal.load(Marshal.dump(state))
    start('trial', 'probe', '--target', '123', stored: -> { state })
    expect(engine.run.status[:configuration]).to include(profile: 'ordinary', sequence: 'probe')
    expect(engine.calls.first.first).to eq(['attack target', 'jab target'])
    expect(engine.calls.first.first).to be_frozen
    expect(state).to eq(original)
    expect(state['trials']['probe']['actions']).not_to be_frozen
  end

  it 'rejects unsupported expanded trial and fallback leaves before any shared reset or publication' do
    state = { 'trials' => { 'probe' => { 'actions' => ['attack target and incant00130(x2)'] } } }
    expect { start('trial', 'probe', '--target', '123', stored: -> { state }) }.to raise_error(ArgumentError, /Travel spells/)
    state = { 'presets' => { 'default' => { 'fallback_commands' => 'attack target and script child(xx)' } } }
    expect { start('clear', stored: -> { state }) }.to raise_error(ArgumentError, /child scripts/)
    expect(resets).to be_empty
    expect(engine.calls).to be_empty
    expect(owner.respond_to?(:quick_combat_runtime)).to be(false)
  end

  it 'admits single-target UAC under either saved do-not-mstrike flag without admitting explicit mstrike' do
    [false, true].each do |disable_mstrike|
      engine.instance_variable_set(:@UAC_MSTRIKE, disable_mstrike)
      engine.instance_variable_set(:@HUNTING_COMMANDS, ['unarmed jab'])
      expect { described_class.admit_routines!(engine, BigshotQuickStartupSpec::EncounterSettings::DEFAULTS, nil) }.not_to raise_error
    end
    engine.instance_variable_set(:@HUNTING_COMMANDS, ['mstrike punch'])
    expect { described_class.admit_routines!(engine, BigshotQuickStartupSpec::EncounterSettings::DEFAULTS, nil) }.to raise_error(ArgumentError, /room-wide/)
  end

  it 'rejects configured retreat or external loot scripts explicitly' do
    base = BigshotQuickStartupSpec::EncounterSettings::DEFAULTS
    expect { described_class.admit_configuration!(base.merge('safety_action' => 'retreat'), {}) }.to raise_error(ArgumentError, /escape adapter/)
    expect { described_class.admit_configuration!(base.merge('loot' => 'room'), 'loot_script' => 'sloot') }.to raise_error(ArgumentError, /loot_script/)
    ['', 'eloot', ' ELoot '].each do |script|
      expect { described_class.admit_configuration!(base.merge('loot' => 'room'), 'loot_script' => script) }.not_to raise_error
    end
    ['eloot sell', 'eloot --load-room-api', 'script eloot', 'eloot;go2 42'].each do |script|
      expect { described_class.admit_configuration!(base.merge('loot' => 'room'), 'loot_script' => script) }.to raise_error(ArgumentError, /loot_script/)
    end
  end

  it 'attaches explicitly configured 130 with resolved destinations and leaves profile settings unchanged' do
    state = { 'presets' => { 'default' => { 'retreat_command' => '130', 'retreat_destinations' => '200' } } }
    map = double('map')
    allow(map).to receive(:[]).with(200).and_return(Object.new)
    stub_const('BigshotQuickStartupSpec::Map', map)
    spells = double('spells')
    allow(spells).to receive(:[]).with(130).and_return(Object.new)
    stub_const('BigshotQuickStartupSpec::Spell', spells)
    expect(start('clear', stored: -> { state })).to include(state: :completed)
    expect(engine.run.instance_variable_get(:@retreat)).to be_a(BigshotQuickStartupSpec::QuickRetreat130)
    expect(state['presets']['default']).to eq('retreat_command' => '130', 'retreat_destinations' => '200')
  end

  it 'rejects unresolved 130 destinations before any global resets' do
    state = { 'presets' => { 'default' => { 'retreat_command' => '130', 'retreat_destinations' => 'u999' } } }
    stub_const('BigshotQuickStartupSpec::Map', double(ids_from_uid: []))
    expect { start('clear', stored: -> { state }) }.to raise_error(ArgumentError, /unknown or ambiguous/)
    expect(resets).to be_empty
    expect(factory).not_to have_received(:new)
  end

  it 'attaches walking retreat to native movement without requiring a spell or changing profiles' do
    state = { 'presets' => { 'default' => { 'retreat_command' => 'walk', 'retreat_destinations' => '200' } } }
    map = double('map')
    allow(map).to receive(:[]).with(200).and_return(Object.new)
    stub_const('BigshotQuickStartupSpec::Map', map)
    spells = double('spells')
    expect(spells).not_to receive(:[])
    stub_const('BigshotQuickStartupSpec::Spell', spells)
    expect(start('clear', stored: -> { state })).to include(state: :completed)
    adapter = engine.run.instance_variable_get(:@retreat)
    expect(adapter).to be_a(BigshotQuickStartupSpec::QuickRetreatWalk)
    expect(engine).to receive(:move).with('north').and_return(true)
    expect(adapter.instance_variable_get(:@movement).call('north')).to be(true)
    expect(state['presets']['default']).to eq('retreat_command' => 'walk', 'retreat_destinations' => '200')
  end

  context 'group engagement startup' do
    let(:group_initialization) { double('owner group initialization', call: true) }
    let(:stored) do
      { 'presets' => { 'default' => { 'mode' => 'assist', 'trigger' => 'any-group', 'unknown' => 'group' } } }
    end

    before do
      stub_const('BigshotQuickStartupSpec::QuickGroupInitialization', group_initialization)
    end

    it 'publishes and activates the supervised runtime before any initial group query' do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # Inject only the parsed private selector so the old implementation reaches
      # the actual ordering bug instead of merely rejecting an unknown CLI flag.
      allow(BigshotQuickStartupSpec::QuickRequest).to receive(:parse).and_wrap_original do |original, argv|
        request = original.call(argv)
        BigshotQuickStartupSpec::QuickRequest.new(request.command, request.options.merge('supervised-start-v1' => "#{now + 20},#{now + 30}"))
      end
      allow(group_initialization).to receive(:call) do |**|
        expect(owner).to respond_to(:quick_combat_runtime)
        expect(owner.quick_combat_runtime.status[:execution_window][:work_deadline]).to eq(now + 20)
        expect(owner.quick_combat_runtime.supervisor_ready?).to be(true)
      end
      start('assist', output: lambda { |message|
        messages << message
        owner.quick_combat_runtime.activate_supervised(valid: -> { true }) if owner.respond_to?(:quick_combat_runtime)
      })
      expect(group_initialization).to have_received(:call).once
    end

    it 'passes owner safety and distinct wound-free receipt observations to the feed' do
      start('assist')
      expect(group_initialization).to have_received(:call).with(engine: engine, owner: owner, prefix: '>',
                                                                snapshot: engine.loop_options[:attack_observation], leader: '').once
      expect(engine.loop_options.keys).to contain_exactly(:observation, :attack_observation)
      count = engine.wounds.length
      expect(engine.loop_options[:attack_observation].call[:wounded]).to be_nil
      expect(engine.wounds.length).to eq(count)
      expect(engine.loop_options[:observation].call[:wounded]).to be(false)
      expect(engine.wounds.length).to eq(count + 1)
    end

    it 'rejects unavailable native attack provenance without starting combat' do
      engine.feed_available = false
      expect { start('assist') }.to raise_error(ArgumentError, /synchronous attack/)
      expect(engine.calls).to be_empty
      expect(engine.run).to be_nil
    end

    it 'refuses disabled outcome tracking before reset, group queries or combat' do
      engine.outcome_available = false
      $bigshot_debug = :unchanged
      expect { start('assist') }.to raise_error(ArgumentError, /ineffective-action monitoring requires enabled native combat tracking with observation provenance/)
      expect(resets).to be_empty
      expect(group_initialization).not_to have_received(:call)
      expect(engine.calls).to be_empty
      expect(engine.run).to be_nil
      expect($bigshot_debug).to eq(:unchanged)
    end

    it 'refuses a missing outcome capability before reset or group queries' do
      engine.singleton_class.undef_method(:quick_outcome_observation_available?)
      expect { start('assist') }.to raise_error(ArgumentError, /ineffective-action monitoring/)
      expect(resets).to be_empty
      expect(group_initialization).not_to have_received(:call)
      expect(engine.calls).to be_empty
    end

    it 'does not constrain any-group initialization by an unused saved leader field' do
      stored['presets']['default']['leader'] = 'FormerLeader'
      start('assist')
      expect(group_initialization).to have_received(:call).with(hash_including(leader: ''))
    end
  end

  it 'bypasses group queries and pulling players only inside the guarded Quick command scope' do
    source = BigshotQuickStartupSpec::SOURCE[/^  def check_for_deaders_prone\n.*?^  end$/m]
    receiver = Class.new { class_eval(source) }.new
    guard = double(checkpoint!: true)
    receiver.instance_variable_set(:@quick_native_scope, true)
    receiver.instance_variable_set(:@quick_guard, guard)
    receiver.check_for_deaders_prone
    expect(guard).to have_received(:checkpoint!).once
  end
end
