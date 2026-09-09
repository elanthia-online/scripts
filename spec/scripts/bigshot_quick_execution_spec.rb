# frozen_string_literal: true

# Optional companion integration uses the actual native guard without imposing
# a developer checkout path on the normal scripts suite:
# LICH_EXECUTION_GUARD_ROOT=/path/to/lich-5 rspec this_spec.rb
if ENV['LICH_EXECUTION_GUARD_ROOT']
  require File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script_execution_guard')
end

module BigshotQuickExecutionSpec
  module Script
    class << self
      attr_accessor :current

      def self
        @current
      end
    end
  end

  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[QuickGuard QuickIO QuickExecution].each do |name|
    body = source[/^  (?:class|module) #{name}\n.*?^  end$/m]
    raise "could not extract #{name}" unless body
    module_eval(body, __FILE__, __LINE__)
  end

  # Contract fixture for standard repo tests. The optional integration run
  # uses the companion's actual guard and source-extracted Script scope methods.
  class ScopeGuard
    class Interrupted < StandardError; end

    def initialize(callback)
      @callback = callback
      @cancelled = false
    end

    def checkpoint!(command: nil)
      raise Interrupted if @cancelled
      accepted = @callback.call(command)
      @cancelled = accepted != true
      raise Interrupted if @cancelled
      true
    end

    def close!
      @cancelled = true
    end
  end

  class Owner
    attr_reader :wires
    attr_accessor :on_send

    def initialize
      @wires = []
    end

    def execution_guard_active?
      !@guard.nil?
    end

    def with_execution_guard(callback)
      raise ArgumentError, 'already active' if @guard
      scope = ScopeGuard.new(callback)
      @guard = scope
      begin
        scope.checkpoint!
        result = yield scope
        scope.checkpoint!
        result
      ensure
        scope.close!
        @guard = nil
      end
    end

    def emit(wire)
      check_execution_guard!(command: wire)
      @wires << wire
      @on_send&.call(wire)
    end

    def native_wait
      check_execution_guard!
    end

    def downstream_buffer
      @downstream_buffer ||= []
    end

    def check_execution_guard!(command: nil)
      @guard ? @guard.checkpoint!(command: command) : true
    end
  end

  if ENV['LICH_EXECUTION_GUARD_ROOT']
    script_source = File.read(File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script.rb')).gsub("\r\n", "\n")
    Owner.const_set(:ScriptExecutionGuard, Lich::Common::ScriptExecutionGuard)
    Owner.const_set(:EXECUTION_GUARD_MUTEX_INITIALIZER, Mutex.new)
    %w[with_execution_guard execution_guard_active? check_execution_guard! execution_guard_mutex].each do |name|
      body = script_source[/^      def #{Regexp.escape(name)}(?:\([^\n]*\))?\n.*?^      end$/m]
      raise "could not extract companion Script##{name}" unless body
      Owner.class_eval(body, __FILE__, __LINE__)
    end
  end

  class NativeSpell
    def initialize(owner)
      @owner = owner
    end

    def cast
      @owner.emit('>prepare 903')
      @owner.native_wait
      @owner.emit('>cast #123')
    end
  end

  class Transport
    def put(*messages)
      messages.each { |message| @owner.emit(@prefix + message) }
    end

    def sleep(_duration)
      @after_sleep&.call
    end

    def get?
      @owner.native_wait
      @responses&.shift
    end
  end

  class Engine < Transport
    include QuickIO
    include QuickExecution
    attr_accessor :routine, :after_sleep, :responses
    attr_reader :calls

    def initialize(owner, prefix = '>')
      super()
      @owner, @prefix = owner, prefix
      @spell = NativeSpell.new(owner)
      @calls = []
    end

    def cmd(command, target)
      @calls << [self, command, target]
      instance_exec(&@routine)
    end

    def debug_msg(*); end
    def reset_variables(_moved); end
    def clear; end
    def dead? = false
    def checkstunned = false
    def checkwebbed = false

    class_eval(File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")[/^  def bs_put\(message\)\n.*?^  end$/m])
  end
end

RSpec.describe 'Bigshot Quick native execution bridge' do
  let(:owner) { BigshotQuickExecutionSpec::Owner.new }
  let(:engine) { BigshotQuickExecutionSpec::Engine.new(owner) }
  let(:identity) { { session: 'login', room_id: 100, room_epoch: 1, target_id: '123' } }
  let(:observed) { identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running) }
  let(:clock) { [100.0] }
  let(:limit) { 5 }
  let(:guard) do
    BigshotQuickExecutionSpec::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                                              max_sends: limit, max_seconds: 20, clock: -> { clock.first })
  end
  let(:target) { Object.new }

  before { BigshotQuickExecutionSpec::Script.current = owner }
  after { BigshotQuickExecutionSpec::Script.current = nil }

  def execute
    engine.quick_execute('903(m20)', target, guard: guard, owner: owner, prefix: '>')
  end

  def expect_clean_scope
    expect(owner.execution_guard_active?).to be(false)
    expect(engine.instance_variable_get(:@quick_guard)).to be_nil
    expect(engine.instance_variable_get(:@quick_native_scope)).to be(false)
  end

  it 'calls the existing cmd on its original receiver with unchanged command and target' do
    engine.routine = -> { put('attack #123') }
    expect(execute).to eq(outcome: :sent, sends: 1)
    expect(engine.calls).to eq([[engine, '903(m20)', target]])
    expect(owner.wires).to eq(['>attack #123'])
    expect_clean_scope
  end

  it 'exposes the immutable identity bound at guard admission without rereading the world' do
    identity[:target_id] = +'123'
    expected = identity.transform_values(&:to_s)
    expect(guard.identity).to eq(expected)
    identity[:target_id].replace('456')
    expect(guard.identity[:target_id]).to eq('123')
    expect(guard.identity).to be_frozen
    expect(guard.identity.values).to all(be_frozen)
  end

  it 'counts local and other-receiver native sends exactly once each' do
    engine.routine = -> { put('stance offensive'); @spell.cast }
    expect(execute).to eq(outcome: :sent, sends: 3)
    expect(owner.wires).to eq(['>stance offensive', '>prepare 903', '>cast #123'])
    expect_clean_scope
  end

  it 'strips exactly one configured prefix before command admission' do
    engine.routine = -> { put('>attack #123') }
    expect(guard).to receive(:transmit).with('>attack #123').and_call_original
    expect(execute[:sends]).to eq(1)
    expect(owner.wires).to eq(['>>attack #123'])
  end

  it 'rejects an unexpected wire prefix before transport' do
    engine.routine = -> { @owner.emit('!cast #123') }
    expect { execute }.to raise_error(BigshotQuickExecutionSpec::QuickGuard::Interrupted) { |error| expect(error.reason).to eq('wire_prefix_changed') }
    expect(owner.wires).to be_empty
    expect(guard.sends).to eq(0)
    expect_clean_scope
  end

  context 'with one available command' do
    let(:limit) { 1 }

    it 'blocks the native cast after preparation consumes the command limit' do
      engine.routine = -> { @spell.cast }
      expect { execute }.to raise_error(BigshotQuickExecutionSpec::QuickGuard::Interrupted) { |error| expect(error.reason).to eq('command_limit') }
      expect(owner.wires).to eq(['>prepare 903'])
      expect(guard.sends).to eq(1)
      expect_clean_scope
    end

    it 'detects sticky native cancellation at scope exit when a helper rescues it' do
      engine.routine = lambda do
        begin
          @spell.cast
        rescue StandardError
          :legacy_helper_swallowed_it
        end
      end
      expect { execute }.to raise_error(BigshotQuickExecutionSpec::QuickGuard::Interrupted) { |error| expect(error.reason).to eq('command_limit') }
      expect(owner.wires).to eq(['>prepare 903'])
      expect_clean_scope
    end
  end

  it 'cancels native waits after room identity changes before another send' do
    owner.on_send = ->(_) { observed[:room_epoch] = 2 }
    engine.routine = -> { @spell.cast }
    expect { execute }.to raise_error(BigshotQuickExecutionSpec::QuickGuard::Interrupted) { |error| expect(error.reason).to eq('room_epoch_changed') }
    expect(owner.wires).to eq(['>prepare 903'])
    expect_clean_scope
  end

  it 'checks Bigshot local sleep while the native scope is active' do
    engine.after_sleep = -> { clock[0] = 121.0 }
    engine.routine = -> { sleep(1); put('must not send') }
    expect { execute }.to raise_error(BigshotQuickExecutionSpec::QuickGuard::Interrupted) { |error| expect(error.reason).to eq('time_limit') }
    expect(owner.wires).to be_empty
    expect_clean_scope
  end

  it 'does not report success after a helper swallows a local QuickIO interruption' do
    engine.routine = lambda do
      begin
        sleep(nil)
      rescue StandardError
        :legacy_helper_swallowed_it
      end
    end
    expect { execute }.to raise_error(BigshotQuickExecutionSpec::QuickGuard::Interrupted) { |error| expect(error.reason).to eq('unbounded_wait') }
    expect(owner.wires).to be_empty
    expect_clean_scope
  end

  it 'latches a local observation denial even if the helper restores healthy observations' do
    state = observed
    engine.routine = lambda do
      state[:control] = :held
      begin
        put('must not send')
      rescue StandardError
        state[:control] = :running
      end
    end
    expect { execute }.to raise_error(BigshotQuickExecutionSpec::QuickGuard::Interrupted) { |error| expect(error.reason).to eq('held') }
    expect(owner.wires).to be_empty
    expect_clean_scope
  end

  it 'cleans up an unrelated command error and preserves that error' do
    engine.routine = -> { raise 'original engine error' }
    expect { execute }.to raise_error(RuntimeError, 'original engine error')
    expect_clean_scope
  end

  it 'rejects nesting before touching the original engine or existing native scope' do
    engine.routine = -> { raise 'must not call cmd' }
    owner.with_execution_guard(->(_) { true }) do
      expect { execute }.to raise_error(ArgumentError, /already active/)
      expect(owner.execution_guard_active?).to be(true)
      expect(engine.calls).to be_empty
      owner.emit('>outer scope still works')
    end
    expect(owner.wires).to eq(['>outer scope still works'])
  end

  it 'fails before cmd when the companion core is unavailable' do
    engine.routine = -> { raise 'must not call cmd' }
    expect do
      engine.quick_execute('903', target, guard: guard, owner: Object.new, prefix: '>')
    end.to raise_error(ArgumentError, /requires Lich/)
    expect(engine.calls).to be_empty
    expect(owner.wires).to be_empty
  end

  it 'rejects another script owner before cmd or scope installation' do
    BigshotQuickExecutionSpec::Script.current = Object.new
    engine.routine = -> { raise 'must not call cmd' }
    expect { execute }.to raise_error(ArgumentError, /owning/)
    expect(engine.calls).to be_empty
    expect(owner.execution_guard_active?).to be(false)
  end

  def install_eloot(&implementation)
    api = Module.new
    api.const_set(:ROOM_LOOT_API_VERSION, 1)
    api.define_singleton_method(:restore_room_hands) { |**| { outcome: :complete } }
    api.define_singleton_method(:room_loot, &implementation)
    stub_const('BigshotQuickExecutionSpec::ELoot', api)
    owner.singleton_class.attr_accessor :silent, :want_downstream, :want_downstream_xml
  end

  it 'runs strict room or corpse requests through eLoot on the same native scope' do
    expect(engine).not_to receive(:reset_variables)
    scopes = []
    install_eloot do |corpse_ids:, floor:, owner:, **|
      scopes << [owner.execution_guard_active?, corpse_ids.frozen?]
      owner.emit(floor ? '>get #456' : ">search ##{corpse_ids.first}")
      { outcome: :complete }.freeze
    end
    %w[room #123].each do |target_text|
      engine.responses = ['You search the remains.']
      result = engine.quick_loot_execute("loot #{target_text}", guard: guard, owner: owner, prefix: '>')
      expect(result[:outcome]).to eq(:complete)
      expect(engine.calls).to be_empty
      expect_clean_scope
    end
    expect(owner.wires).to eq(['>get #456', '>search #123'])
    expect(scopes).to eq([[true, true], [true, true]])
  end

  it 'rejects alternate or compound loot commands before installing a scope' do
    ['loot', 'loot #0', 'loot #123;attack #123', "loot room\nlook", 'search #123', 'script eloot'].each do |command|
      expect { engine.quick_loot_execute(command, guard: guard, owner: owner, prefix: '>') }.to raise_error(ArgumentError, /Quick loot/)
    end
    expect(owner.wires).to be_empty
    expect(owner.execution_guard_active?).to be(false)
    expect(engine.instance_variable_get(:@quick_guard)).to be_nil
    expect(engine.instance_variable_get(:@quick_native_scope)).to be_nil
  end

  it 'charges and bounds eLoot helper initialization and retry sends' do
    install_eloot do |owner:, **|
      owner.emit('>inventory')
      owner.emit('>inventory')
      { outcome: :complete }.freeze
    end
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock.first }
    engine.after_sleep = -> { clock[0] += 0.1 }
    engine.responses = ['Sorry, you may only type ahead one command.']
    one_send = BigshotQuickExecutionSpec::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                                                         max_sends: 1, max_seconds: 20, clock: -> { clock.first })
    expect do
      engine.quick_loot_execute('loot #123', guard: one_send, owner: owner, prefix: '>')
    end.to raise_error(BigshotQuickExecutionSpec::QuickGuard::Interrupted) { |error| expect(error.reason).to eq('command_limit') }
    expect(owner.wires).to eq(['>inventory'])
    expect(one_send.sends).to eq(1)
    expect_clean_scope
  end
end
