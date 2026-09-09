# frozen_string_literal: true

if ENV['LICH_EXECUTION_GUARD_ROOT']
  require File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script_execution_guard')
end

module BigshotQuickRetreatSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[EncounterPolicy EncounterController QuickGuard QuickRun QuickRetreat130].each do |name|
    body = source[/^  class #{name}\n.*?^  end$/m]
    raise "could not extract #{name}" unless body

    module_eval(body)
  end

  class Owner
    class Denied < StandardError; end
    attr_accessor :on_sleep
    attr_reader :writes

    def initialize
      @writes = []
    end

    def execution_guard_active?
      !@policy.nil?
    end

    def with_execution_guard(policy)
      raise 'nested native guard' if @policy

      @policy, @cancelled = policy, false
      check_execution_guard!
      result = yield
      check_execution_guard!
      result
    ensure
      @policy = nil
    end

    def check_execution_guard!(command: nil)
      checkpoint(command)
    end

    def checkpoint(command)
      @cancelled = true unless @policy.call(command)
      raise Denied if @cancelled
    end

    def emit(command)
      check_execution_guard!(command: command)
      @writes << command
    end

    def execution_sleep(seconds)
      check_execution_guard!
      @on_sleep.call(seconds)
      check_execution_guard!
    end
  end

  # Optional native scope integration, without a required developer checkout.
  # The spell remains a canonical-object fixture; this verifies the companion
  # cancellation machinery, not live Spirit Guide behavior.
  if ENV['LICH_EXECUTION_GUARD_ROOT']
    native = File.read(File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script.rb')).gsub("\r\n", "\n")
    Owner.const_set(:ScriptExecutionGuard, Lich::Common::ScriptExecutionGuard)
    Owner.const_set(:EXECUTION_GUARD_MUTEX_INITIALIZER, Mutex.new)
    Owner.send(:remove_const, :Denied)
    Owner.const_set(:Denied, Lich::Common::ScriptExecutionGuard::Interrupted)
    %w[with_execution_guard execution_guard_active? check_execution_guard! execution_guard_mutex].each do |name|
      body = native[/^      def #{Regexp.escape(name)}(?:\([^\n]*\))?\n.*?^      end$/m]
      raise "could not extract native Script##{name}" unless body

      Owner.class_eval(body)
    end
  end
end

RSpec.describe BigshotQuickRetreatSpec::QuickRetreat130 do
  let(:owner) { BigshotQuickRetreatSpec::Owner.new }
  let(:now) { [100.0] }
  let(:world) do
    { session: 'login', room_id: 100, room_epoch: 1, owner: true, connected: true,
      alive: true, stable: true, destination_safe: false }
  end
  let(:settings) { { 'max_actions' => 4, 'max_seconds' => 10 } }
  let(:spell) { double('canonical Spell[130]', known?: true, affordable?: true) }
  let(:adapter) do
    described_class.new(settings, destinations: ['200'], owner: owner, prefix: '>', spell: spell, clock: -> { now.first })
  end

  before do
    stub_const('BigshotQuickRetreatSpec::Script', double(current: owner))
    owner.on_sleep = ->(seconds) { now[0] += seconds }
    allow(spell).to receive(:cast) do
      owner.emit('>incant 130')
      arrive
      'opaque native response'
    end
  end

  def arrive
    world.merge!(room_id: 200, room_epoch: 2, destination_safe: true)
  end

  def retreat
    adapter.call { world.dup }
  end

  it 'resolves explicit mapped Lich rooms and unambiguous UIDs without choosing routes' do
    map = double('map')
    allow(map).to receive(:[]).with(200).and_return(Object.new)
    allow(map).to receive(:[]).with(201).and_return(Object.new)
    allow(map).to receive(:ids_from_uid).with(900).and_return([201])
    expect(described_class.destinations('200, u900, 200', fallback: nil, map: map)).to eq(%w[200 201])
    expect(described_class.destinations('', fallback: 'u900', map: map)).to eq(['201'])
  end

  it 'rejects unknown/ambiguous destination UIDs and placeholder or malformed rooms' do
    map = double('map', ids_from_uid: [200, 201])
    allow(map).to receive(:[]).and_return(nil)
    ['u900', 'u-900', '-200', 'u-', 'u0', 'u-0', '4', '0', '200', '200,', '', 'north', '200;east'].each do |text|
      expect { described_class.destinations(text, fallback: nil, map: map) }.to raise_error(ArgumentError)
    end
  end

  it 'resolves a negative UID to a positive mapped room, including profile fallback' do
    map = double('map')
    expect(map).to receive(:ids_from_uid).with(-900).twice.and_return([201])
    allow(map).to receive(:[]).with(201).and_return(Object.new)
    expect(described_class.destinations('u-900', fallback: nil, map: map)).to eq(['201'])
    expect(described_class.destinations('', fallback: 'u-900', map: map)).to eq(['201'])
  end

  it 'uses the canonical native spell and reports success only at the configured safe destination' do
    expect(retreat).to eq(outcome: :retreated, sends: 1, reason: 'retreated')
    expect(spell).to have_received(:cast).once.with(no_args)
    expect(owner.writes).to eq(['>incant 130'])
    expect(owner).not_to be_execution_guard_active
  end

  it 'requires the destination proof even when a native response sounds successful' do
    allow(spell).to receive(:cast) { owner.emit('>incant 130'); world.merge!(room_id: 999, room_epoch: 2); 'Success!' }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_displacement_unverified')
  end

  it 'does not treat a same-room epoch change as a confirmed escape' do
    allow(spell).to receive(:cast) { owner.emit('>incant 130'); world[:room_epoch] += 1 }
    expect(retreat[:reason]).to eq('retreat_displacement_unverified')
  end

  it 'does not declare a hostile or environmentally dangerous configured destination safe' do
    allow(spell).to receive(:cast) { owner.emit('>incant 130'); arrive; world[:destination_safe] = false }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_destination_unsafe')
  end

  it 'requires fresh survival and connection evidence after displacement' do
    [[:alive, 'retreat_survival_unverified'], [:connected, 'disconnected'], [:owner, 'owner_lost']].each do |key, reason|
      world.merge!(room_id: 100, room_epoch: 1, alive: true, connected: true, owner: true)
      allow(spell).to receive(:cast) { owner.emit('>incant 130'); arrive; world[key] = false }
      expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: reason)
    end
  end

  it 'does not pulse mana, cast fallback spells or create children when 130 is unavailable' do
    allow(spell).to receive(:affordable?).and_return(false)
    expect(retreat).to eq(outcome: :unconfirmed, sends: 0, reason: 'retreat_spell_unavailable')
    expect(spell).not_to have_received(:cast)
    expect(owner.writes).to be_empty
  end

  it 'bounds a native helper that returns without moving, while allowing cooperative cancellation' do
    allow(spell).to receive(:cast) { owner.emit('>incant 130') }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_time_limit')
    expect(now.first).to be <= 110.2
  end

  it 'counts all accepted retry sends and refuses the retry beyond the escape budget' do
    settings['max_actions'] = 1
    allow(spell).to receive(:cast) { 2.times { owner.emit('>incant 130') } }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_action_limit')
    expect(owner.writes).to eq(['>incant 130'])
  end

  it 'rejects any fallback command and every new send after displacement' do
    allow(spell).to receive(:cast) { owner.emit('>symbol of return') }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 0, reason: 'retreat_command_denied')
    allow(spell).to receive(:cast) { owner.emit('>incant 130'); arrive; owner.emit('>incant 130') }
    expect(retreat).to eq(outcome: :retreated, sends: 1, reason: 'retreated')
    expect(owner.writes).to eq(['>incant 130'])
  end

  it 'does not confuse a stopped helper that swallowed interruption with success' do
    allow(spell).to receive(:cast) do
      owner.emit('>incant 130')
      world[:escape_cancelled] = 'manual_stop'
      begin
        owner.check_execution_guard!
      rescue BigshotQuickRetreatSpec::Owner::Denied
        arrive
      end
    end
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'manual_stop')
    expect(owner).not_to be_execution_guard_active
  end

  it 'denies a changed prefix or injected native command without charging a send' do
    ['!incant 130', ">incant 130\nlook"].each do |wire|
      allow(spell).to receive(:cast) { owner.emit(wire) }
      expect(retreat).to eq(outcome: :unconfirmed, sends: 0, reason: 'retreat_command_denied')
    end
    expect(owner.writes).to be_empty
  end

  it 'does not retry a native execution error or call a counted send unsent' do
    allow(spell).to receive(:cast) { owner.emit('>incant 130'); raise 'uncertain transport outcome' }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'retreat_execution_error')
    expect(spell).to have_received(:cast).once
  end

  it 'copies the initial session identity and detects caller mutation during a native wait' do
    world[:session] = +'login'
    allow(spell).to receive(:cast) { owner.emit('>incant 130'); world[:session].replace('other'); arrive }
    expect(retreat).to eq(outcome: :unconfirmed, sends: 1, reason: 'session_changed')
  end

  context 'the real QuickRun lifecycle' do
    let(:policy) { BigshotQuickRetreatSpec::EncounterPolicy.new({ 'mode' => 'watch' }) }
    let(:run) do
      BigshotQuickRetreatSpec::QuickRun.new(engine: Object.new, policy: policy, owner: owner,
                                            snapshot: -> { world.merge(safe: false, targets: [], members: []) },
                                            retreat_snapshot: -> { world.dup }, retreat: adapter,
                                            resolve_target: ->(_id) {}, validate: ->(_command) { true }, prefix: '>', clock: -> { now.first })
    end

    it 'finishes verified retreat with separate escape accounting and no attack actions' do
      run.request('retreat')
      expect(run.tick).to include(state: :stopped, reason: 'retreated', escape_sends: 1, escape_reason: 'retreated', actions: 0)
    end

    it 'drains a queued stop inside native waits and preserves the terminal stop' do
      allow(spell).to receive(:cast) do
        owner.emit('>incant 130')
        run.request('stop')
        owner.execution_sleep(0.1)
        owner.emit('>incant 130')
      end
      run.request('retreat')
      expect(run.tick).to include(state: :stopped, reason: 'manual_stop', escape_sends: 1)
      expect(owner.writes).to eq(['>incant 130'])
    end

    it 'allows a manual hold to cancel further movement without losing monitoring ownership' do
      allow(spell).to receive(:cast) do
        owner.emit('>incant 130')
        run.request('hold')
        owner.execution_sleep(0.1)
      end
      run.request('retreat')
      expect(run.tick).to include(state: :held, escape_reason: 'retreat_hold_requested', escape_sends: 1)
      expect(owner.writes).to eq(['>incant 130'])
    end

    it 'consumes queue validity on entry rather than treating its TTL as the native spell lifetime' do
      valid = true
      run.request('retreat', valid: -> { valid })
      allow(spell).to receive(:cast) do
        owner.emit('>incant 130')
        valid = false
        owner.execution_sleep(0.1)
        arrive
      end
      expect(run.tick).to include(state: :stopped, reason: 'retreated', escape_sends: 1)
      expect(owner.writes).to eq(['>incant 130'])
    end

    it 'does not resume a failed native retreat automatically' do
      allow(spell).to receive(:cast) { owner.emit('>incant 130'); world.merge!(room_id: 999, room_epoch: 2) }
      run.request('retreat')
      3.times { run.tick }
      expect(spell).to have_received(:cast).once
      expect(run.status).to include(state: :held, reason: 'retreat_displacement_unverified')
    end

    it 'preserves a terminal session change observed inside the native escape scope' do
      allow(spell).to receive(:cast) { owner.emit('>incant 130'); world[:session] = 'different character' }
      run.request('retreat')
      expect(run.tick).to include(state: :stopped, reason: 'session_changed', escape_sends: 1)
      expect(owner.writes).to eq(['>incant 130'])
    end
  end
end
