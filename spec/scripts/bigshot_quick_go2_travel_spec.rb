# frozen_string_literal: true

require_relative '../support/bigshot_quick_walk_harness'

module BigshotQuickGo2Spec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  module_eval(source[/^  class QuickGo2Travel\n.*?^  end$/m])
  class Engine
    def debug_msg(*); end
  end
  Engine.class_eval(source[/^  def go2\(.*?^  end$/m])

  class Owner < BigshotQuickWalkSpec::Owner
    attr_accessor :stopping
    attr_reader :child_scripts

    def initialize
      super
      @child_scripts = []
    end

    def stopping? = !!@stopping
    def execution_sleep(_seconds) = sleep(0.001)
  end

  class Child
    attr_reader :writes, :killed

    def initialize(owner, policy, commands, world, after_send)
      @owner, @writes = owner, []
      owner.child_scripts << self
      @thread = Thread.new do
        Thread.current[:go2_fixture_script] = self
        begin
          raise 'startup denied' unless policy.call(nil)
          commands.each do |command|
            raise 'send denied' unless policy.call(">#{command}")
            @writes << command
            world[:room_id] += 1
            world[:room_epoch] += 1
            after_send&.call(self)
          end
          raise 'completion denied' unless policy.call(nil)
        rescue StandardError => error
          @error = error
        ensure
          owner.child_scripts.delete(self)
        end
      end
    end

    def join(timeout) = @thread.join(timeout) && self
    def completed_successfully? = @error.nil? && !@thread.alive? && !@killed

    def kill_sync(timeout:)
      @killed = true
      @thread.kill
      !!@thread.join(timeout)
    end
  end
end

RSpec.describe BigshotQuickGo2Spec::QuickGo2Travel do
  let(:owner) { BigshotQuickGo2Spec::Owner.new }
  let(:engine) { BigshotQuickGo2Spec::Engine.new }
  let(:map) { double('map', :[] => true) }
  let(:world) { { room_id: 100, room_epoch: 1, stable: true, connected: true, alive: true, session: 'fixture-login', owner: true } }
  let(:commands) { Array.new(32, 'north') }
  let(:after_send) { nil }
  let(:deadline) { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3 }
  let(:adapter) do
    described_class.new(destination: 132, deadline: deadline, owner: owner, prefix: '>', map: map,
                        launch: ->(destination, policy) { engine.go2(destination, execution_guard: policy) })
  end

  before do
    @children = []
    script = Class.new
    script.const_set(:START_EXECUTION_GUARD_PROTOCOL, 1)
    script.const_set(:SCRIPT_START_RESTRICTION_PROTOCOL, 1)
    stub_const('BigshotQuickGo2Spec::Script', script)
    allow(script).to receive(:current) { Thread.current[:go2_fixture_script] || owner }
    allow(script).to receive(:start_child) do |name, args, quiet:, execution_guard:, allow_script_starts:|
      expect(name).to eq('go2')
      expect(args).to start_with('132 --disable-confirm --typeahead=0 ')
      expect(args).to include('--preserve-scripts')
      expect(quiet).to be(true)
      expect(allow_script_starts).to be(false)
      child = BigshotQuickGo2Spec::Child.new(owner, execution_guard, commands, world, after_send)
      @children << child
      child
    end
  end

  after do
    @children.each { |child| child.kill_sync(timeout: 1) unless child.join(0) }
  end

  def travel
    adapter.call do
      current = BigshotQuickGo2Spec::Script.current
      world.merge(owner: world[:owner] && (current.equal?(owner) ||
        (owner.respond_to?(:quick_refuge_travel_child?) && owner.quick_refuge_travel_child?(current))))
    end
  end

  it 'delegates a long outside-area trip to go2 and verifies the final room' do
    expect(travel).to include(outcome: :retreated, sends: 32)
    expect(@children.one?).to be(true)
    expect(@children.first.writes).to eq(commands)
    expect(world[:room_id]).to eq(132)
    expect(owner.child_scripts).to be_empty
    expect(owner).not_to respond_to(:quick_refuge_travel_child?)
  end

  it 'does not mistake a clean go2 exit for arrival' do
    commands.clear
    expect(travel).to include(outcome: :unconfirmed, reason: 'refuge_travel_arrival_unconfirmed')
    expect(owner.child_scripts).to be_empty
  end

  it 'does not start go2 when already at its destination' do
    world[:room_id] = 132
    expect(travel).to include(outcome: :retreated, sends: 0)
    expect(@children).to be_empty
  end

  context 'when an ordinary stop arrives during outbound travel' do
    let(:after_send) { ->(_) { world[:escape_cancelled] = 'manual_stop' } }

    it 'unwinds the exact child without another movement send' do
      expect(travel).to include(outcome: :unconfirmed, reason: 'manual_stop', sends: 1)
      expect(@children.first.writes).to eq(['north'])
      expect(owner.child_scripts).to be_empty
    end
  end

  context 'when hard authority is revoked' do
    let(:after_send) { ->(_) { world[:owner] = false } }

    it 'denies the next send and does not grant cleanup travel authority' do
      expect(travel).to include(outcome: :unconfirmed, sends: 1)
      expect(@children.first.writes).to eq(['north'])
    end
  end

  context 'when go2 attempts something outside travel' do
    let(:commands) { ['withdraw 1000 silvers', 'north'] }

    it 'denies spending rather than treating it as part of test travel' do
      expect(travel).to include(outcome: :unconfirmed, reason: 'refuge_travel_command_denied', sends: 0)
      expect(@children.first.writes).to be_empty
    end
  end

  context 'when the session changes' do
    let(:after_send) { ->(_) { world[:session] = 'replacement' } }

    it 'does not follow the replacement session' do
      expect(travel).to include(outcome: :unconfirmed, reason: 'refuge_travel_session_lost', sends: 1)
    end
  end

  it 'does not launch with an expired phase deadline' do
    allow(adapter).to receive(:validate!).and_call_original
    adapter.instance_variable_set(:@deadline, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
    expect(travel).to include(outcome: :unconfirmed, reason: 'refuge_travel_deadline')
    expect(@children).to be_empty
  end

  it 'retains ordinary Bigshot go2 invocation when no guard was requested' do
    allow(engine).to receive(:hidden?).and_return(false)
    allow(engine).to receive(:invisible?).and_return(false)
    room = Class.new
    stub_const('BigshotQuickGo2Spec::Room', room)
    allow(room).to receive(:current).and_return(double(id: 100, tags: []))
    expect(BigshotQuickGo2Spec::Script).to receive(:run).with('go2', '132 --disable-confirm', { quiet: true })
    engine.go2(132)
    expect(@children).to be_empty
  end
end
