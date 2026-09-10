# frozen_string_literal: true

module BigshotQuickControlsSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[QuickExecution EncounterPolicy EncounterController QuickGuard QuickRun].each do |name|
    body = source[/^  (?:class|module) #{name}\n.*?^  end$/m]
    raise "could not extract #{name}" unless body
    module_eval(body, __FILE__, __LINE__)
  end

  module Script
    class << self
      attr_accessor :current
    end
  end

  module UpstreamHook
    class << self
      attr_accessor :hooks, :registrations, :removed

      def add(name, action, persist: nil)
        registrations << [name, persist]
        hooks[name] = action
      end

      def remove(name)
        removed << name
        hooks.delete(name)
      end

      def run(input)
        hooks.values.each do |action|
          input = action.call(input)
          return nil if input.nil?
        end
        input
      end
    end
  end

  class Owner
    attr_accessor :name
    attr_reader :sleeps

    def initialize(name)
      @name = name
      @sleeps = []
    end

    def execution_guard_active?
      false
    end

    def execution_sleep(duration)
      @sleeps << duration
    end
  end

  class Engine
    include QuickExecution
    attr_reader :messages, :debug_messages

    def initialize
      @messages = []
      @debug_messages = []
      @DEBUG_SYSTEM = :system
      @DEBUG_COMMANDS = :commands
    end

    def respond(message)
      @messages << message
    end

    def debug_msg(type, message)
      @debug_messages << [type, message]
    end
  end
end

RSpec.describe 'Bigshot scoped Quick client controls' do
  let(:engine) { BigshotQuickControlsSpec::Engine.new }
  let(:owner) { BigshotQuickControlsSpec::Owner.new('bigshot') }
  let(:hooks) { BigshotQuickControlsSpec::UpstreamHook }
  let(:cached) { { state: :running, target_id: '123', actions: 2, reason: nil }.freeze }
  let(:mailbox) { [] }
  let(:run) do
    double('run').tap do |instance|
      allow(instance).to receive(:request) { |action| mailbox << action; { accepted: true, status: cached } }
    end
  end

  before do
    BigshotQuickControlsSpec::Script.current = owner
    hooks.hooks, hooks.registrations, hooks.removed = {}, [], []
  end

  after { BigshotQuickControlsSpec::Script.current = nil }

  def scoped(prefix = ';', &block)
    engine.with_quick_controls(run, owner: owner, lich_prefix: prefix, &block)
  end

  it 'queues exact active-owner controls and distinguishes acknowledgement from current status' do
    scoped do
      expect(hooks.run(';bigshot quick hold')).to be_nil
      expect(hooks.run('<c>;bigshot quick status')).to be_nil
    end
    expect(mailbox).to eq(%w[hold status])
    expect(engine.messages.first).to include('hold queued', 'current state: running')
    expect(engine.messages.last).to include('running', 'target 123', 'actions 2')
    expect(engine.messages.last).not_to include('queued')
    expect(hooks.registrations.last.last).to be(false)
  end

  it 'surfaces recent observation and execution error diagnostics on explicit status' do
    diagnostic = cached.merge(
      observations: [{ sequence: 7, command: 'attack target', outcome: :interrupted, reason: 'execution_error' }],
      error: { class: 'RuntimeError', message: 'adapter failed', location: 'adapter.rb:42' }
    ).freeze
    allow(run).to receive(:request).with('status').and_return(accepted: true, status: diagnostic)
    scoped { expect(hooks.run(';bigshot quick status')).to be_nil }
    expect(engine.messages.last).to include('recent #7 attack target=interrupted/execution_error')
    expect(engine.messages.last).to include('error RuntimeError: adapter failed at adapter.rb:42')
  end

  it 'matches literal custom prefixes and owner names containing regex characters' do
    owner.name = 'bigshot.test'
    scoped('.*') do
      expect(hooks.run('<c>.*bigshot.test quick stop')).to be_nil
      [';bigshot.test quick stop', '.*bigshotXtest quick stop', '..bigshot.test quick stop'].each do |input|
        expect(hooks.run(input)).to equal(input)
      end
    end
    expect(mailbox).to eq(['stop'])
  end

  it 'passes ordinary game and unrelated Lich commands through unchanged' do
    scoped do
      ['attack #123', ';other quick hold', ';bigshot setup', ';bigshot quicker stop', 'say ;bigshot quick stop', ';;bigshot quick hold'].each do |input|
        expect(hooks.run(input)).to equal(input)
      end
    end
    expect(mailbox).to be_empty
  end

  it 'consumes malformed commands in this Quick namespace without queuing them' do
    scoped do
      [';bigshot quick', ';bigshot quick stop now', ';bigshot quick --force stop', ";bigshot quick hold\nattack #123"].each do |input|
        expect(hooks.run(input)).to be_nil
      end
    end
    expect(mailbox).to be_empty
    expect(engine.messages.length).to eq(4)
    expect(engine.messages).to all(include('no extra arguments'))
  end

  it 'reports mailbox rejection as not queued' do
    allow(run).to receive(:request).with('hold').and_return(accepted: false, reason: 'control_queue_full', status: cached)
    scoped { expect(hooks.run(';bigshot quick hold')).to be_nil }
    expect(engine.messages.last).to include('not queued', 'control_queue_full')
  end

  it 'queues exact human engagement IDs without querying game state on the hook thread' do
    expect(run).to receive(:request_engagement).with('123').and_return(accepted: true, status: cached)
    scoped { expect(hooks.run(';bigshot quick engage #123')).to be_nil }
    expect(engine.messages.last).to include('engage #123 queued')
  end

  it 'consumes a recognized control when mailbox handling raises' do
    allow(run).to receive(:request).and_raise('mailbox error')
    scoped { expect(hooks.run(';bigshot quick stop')).to be_nil }
    expect(engine.messages.last).to eq('Quick Combat control could not be queued.')
  end

  it 'removes only its own unique hook after normal and exceptional completion' do
    hooks.add('unrelated', ->(input) { input }, persist: true)
    expect(scoped { :result }).to eq(:result)
    first_name = hooks.removed.last
    expect { scoped { raise 'body error' } }.to raise_error(RuntimeError, 'body error')
    expect(hooks.removed.last).not_to eq(first_name)
    expect(hooks.hooks.keys).to eq(['unrelated'])
  end

  context 'with the real QuickRun lifecycle' do
    let(:observations) { [] }
    let(:policy) { BigshotQuickControlsSpec::EncounterPolicy.new({ 'mode' => 'watch' }) }
    let(:run) do
      BigshotQuickControlsSpec::QuickRun.new(engine: engine, policy: policy, owner: owner,
                                             snapshot: -> { observations << true; { session: 'login', room_id: 100, room_epoch: 1, targets: [], members: [], safe: true, owner: true, connected: true } },
                                             resolve_target: ->(_) { nil }, validate: ->(_) { true }, prefix: '>')
    end

    around do |example|
      previous = $clean_lich_char
      $clean_lich_char = ';'
      example.run
    ensure
      $clean_lich_char = previous
    end

    it 'monitors while held, services queued stop and closes without game commands' do
      count = 0
      final = engine.quick_run_loop(run, owner: owner) do
        count += 1
        hooks.run(';bigshot quick hold') if count == 1
        hooks.run(';bigshot quick stop') if count == 3
      end
      expect(final).to include(state: :stopped, reason: 'manual_stop')
      expect(observations.length).to eq(2)
      expect(owner.sleeps).to eq([0.1, 0.1])
      expect(engine.messages.grep(/Quick Combat held:/)).to eq(['Quick Combat held: manual_hold (0 combat sends, 0 loot sends).'])
      expect(hooks.hooks).to be_empty
      expect(run.request('resume')).to include(accepted: false, reason: 'run_closed')
      expect(engine.debug_messages).to include([:system, a_string_including('Quick Combat lifecycle started')],
                                               [:system, a_string_including('Quick Combat lifecycle finished')])
    end

    it 'cleans up its hook and lifecycle when the event pump fails' do
      expect { engine.quick_run_loop(run, owner: owner) { raise 'event pump failed' } }.to raise_error(RuntimeError, 'event pump failed')
      expect(run.status).to include(state: :stopped, reason: 'manual_stop')
      expect(hooks.hooks).to be_empty
      expect(owner.sleeps).to be_empty
    end

    it 'reports an automatic cleanup hold with its usage once, not on every idle tick' do
      held = { state: :held, reason: 'command_limit', sends: 2, loot_sends: 20 }
      allow(run).to receive(:tick).and_return(held, held, { state: :stopped })
      engine.quick_run_loop(run, owner: owner)
      expect(engine.messages).to eq(['Quick Combat held: command_limit (2 combat sends, 20 loot sends).'])
    end
  end
end
