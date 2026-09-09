# frozen_string_literal: true

require_relative '../../support/bigshot_quick_native_cmd_support'

module BigshotQuickCompilationSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  class Admission; end
  %w[command_supported! admit_routines!].each do |method|
    Admission.class_eval(source[/^    def self.#{Regexp.escape(method)}\(.*?^    end$/m])
  end
  class Engine < BigshotQuickNativeCmdSpec::Engine
    EncounterPolicy = BigshotQuickNativeCmdSpec::EncounterPolicy
  end
  %w[clean_value quick_compile_commands quick_routine_map quick_policy].each do |method|
    Engine.class_eval(source[/^  def #{method}\(.*?^  end$/m])
  end
end

RSpec.describe 'Quick character and trial command compilation' do
  let(:namespace) { BigshotQuickNativeCmdSpec }
  let(:owner) { namespace::Owner.new }
  let(:engine) { BigshotQuickCompilationSpec::Engine.new(owner) }
  let(:admission) { BigshotQuickCompilationSpec::Admission }

  it 'uses actual split_xx profile semantics for commas, grouped commands and repetition on every trial line' do
    lines = ['attack target and jab target(x2)', 'grapple target, kick target(xx)']
    expect(engine).to receive(:clean_value).with('split_xx', lines[0]).and_call_original
    expect(engine).to receive(:clean_value).with('split_xx', lines[1]).and_call_original
    compiled = engine.quick_compile_commands(lines)
    expect(compiled).to eq([['attack target', 'jab target']] * 2 + ['grapple target'] + ['kick target'] * 5)
    expect(compiled).to be_frozen
    expect(compiled.first).to be_frozen
    expect(compiled.first.first).to be_frozen
    expect(lines).to eq(['attack target and jab target(x2)', 'grapple target, kick target(xx)'])
    expect(lines).not_to be_frozen
  end

  it 'supplies the same compiled fallback to policy without changing the saved text or profile routine' do
    text = 'attack target and jab target, grapple target(x2)'.dup
    settings = { 'fallback_commands' => text, 'unknown' => 'manual' }
    engine.instance_variable_set(:@TARGETS, 'rat' => 'a')
    engine.instance_variable_set(:@HUNTING_COMMANDS, ['903'])
    policy = engine.quick_policy(settings)
    commands = policy.commands(name: 'invader', noun: 'invader')
    expect(commands).to eq(engine.clean_value('split_xx', text))
    expect(commands).to be_frozen
    expect(policy.commands(name: 'rat', noun: 'rat')).to eq(['903'])
    expect(settings['fallback_commands']).to eq(text)
    expect(settings['fallback_commands']).not_to be_frozen
  end

  it 'rejects unsupported leaves throughout expanded arrays before any native send' do
    ['attack target and script child', 'attack target and incant00130(x2)',
     'attack target, attack target and go2 42(xx)'].each do |text|
      settings = { 'fallback_commands' => text }
      expect { admission.admit_routines!(engine, settings, nil) }.to raise_error(ArgumentError)
      trial = { actions: engine.quick_compile_commands([text]) }
      expect { admission.admit_routines!(engine, {}, trial) }.to raise_error(ArgumentError)
    end
    expect(owner.wires).to be_empty
  end

  it 'preserves native zero-repeat behavior and refuses an empty resulting sequence' do
    expect(engine.quick_compile_commands(['attack target(x0)'])).to eq([])
    expect { admission.admit_routines!(engine, {}, actions: []) }.to raise_error(ArgumentError, /requires configured/)
  end

  it 'identifies the rejected compiled routine as well as the reason' do
    engine.instance_variable_set(:@TARGETS, 'rat' => 'a')
    engine.instance_variable_set(:@HUNTING_COMMANDS, ['wait 10', 'script fixture-combat'])
    expect { admission.admit_routines!(engine, { 'fallback_commands' => '' }, nil) }
      .to raise_error(ArgumentError, /child scripts.*command: "script fixture-combat"/)
    expect(owner.wires).to be_empty
  end

  it 'does not let normalization hide command separators or accept non-editor array definitions' do
    ["attack target\njab target", 'attack target(xx);go2 42', ['attack target']].each do |entry|
      expect { engine.quick_compile_commands([entry]) }.to raise_error(ArgumentError, /command definitions/)
    end
  end

  context 'when passing a compiled group through the existing native cmd engine' do
    let(:npc) { Struct.new(:id, :name, :noun).new('123', 'giant rat', 'rat') }
    let(:identity) { { session: 'login', room_id: 100, room_epoch: 1, target_id: '123' } }
    let(:observed) { identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running) }

    before do
      namespace::Script.current = owner
      namespace::Spell.entries = {
        1201 => namespace::NativeSpell.new(1201, owner, known: false),
        597  => namespace::NativeSpell.new(597, owner)
      }
      %i[debug_msg check_for_deaders_prone escape_rooms waitrt? waitcastrt? change_stance].each { |method| allow(engine).to receive(method) }
      allow(engine).to receive(:dead_or_gone?).and_return(false)
      allow(engine).to receive(:still_targetable?).with('123').and_return(true)
      allow(engine).to receive(:valid_target?).with(npc).and_return(true)
      allow(engine).to receive(:standing?).and_return(true)
      allow(engine).to receive(:checkprep).and_return('None')
    end

    after do
      namespace::Script.current = nil
      namespace::Spell.entries = nil
      expect(owner.execution_guard_active?).to be(false)
    end

    def execute(limit: 10)
      commands = engine.quick_compile_commands(['attack target and jab target'])
      admission.command_supported!(commands)
      guard = namespace::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                                        max_sends: limit, max_seconds: 20, clock: -> { 100.0 })
      engine.quick_execute(commands.first, npc, guard: guard, owner: owner, prefix: '>')
    end

    it 'dispatches separate targeted native commands and accounts for every send in the group' do
      expect(execute).to eq(outcome: :sent, sends: 2)
      expect(owner.wires).to eq(['>attack #123', '>jab #123'])
    end

    it 'does not grant an entire compiled group for the price of one native send' do
      expect { execute(limit: 1) }.to raise_error(namespace::QuickGuard::Interrupted, /command_limit/)
      expect(owner.wires).to eq(['>attack #123'])
    end

    it 'rechecks cancellation before the next member of a compiled group' do
      owner.on_send = ->(_wire) { observed[:control] = :held }
      expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /held/)
      expect(owner.wires).to eq(['>attack #123'])
    end

    it 'applies the trial-wide action limit across repeated native groups, including an interrupted partial group' do
      settings = { 'mode' => 'trial', 'max_actions' => 3, 'max_seconds' => 20 }
      policy = engine.quick_policy(settings)
      trial = { target_id: '123', actions: engine.quick_compile_commands(['attack target and jab target(x2)']) }
      world = observed.merge(targets: [{ id: '123', name: 'giant rat', noun: 'rat', hostile: true }])
      run = namespace::QuickRun.new(engine: engine, policy: policy, owner: owner, snapshot: -> { world },
                                    resolve_target: ->(_id) { npc }, validate: admission.method(:command_supported!),
                                    prefix: '>', trial: trial, clock: -> { 100.0 })
      expect(run.tick).to include(state: :running, actions: 2)
      expect(run.tick).to include(state: :held, actions: 3)
      expect(owner.wires).to eq(['>attack #123', '>jab #123', '>attack #123'])
      expect(trial[:actions]).to eq([['attack target', 'jab target']] * 2)
    end
  end
end
