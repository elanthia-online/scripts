# Exercise actual Bigshot I/O overrides and bs_put without a game connection.
module BigshotQuickIOSpec
  SOURCE = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  module_eval(SOURCE[/^  class QuickGuard\n.*?^  end$/m])
  module_eval(SOURCE[/^  module QuickIO\n.*?^  end$/m])

  class BaseTransport
    attr_reader :sent, :lines, :delays
    attr_accessor :on_sleep, :on_send, :on_read

    def initialize
      @sent = []
      @lines = []
      @delays = []
    end

    def put(*messages)
      @sent.concat(messages)
      @on_send&.call
    end

    def sleep(seconds = nil)
      @delays << seconds
      @on_sleep&.call(seconds)
    end

    def get
      @lines.shift
    end

    def get?
      @on_read&.call
      @lines.shift
    end

    # Mimics the dispatch shape of inherited Lich helpers. They retain this
    # receiver, unlike Spell/Util singleton helpers (not covered by QuickIO).
    def fput(message)
      put(message)
      sleep(0.2)
      put(message) if get? == 'retry'
    end
  end

  class Harness < BaseTransport
    include QuickIO
    attr_writer :quick_guard
    attr_accessor :stunned, :webbed

    Script = Class.new do
      def self.self
        @script ||= Struct.new(:downstream_buffer).new([])
      end
    end

    def debug_msg(*); end
    def clear; end
    def respond(*); end
    def echo(*); end
    def dead? = false
    def checkstunned = @stunned
    def checkwebbed = @webbed

    class_eval(SOURCE[/^  def bs_put\(message\)\n.*?^  end$/m])
  end
end

RSpec.describe BigshotQuickIOSpec::QuickGuard do
  let(:time) { [10.0] }
  let(:identity) { { session: 'session-one', room_id: 25, room_epoch: 1, target_id: '17' } }
  let(:snapshot) { identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running) }
  let(:guard) { described_class.new(snapshot: -> { snapshot }, identity: identity, max_sends: 2, max_seconds: 1, clock: -> { time.first }) }

  it 'requires finite limits and complete identity' do
    expect { described_class.new(snapshot: -> {}, identity: {}, max_sends: 1, max_seconds: 1) }.to raise_error(ArgumentError)
    [0, -1, Float::INFINITY, Float::NAN].each do |seconds|
      expect { described_class.new(snapshot: -> {}, identity: identity, max_sends: 1, max_seconds: seconds) }.to raise_error(ArgumentError)
    end
  end

  it 'counts every attempted send, including uncertain transport failures' do
    expect { guard.transmit('attack #17') { raise IOError } }.to raise_error(IOError)
    guard.transmit('stance defensive') { true }
    expect(guard.sends).to eq(2)
    expect { guard.transmit('attack #17') { raise 'must not send' } }.to raise_error(described_class::Interrupted, /command_limit/)
  end

  it 'rejects multiline commands without spending a command allowance' do
    expect { guard.transmit("attack #17\nattack #17") {} }.to raise_error(described_class::Interrupted, /invalid_command/)
    expect(guard.sends).to eq(0)
  end

  it 'rechecks identity, permission and connection before transport' do
    { session: 'new', room_id: 26, room_epoch: 2, target_id: '18', owner: false,
      connected: false, authorized: false, target_valid: false, control: :stopped }.each do |key, value|
      prior = snapshot[key]
      candidate_guard = described_class.new(snapshot: -> { snapshot }, identity: identity,
                                            max_sends: 2, max_seconds: 1, clock: -> { time.first })
      snapshot[key] = value
      expect { candidate_guard.transmit('attack #17') { raise 'must not send' } }.to raise_error(described_class::Interrupted)
      expect(candidate_guard.sends).to eq(0)
      snapshot[key] = prior
    end
    expect(guard.sends).to eq(0)
  end

  it 'reports safety while held, without taking an escape action' do
    snapshot.merge!(control: :held, safe: false, safety_reason: 'wounded')
    expect { guard.checkpoint! }.to raise_error(described_class::Interrupted, /wounded/)
    snapshot[:safe] = true
    expect { guard.checkpoint! }.to raise_error(described_class::Interrupted, /wounded/)
    resumed = described_class.new(snapshot: -> { snapshot }, identity: identity,
                                  max_sends: 2, max_seconds: 1, clock: -> { time.first })
    expect { resumed.checkpoint! }.to raise_error(described_class::Interrupted, /held/)
  end

  it 'uses a monotonic deadline and rejects an invalid clock' do
    guard
    time[0] = 11.0
    expect { guard.checkpoint! }.to raise_error(described_class::Interrupted, /time_limit/)
    time[0] = 9.0
    expect { guard.checkpoint! }.to raise_error(described_class::Interrupted, /time_limit/)
    time[0] = 10.0
    fresh = described_class.new(snapshot: -> { snapshot }, identity: identity,
                                max_sends: 2, max_seconds: 1, clock: -> { time.first })
    time[0] = 9.0
    expect { fresh.checkpoint! }.to raise_error(described_class::Interrupted, /clock_invalid/)
  end

  it 'rechecks the deadline after a slow observation before issuing a command' do
    slow = described_class.new(snapshot: -> { time[0] = 11.0; snapshot }, identity: identity,
                               max_sends: 1, max_seconds: 1, clock: -> { time.first })
    sent = false
    expect { slow.transmit('attack #17') { sent = true } }.to raise_error(described_class::Interrupted, /time_limit/)
    expect(sent).to eq(false)
    expect(slow.sends).to eq(0)
  end
end

RSpec.describe BigshotQuickIOSpec::Harness do
  let(:time) { [10.0] }
  let(:identity) { { session: 'one', room_id: 25, room_epoch: 1, target_id: '17' } }
  let(:snapshot) { identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running) }
  let(:transport) { described_class.new }
  let(:guard) { BigshotQuickIOSpec::QuickGuard.new(snapshot: -> { snapshot }, identity: identity, max_sends: 1, max_seconds: 0.5, clock: -> { time.first }) }

  before do
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { time.first }
    transport.on_sleep = ->(seconds) { time[0] += seconds }
  end

  it 'preserves legacy bs_put and inherited helpers without a guard' do
    transport.lines << 'normal response'
    expect(transport.bs_put('attack #17')).to eq('normal response')
    transport.fput('look')
    expect(transport.sent).to eq(['attack #17', 'look'])
    expect(transport.delays).to eq([0.2])
  end

  it 'preserves the native sleep argument contract without a guard' do
    parent = Class.new do
      attr_reader :arguments

      def sleep(*arguments)
        @arguments = arguments
      end
    end
    native = Class.new(parent) { include BigshotQuickIOSpec::QuickIO }.new
    native.send(:sleep, nil)
    expect(native.arguments).to eq([nil])
    native.send(:sleep)
    expect(native.arguments).to eq([])
    native.send(:sleep, 0, 0)
    expect(native.arguments).to eq([0, 0])
  end

  it 'guards actual bs_put resends after a typeahead rejection' do
    transport.quick_guard = guard
    transport.lines << 'Sorry, you may only type ahead one command.'
    expect { transport.bs_put('attack #17') }.to raise_error(BigshotQuickIOSpec::QuickGuard::Interrupted, /command_limit/)
    expect(transport.sent).to eq(['attack #17'])
  end

  it 'interrupts the real roundtime retry sleep when held' do
    transport.quick_guard = guard
    transport.lines << '...wait 3 seconds.'
    transport.on_sleep = ->(seconds) { time[0] += seconds; snapshot[:control] = :held }
    expect { transport.bs_put('attack #17') }.to raise_error(BigshotQuickIOSpec::QuickGuard::Interrupted, /held/)
    expect(transport.sent).to eq(['attack #17'])
    expect(transport.delays.max).to be <= 0.1
  end

  it 'interrupts bs_put waiting on an empty stream at its deadline' do
    transport.quick_guard = guard
    expect { transport.bs_put('attack #17') }.to raise_error(BigshotQuickIOSpec::QuickGuard::Interrupted, /time_limit/)
    expect(transport.sent).to eq(['attack #17'])
  end

  it 'rechecks safety while the actual stun loop is waiting' do
    transport.quick_guard = guard
    transport.stunned = true
    transport.lines << 'You are stunned.'
    transport.on_sleep = ->(seconds) { time[0] += seconds; snapshot.merge!(safe: false, safety_reason: 'wounded') }
    expect { transport.bs_put('attack #17') }.to raise_error(BigshotQuickIOSpec::QuickGuard::Interrupted, /wounded/)
    expect(transport.sent.size).to eq(1)
  end

  it 'also guards sends made inside inherited helpers on the Bigshot receiver' do
    transport.quick_guard = guard
    transport.lines << 'retry'
    expect { transport.fput('attack #17') }.to raise_error(BigshotQuickIOSpec::QuickGuard::Interrupted, /command_limit/)
    expect(transport.sent.size).to eq(1)
  end

  it 'enforces the deadline on a busy get? stream that never sleeps' do
    transport.quick_guard = guard
    transport.lines.concat(Array.new(10, 'unrelated game output'))
    transport.on_read = -> { time[0] += 0.2 }
    expect { loop { transport.send(:get?) } }.to raise_error(BigshotQuickIOSpec::QuickGuard::Interrupted, /time_limit/)
    expect(transport.delays).to be_empty
    expect(transport.lines).not_to be_empty
  end

  it 'checks hold before polling a buffered response' do
    transport.quick_guard = guard
    transport.lines << 'response'
    snapshot[:control] = :held
    expect { transport.send(:get?) }.to raise_error(BigshotQuickIOSpec::QuickGuard::Interrupted, /held/)
    expect(transport.lines).to eq(['response'])
  end
end
