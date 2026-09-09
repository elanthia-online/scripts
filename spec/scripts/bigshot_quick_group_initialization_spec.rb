# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

module BigshotQuickGroupInitializationSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[EncounterPolicy QuickGroupInitialization].each do |name|
    body = source[/^  class #{name}\n.*?^  end$/m]
    raise "Missing #{name}" unless body

    module_eval(body)
  end

  module Script
    class << self
      attr_accessor :current
    end
  end

  class Owner
    class Interrupted < StandardError; end

    attr_accessor :stopping, :on_sleep
    attr_reader :sends, :sleeps

    def initialize(clock)
      @clock = clock
      @sends, @sleeps = [], []
    end

    def stopping?
      !!@stopping
    end

    def execution_guard_active?
      !@policy.nil?
    end

    def with_execution_guard(policy)
      @policy = policy
      check_execution_guard!
      result = yield
      check_execution_guard!
      result
    ensure
      @policy = nil
    end

    def check_execution_guard!(command: nil)
      raise Interrupted, 'native cancellation' unless @policy.call(command) == true
    end

    def emit(command)
      check_execution_guard!(command: command)
      @sends << command
    end

    def execution_sleep(seconds)
      check_execution_guard!
      @sleeps << seconds
      @clock[0] += seconds
      @on_sleep&.call
      check_execution_guard!
    end
  end

  class Engine
    attr_accessor :after_send

    def initialize(owner)
      @owner = owner
    end

    private

    def put(command)
      @owner.emit("<c>#{command}")
      @after_send&.call
    end
  end
end

RSpec.describe BigshotQuickGroupInitializationSpec::QuickGroupInitialization do
  let(:clock) { [10.0] }
  let(:owner) { BigshotQuickGroupInitializationSpec::Owner.new(clock) }
  let(:engine) { BigshotQuickGroupInitializationSpec::Engine.new(owner) }
  let(:members) { [{ id: '-10', name: 'Ally' }] }
  let(:group) { double('native group', checked?: true, _members: members) }
  let(:observed) do
    { session: 'login', room_id: 42, room_epoch: 1, owner: true, connected: true,
      safe: false, safety_reason: 'wound check required.', members_verified: true,
      member_records: members }
  end
  let(:observing_threads) { [] }
  let(:snapshot) do
    lambda do
      observing_threads << Thread.current
      observed.merge(members_verified: group.checked?, member_records: members.dup)
    end
  end

  before do
    BigshotQuickGroupInitializationSpec::Script.current = owner
    expect(group).not_to receive(:check)
    expect(group).not_to receive(:clear)
    expect(group).not_to receive(:members)
  end

  def initialize_group(**options)
    described_class.call(engine: engine, owner: owner, prefix: '<c>', snapshot: snapshot,
                         group: group, clock: -> { clock[0] }, **options)
  end

  it 'uses verified present membership without querying or mutating the native group' do
    expect(initialize_group).to eq(queried: false, members: ['Ally'])
    expect(owner.sends).to be_empty
    expect(owner.sleeps).to be_empty
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'does not query after supervisor authority or work time has expired' do
    allow(group).to receive(:checked?).and_return(false)
    expect { initialize_group(permit: -> { false }) }.to raise_error(ArgumentError, /supervisor authority/)
    expect(owner.sends).to be_empty
  end

  it 'unwinds the initial group wait immediately when supervisor permission expires' do
    allow(group).to receive(:checked?).and_return(false)
    expect { initialize_group(permit: -> { clock[0] < 10.05 }) }.to raise_error(ArgumentError, /supervisor authority/)
    expect(owner.sends).to eq(['<c>group'])
    expect(owner.sleeps).to eq([0.05])
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'sends one owner-bound query and waits for native membership verification' do
    allow(group).to receive(:checked?).and_return(false)
    owner.on_sleep = -> { allow(group).to receive(:checked?).and_return(true) }
    result = initialize_group(leader: 'ally')
    expect(result).to eq(queried: true, members: ['Ally'])
    expect(result).to be_frozen
    expect(result[:members]).to be_frozen
    expect(owner.sends).to eq(['<c>group'])
    expect(owner.sleeps).to eq([0.05])
    expect(observing_threads.uniq).to eq([Thread.current])
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'accepts verification that arrived during the query send without an extra wait' do
    allow(group).to receive(:checked?).and_return(false)
    engine.after_send = -> { allow(group).to receive(:checked?).and_return(true) }
    expect(initialize_group[:queried]).to be(true)
    expect(owner.sleeps).to be_empty
  end

  it 'refuses confirmed no-group status with an actionable message' do
    members.clear
    expect { initialize_group }.to raise_error(ArgumentError, /join your group, run GROUP/)
    expect(owner.sends).to be_empty
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'refuses a queried empty membership without fabricating a group' do
    allow(group).to receive(:checked?).and_return(false)
    engine.after_send = lambda do
      members.clear
      allow(group).to receive(:checked?).and_return(true)
    end
    expect { initialize_group }.to raise_error(ArgumentError, /verified group members here/)
    expect(owner.sends).to eq(['<c>group'])
  end

  it 'stops polling after three seconds without clearing the prior native cache' do
    allow(group).to receive(:checked?).and_return(false)
    expect { initialize_group }.to raise_error(ArgumentError, /query timed out; run GROUP/)
    expect(clock[0]).to be_between(13.0, 13.051)
    expect(owner.sends).to eq(['<c>group'])
    expect(members).to eq([{ id: '-10', name: 'Ally' }])
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'does not query for an already cancelled owner' do
    owner.stopping = true
    allow(group).to receive(:checked?).and_return(false)
    expect { initialize_group }.to raise_error(ArgumentError, /lost its owner/)
    expect(owner.sends).to be_empty
  end

  it 'cancels promptly when the native owner begins stopping during the wait' do
    allow(group).to receive(:checked?).and_return(false)
    owner.on_sleep = -> { owner.stopping = true }
    expect { initialize_group }.to raise_error(ArgumentError, /lost its owner/)
    expect(owner.sleeps).to eq([0.05])
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'rejects a changed room before accepting newly verified membership' do
    allow(group).to receive(:checked?).and_return(false)
    owner.on_sleep = lambda do
      observed[:room_epoch] += 1
      allow(group).to receive(:checked?).and_return(true)
    end
    expect { initialize_group }.to raise_error(ArgumentError, /changed room or session/)
  end

  it 'rejects disconnection while waiting' do
    allow(group).to receive(:checked?).and_return(false)
    owner.on_sleep = -> { observed[:connected] = false }
    expect { initialize_group }.to raise_error(ArgumentError, /lost its connection/)
  end

  it 'rejects a repeated query or alternative command at the native send boundary' do
    ['<c>group', '<c>attack #100', '<c>group open'].each do |command|
      allow(group).to receive(:checked?).and_return(false)
      engine.after_send = -> { owner.emit(command) }
      expect { initialize_group }.to raise_error(ArgumentError, /unexpected or repeated command/)
    end
    expect(owner.sends).to eq(['<c>group'] * 3)
  end

  it 'requires the selected leader among verified present members' do
    expect { initialize_group(leader: 'Other') }.to raise_error(ArgumentError, /not a verified group member here/)
    expect(owner.sends).to be_empty
  end

  it 'does not borrow another active native execution scope' do
    owner.with_execution_guard(->(_command) { true }) do
      expect { initialize_group }.to raise_error(ArgumentError, /cannot borrow an active scope/)
      expect(owner.execution_guard_active?).to be(true)
    end
  end

  it 'turns observation failures into a refusal and cleans the query scope' do
    calls = 0
    failing = lambda do
      calls += 1
      raise 'unavailable observation' if calls > 1

      observed
    end
    expect do
      described_class.call(engine: engine, owner: owner, prefix: '<c>', snapshot: failing,
                           group: group, clock: -> { clock[0] })
    end.to raise_error(ArgumentError, /group observation failed/)
    expect(owner.sends).to be_empty
    expect(owner.execution_guard_active?).to be(false)
  end

  it 'integrates with the companion native scope and Group listing/status observer' do
    skip 'Set LICH_EXECUTION_GUARD_ROOT for native Group integration' unless ENV['LICH_EXECUTION_GUARD_ROOT']
    # Keep native constants and registries isolated from the scripts suite.
    native = <<~'RUBY'
      require 'json'
      require 'set'
      $LOAD_PATH.unshift(File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib'))
      require 'common/script'
      require 'common/gameobj'
      require 'gemstone/group'
      Object.include Lich::Common
      owner = Lich::Common::Script.allocate
      Lich::Common::Script.define_singleton_method(:current) { owner }
      module Probe
      end
      source = File.read(ARGV.fetch(0)).gsub("\r\n", "\n")
      %w[EncounterPolicy QuickGroupInitialization].each do |name|
        body = source[/^  class #{name}\n.*?^  end$/m]
        raise "Missing #{name}" unless body
        Probe.module_eval(body)
      end
      group = Lich::Gemstone::Group
      raise 'Unexpected preverified fixture' if group.checked?
      GameObj.new_pc('-10', 'Ally', 'Ally')
      response = [
        'You are grouped with <a exist="-10" noun="Ally">Ally</a>.',
        'Your group status is currently open.'
      ]
      sends = []
      engine = Object.new
      engine.define_singleton_method(:put) do |command|
        wire = "<c>#{command}"
        owner.check_execution_guard!(command: wire)
        sends << wire
        response.each do |line|
          match = group::Observer.wants?(line)
          raise 'Native group message did not match' unless match
          group::Observer.consume(line, match)
        end
      end
      snapshot = lambda do
        { session: 'login', room_id: 42, room_epoch: 1, owner: true, connected: true,
          members_verified: group.checked?,
          member_records: group._members.map { |member| { id: member.id, name: member.noun } } }
      end
      result = Probe::QuickGroupInitialization.call(
        engine: engine, owner: owner, prefix: '<c>', snapshot: snapshot, leader: 'Ally'
      )
      puts JSON.generate(result: result, sends: sends, checked: group.checked?,
                         native_scope_active: owner.execution_guard_active?)
    RUBY
    source = File.expand_path('../../scripts/bigshot.lic', __dir__)
    output, error, status = Open3.capture3(RbConfig.ruby, '-', source, stdin_data: native)
    expect(status.success?).to be(true), "Native group probe failed:\n#{output}\n#{error}"
    expect(JSON.parse(output)).to eq(
      'result' => { 'queried' => true, 'members' => ['Ally'] },
      'sends' => ['<c>group'], 'checked' => true, 'native_scope_active' => false
    )
  end
end
