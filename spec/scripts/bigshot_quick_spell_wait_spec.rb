# frozen_string_literal: true

module BigshotQuickSpellWaitSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[QuickGuard QuickIO QuickExecution].each do |name|
    module_eval(source[/^  (?:class|module) #{name}\n.*?^  end$/m])
  end

  class Transport
    attr_accessor :clock, :lines, :read_action, :sleep_action
    attr_reader :readers, :delays, :stands

    def initialize
      @clock, @lines, @readers, @delays, @stands = 0.0, [], [], [], 0
    end

    def get?
      @readers << Thread.current
      @read_action&.call
      @lines.shift
    end

    def sleep(seconds)
      @clock += seconds
      @delays << seconds
      @sleep_action&.call
    end

    def dead_or_gone?(_npc) = false
    def still_targetable?(_id) = true
    def should_flee? = false
    def standing? = true
    def stand = (@stands += 1)
  end

  class Engine < Transport
    include QuickIO
    include QuickExecution
  end
end

RSpec.describe 'Quick owner-thread spell completion wait' do
  let(:engine) { BigshotQuickSpellWaitSpec::Engine.new }
  let(:npc) { Struct.new(:id).new('123') }
  let(:identity) { { session: 'login', room_id: 42, room_epoch: 1, target_id: '123' } }
  let(:snapshot) { identity.merge(owner: true, connected: true, safe: true, authorized: true, target_valid: true, control: :running) }
  let(:guard) do
    BigshotQuickSpellWaitSpec::QuickGuard.new(snapshot: -> { snapshot }, identity: identity,
                                              max_sends: 3, max_seconds: 2, clock: -> { engine.clock })
  end

  before do
    engine.instance_variable_set(:@quick_guard, guard)
    engine.instance_variable_set(:@quick_native_scope, true)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { engine.clock }
    expect(Thread).not_to receive(:new)
  end

  def wait(duration: 1)
    engine.quick_wait_for_spell(npc, complete: /spell finished/, duration: duration)
  end

  it 'drains completion on the owner without consuming the next routine response' do
    engine.lines = ['unrelated', 'spell finished', 'next action']
    expect(wait).to eq(:complete)
    expect(engine.lines).to eq(['next action'])
    expect(engine.readers.uniq).to eq([Thread.current])
    expect(engine.delays).to be_empty
  end

  it 'times out when no further output arrives, without a blocked background reader' do
    expect(wait).to eq(:timeout)
    expect(engine.clock).to be_within(0.001).of(1)
    expect(guard.sends).to eq(0)
  end

  it 'yields between bounded batches in a busy stream' do
    engine.lines = Array.new(70, 'noise') + ['spell finished']
    expect(wait).to eq(:complete)
    expect(engine.delays.length).to eq(2)
    expect(engine.readers.length).to eq(71)
  end

  { control: [:held, 'held'], room_id: [43, 'room_id_changed'],
    safe: [false, 'safety_unverified'], connected: [false, 'disconnected'] }.each do |field, (value, reason)|
    it "interrupts the owner wait when #{field} changes" do
      engine.sleep_action = -> { snapshot[field] = value }
      expect { wait }.to raise_error(BigshotQuickSpellWaitSpec::QuickGuard::Interrupted) { |error| expect(error.reason).to eq(reason) }
      expect(engine.clock).to eq(0.1)
      expect(engine.readers.length).to eq(1)
    end
  end

  it 'observes permission revocation within a busy input batch' do
    engine.lines = Array.new(100, 'noise')
    engine.read_action = -> { snapshot[:authorized] = false }
    expect { wait }.to raise_error(BigshotQuickSpellWaitSpec::QuickGuard::Interrupted, /permission_revoked/)
    expect(engine.readers.length).to eq(1)
  end

  it 'remains subject to the shorter original routine deadline' do
    expect { wait(duration: 12) }.to raise_error(BigshotQuickSpellWaitSpec::QuickGuard::Interrupted, /time_limit/)
    expect(engine.clock).to be_within(0.001).of(2)
  end

  it 'returns on target loss without trying to stand or cast again' do
    allow(engine).to receive(:dead_or_gone?).with(npc).and_return(true)
    expect(wait).to eq(:target_unavailable)
    expect(engine.readers).to be_empty
    expect(engine.stands).to eq(0)
  end

  it 'retains native standing recovery while the scope remains valid' do
    allow(engine).to receive(:standing?).and_return(false, true)
    engine.sleep_action = -> { engine.lines << 'spell finished' }
    expect(wait).to eq(:complete)
    expect(engine.stands).to eq(1)
  end

  it 'requires a valid scoped wait rather than silently becoming unbounded' do
    [0, -1, Float::INFINITY, Float::NAN].each do |duration|
      expect { wait(duration: duration) }.to raise_error(ArgumentError)
    end
    engine.instance_variable_set(:@quick_native_scope, false)
    expect { wait }.to raise_error(ArgumentError, /active execution scope/)
  end
end
