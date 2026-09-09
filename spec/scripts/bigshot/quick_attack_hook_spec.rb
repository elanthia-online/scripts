# frozen_string_literal: true

module BigshotQuickAttackHookSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[QuickExecution EncounterPolicy EncounterController QuickEngagement QuickAttackFeed].each do |name|
    module_eval(source[/^  (?:class|module) #{name}\n.*?^  end$/m])
  end

  module Script
    class << self
      attr_accessor :current
    end
  end

  module Game
    class << self
      attr_accessor :thread, :ingress_time

      def current_ingress_time
        ingress_time if Thread.current.equal?(thread)
      end
    end
  end

  class NativeXML
    attr_accessor :room_count, :in_stream

    def initialize
      @room_count = 1
      @in_stream = false
      @active_tags, @active_ids = [], []
      @current_stream, @current_style = '', ''
      @bold = false
    end
  end
  XMLData = NativeXML.new

  module Room
    def self.current
      Struct.new(:id).new(42)
    end
  end

  module DownstreamHook
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
        hooks.values.each { |hook| input = hook.call(input) }
        input
      end
    end
  end

  module Lich
    module Gemstone
      module Combat
        module Definitions
          module Attacks
            # Native THIRD_PERSON_ATTACKS shape from combat/defs/attacks.rb.
            ATTACK_LOOKUP = [[/(?<attacker>.+?) swings (?<weapon>.+?) at (?<target>.+?)(?: in a murderous arc)?!/, :attack]].freeze
          end
        end

        module Parser
          class << self
            attr_accessor :failure, :after_parse

            def parse_attack(line)
              raise 'parser failure' if failure
              after_parse&.call
              ids = line.scan(/<a exist="(-?\d+)"/).flatten
              { name: :attack, foreign_caster: true, attacker: { id: ids.first.to_i }, target: { id: ids.last.to_i } }
            end
          end
        end
      end
    end
  end

  class Engine
    include QuickExecution
  end
end

RSpec.describe 'Bigshot scoped native attack observation' do
  let(:engine) { BigshotQuickAttackHookSpec::Engine.new }
  let(:owner) { Object.new }
  let(:hooks) { BigshotQuickAttackHookSpec::DownstreamHook }
  let(:game) { BigshotQuickAttackHookSpec::Game }
  let(:xml) { BigshotQuickAttackHookSpec::XMLData }
  let(:parser) { BigshotQuickAttackHookSpec::Lich::Gemstone::Combat::Parser }
  let(:clock) { [10.0] }
  let(:evidence) { [] }
  let(:run) { double('owner run', observe_engagement: nil) }
  let(:snapshot) do
    { session: 'login', room_id: 42, room_epoch: 1, owner: true, connected: true,
      members_verified: true, members: ['Ally'], member_records: [{ id: '-10', name: 'Ally' }],
      targets: [{ id: '100', hostile: true, dead: false }] }
  end
  let(:actor) { '<a exist="-10" noun="Ally">Ally</a>' }
  let(:target) { '<pushBold/>a <a exist="100" noun="rat">rat</a><popBold/>' }
  let(:line) { "#{actor} swings a sword at #{target}!\r\n" }
  let(:receipt_reads) { [] }
  let(:owner_reads) { [] }
  let(:receipt_reader) { -> { receipt_reads << Thread.current; snapshot } }
  let(:owner_reader) { -> { owner_reads << Thread.current; snapshot } }

  before do
    @old_server_buffer = $_SERVERBUFFER_
    $_SERVERBUFFER_ = []
    hooks.hooks, hooks.registrations, hooks.removed = {}, [], []
    BigshotQuickAttackHookSpec::Script.current = owner
    game.thread, game.ingress_time = Thread.current, 10.0
    xml.instance_variables.each { |key| xml.remove_instance_variable(key) }
    xml.send(:initialize)
    parser.failure, parser.after_parse = false, nil
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock.first }
    allow(run).to receive(:observe_engagement) { |**packet| evidence << packet }
  end

  after { $_SERVERBUFFER_ = @old_server_buffer }

  def scoped(&block)
    engine.with_quick_attack_feed(run, owner: owner, observation: owner_reader, attack_observation: receipt_reader, &block)
  end

  def deliver(text, raw: text, native: true)
    game.thread = Thread.current if native
    $_SERVERBUFFER_ << raw
    hooks.run(text)
  end

  it 'rejects old native ingress even when the hook clock is fresh' do
    game.ingress_time = 1.0
    scoped { |drain| deliver(line); drain.call }
    expect(evidence).to be_empty
  end

  it 'preserves original ingress instead of relabeling it with hook time' do
    game.ingress_time = 9.5
    scoped { |drain| deliver(line); drain.call }
    expect(evidence.first[:at]).to eq(9.5)
  end

  it 'rejects missing ingress and invocation outside the exact game parser thread' do
    scoped do |drain|
      game.ingress_time = nil
      deliver(line)
      game.ingress_time = 10.0
      game.thread = nil
      deliver(line, native: false)
      drain.call
    end
    expect(evidence).to be_empty
  end

  context 'with actual encounter permission cutoffs' do
    let(:sent) { [] }
    let(:run) do
      settings = { 'mode' => 'assist', 'trigger' => 'leader', 'leader' => 'Ally',
                   'unknown' => 'group', 'fallback_commands' => 'attack target', 'targeting' => 'assist-only' }
      policy = BigshotQuickAttackHookSpec::EncounterPolicy.new(settings, targets: {}, routines: {}, fallback: ['attack target'])
      BigshotQuickAttackHookSpec::EncounterController.new(policy: policy, snapshot: -> { snapshot.merge(safe: true) },
                                                          dispatch: ->(**item) { sent << item; :sent }, clock: -> { clock.first })
    end

    before { allow(run).to receive(:observe_engagement).and_call_original }

    it 'cannot grant startup or resumed permission from input queued before the cutoff' do
      scoped do |drain|
        game.ingress_time = 9.5
        deliver(line)
        drain.call
        run.tick
        expect(sent).to be_empty
        clock[0] = 11.0
        run.hold
        run.resume
        game.ingress_time = 10.5
        deliver(line)
        drain.call
        run.tick
        expect(sent).to be_empty
        game.ingress_time = 11.0
        deliver(line)
        drain.call
        run.tick
        expect(sent.length).to eq(1)
      end
    end
  end

  it 'captures receipt provenance synchronously but only delivers evidence on the owner thread' do
    owner_thread = Thread.current
    scoped do |drain|
      worker = Thread.new { deliver(line) }
      expect(worker.value).to equal(line)
      expect(evidence).to be_empty
      expect(owner_reads).to be_empty
      expect(receipt_reads).not_to include(owner_thread)
      drain.call
      expect(owner_reads).to eq([owner_thread])
    end
    expect(evidence).to eq([{ member: 'Ally', target_id: '100', room_id: 42, room_epoch: 1, at: 10.0,
                            member_roster: [['-10', 'Ally']] }])
    expect(hooks.registrations.last.last).to be(false)
    expect(hooks.hooks).to be_empty
  end

  it 'drains verified evidence before the owner tick and closes both feed and run' do
    allow(engine).to receive(:with_quick_controls) { |*_args, **_options, &block| block.call }
    allow(run).to receive(:tick) do
      expect(evidence.size).to eq(1)
      { state: :completed }
    end
    allow(run).to receive(:close)
    result = engine.quick_run_loop(run, owner: owner, observation: owner_reader, attack_observation: receipt_reader) { deliver(line) }
    expect(result).to eq(state: :completed)
    expect(run).to have_received(:close)
    expect(hooks.hooks).to be_empty
  end

  it 'rejects non-main native context, prior-hook rewrites, speech and partial chunks' do
    scoped do |drain|
      xml.in_stream = true
      deliver(line)
      xml.in_stream = false
      xml.instance_variable_set(:@active_tags, ['stream'])
      deliver(line)
      xml.instance_variable_set(:@active_tags, [])
      deliver(line, raw: 'ordinary native line')
      deliver("#{actor} says, \"#{line.strip}\"\n")
      deliver('fragment')
      deliver(line)
      drain.call
      expect(evidence).to be_empty
      deliver(line)
      drain.call
      expect(evidence.size).to eq(1)
    end
  end

  it 'drops stale room, session and membership evidence at owner drain' do
    scoped do |drain|
      deliver(line)
      snapshot[:session] = 'new-login'
      drain.call
      deliver(line)
      snapshot[:member_records] = []
      drain.call
      snapshot[:member_records] = [{ id: '-10', name: 'Ally' }]
      deliver(line)
      xml.room_count = snapshot[:room_epoch] = 2
      drain.call
    end
    expect(evidence).to be_empty
  end

  it 'rejects movement during parsing and ambiguous creature targets' do
    scoped do |drain|
      parser.after_parse = -> { xml.room_count = snapshot[:room_epoch] = 2 }
      deliver(line)
      parser.after_parse = nil
      deliver("#{actor} swings a sword at #{target} and #{target}!\n")
      drain.call
    end
    expect(evidence).to be_empty
  end

  it 'bounds queued events and drops expired packets without blocking the hook' do
    scoped do |drain|
      70.times { expect(deliver(line)).to equal(line) }
      drain.call
      expect(evidence.size).to eq(64)
      evidence.clear
      deliver(line)
      clock[0] = 14.0
      drain.call
      expect(evidence).to be_empty
    end
  end

  it 'keeps unrelated native input intact when parsing fails' do
    scoped do |drain|
      parser.failure = true
      expect(deliver(line)).to equal(line)
      expect(deliver("normal output\n")).to eq("normal output\n")
      drain.call
    end
    expect(evidence).to be_empty
  end

  it 'removes only its scoped hook on error and disables captured callbacks after cleanup' do
    untouched = proc { |input| input }
    hooks.hooks['unrelated'] = untouched
    captured = nil
    expect do
      scoped do |_drain|
        captured = hooks.hooks.values.last
        raise 'owner stopped'
      end
    end.to raise_error(RuntimeError, 'owner stopped')
    expect(hooks.hooks).to eq('unrelated' => untouched)
    $_SERVERBUFFER_ << line
    expect(captured.call(line)).to equal(line)
    expect(receipt_reads).to be_empty
  end

  it 'rejects non-owner drains and unavailable native context before hook installation' do
    scoped do |drain|
      failure = Thread.new do
        drain.call
      rescue ThreadError => error
        error
      end.value
      expect(failure).to be_a(ThreadError)
    end
    xml.remove_instance_variable(:@active_ids)
    expect(engine.quick_attack_observation_available?).to be(false)
    expect { scoped {} }.to raise_error(ArgumentError, /unavailable/)
    expect(hooks.hooks).to be_empty
  end
end
