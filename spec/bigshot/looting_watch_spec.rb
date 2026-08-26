# Spec for bigshot.lic's looting_watch pause handling.
#
# We do NOT load the .lic file: it needs the whole Lich runtime (Settings,
# XMLData, Spell, GTK, DRb ...). Instead the real method body is extracted
# from scripts/bigshot.lic and evaluated against stubs (same technique as
# spec/bigshot/priority_spec.rb), so this spec exercises production code and
# fails if that code's shape changes.
#
# Regression covered: looting_watch used to check only the *watched* script's
# (eloot's) pause state, never bigshot's own. When something (e.g. ecleanse)
# paused bigshot and eloot back-to-back, looting_watch would notice eloot's
# pause and return to its caller immediately, without regard for bigshot's
# own pause - letting bigshot's thread run one more loop iteration and race
# eloot's independently-resumed thread over the next corpse. The fix adds
# `Script.current` at the top of the loop, which is the idiom lich-5 uses
# elsewhere (echo, fput, ...) to block on the calling script's own pause.
#
# The stub Script.current models that blocking with a real Mutex/
# ConditionVariable rather than sleep-based polling, and the spec
# rendezvouses with the background thread through Queues so the assertions
# are deterministic instead of racing real wall-clock timing.

module BigshotLootingWatchSpec
  SOURCE_PATH = File.expand_path('../../scripts/bigshot.lic', __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")

  LOOTING_WATCH_SRC = SOURCE[/^  def looting_watch\(script_ran\).*?^  end$/m] or
    raise 'could not extract looting_watch from bigshot.lic'

  ScriptRef = Struct.new(:name)
  Item = Struct.new(:type)

  # Stand-in for Lich's Script class. #current models bigshot's own pause
  # enforcement (Script#wait_while_paused!) with a Mutex/ConditionVariable:
  # it blocks while the "self" script (bigshot) is paused, and pushes onto
  # an optional queue right before it starts waiting, so a spec can
  # rendezvous with that moment instead of guessing at timing.
  class ScriptRegistry
    def initialize(self_name:)
      @self_name = self_name
      @mutex = Mutex.new
      @cv = ConditionVariable.new
      @entries = {}
      @current_calls = 0
      @killed = []
    end

    attr_accessor :waiting_queue
    attr_reader :current_calls, :killed

    def add(name, paused: false, running: true)
      @entries[name] = { paused: paused, running: running }
    end

    def pause(name)
      @mutex.synchronize { @entries.fetch(name)[:paused] = true }
    end

    def unpause(name)
      @mutex.synchronize do
        @entries.fetch(name)[:paused] = false
        @cv.broadcast
      end
    end

    def paused?(name)
      @entries.fetch(name)[:paused]
    end

    def running?(name)
      @entries.fetch(name)[:running]
    end

    def kill(name)
      @entries.fetch(name)[:running] = false
      @killed << name
    end

    def current
      @mutex.synchronize do
        @current_calls += 1
        if @entries.fetch(@self_name)[:paused]
          @waiting_queue&.push(:waiting)
          @cv.wait(@mutex) while @entries.fetch(@self_name)[:paused]
        end
      end
      self
    end
  end

  module Harness
    module GameObj
      class << self
        attr_accessor :right_hand, :left_hand
      end
    end

    module Script
      class << self
        attr_accessor :registry

        def current
          registry.current
        end

        def paused?(name)
          registry.paused?(name)
        end

        def running?(name)
          registry.running?(name)
        end

        def kill(name)
          registry.kill(name)
        end
      end
    end

    class Runner
      eval(BigshotLootingWatchSpec::LOOTING_WATCH_SRC)
    end
  end
end

RSpec.describe 'bigshot looting_watch' do
  include BigshotLootingWatchSpec

  let(:registry) { BigshotLootingWatchSpec::ScriptRegistry.new(self_name: 'bigshot') }
  let(:eloot) { BigshotLootingWatchSpec::ScriptRef.new('eloot') }
  let(:runner) { BigshotLootingWatchSpec::Harness::Runner.new }

  before do
    registry.add('bigshot')
    registry.add('eloot')
    BigshotLootingWatchSpec::Harness::Script.registry = registry
    BigshotLootingWatchSpec::Harness::GameObj.right_hand = BigshotLootingWatchSpec::Item.new('')
    BigshotLootingWatchSpec::Harness::GameObj.left_hand = BigshotLootingWatchSpec::Item.new('')
    $bigshot_should_rest = false
    $rest_reason = nil
  end

  after do
    $bigshot_should_rest = false
    $rest_reason = nil
  end

  it 'blocks on its own (bigshot) pause even while the watched script is also paused, ' \
     'and only returns once bigshot is unpaused' do
    registry.pause('bigshot')
    registry.pause('eloot')

    waiting = Queue.new
    returned = Queue.new
    registry.waiting_queue = waiting

    thread = Thread.new do
      runner.looting_watch(eloot)
      returned.push(:done)
    end

    waiting.pop # blocks until the thread is parked inside Script.current

    expect(returned).to be_empty
    expect(registry.killed).to be_empty

    registry.unpause('bigshot')
    returned.pop # blocks until looting_watch actually returns

    thread.join
    # eloot is paused but idle (no box in hand, no rest flag), so the loop
    # exits without killing it - matches the pre-fix behavior for this half
    # of the condition once bigshot's own pause is no longer in the way.
    expect(registry.killed).to be_empty
  end

  it 'still breaks immediately on the watched script pausing when bigshot itself was never paused' do
    registry.pause('eloot')

    runner.looting_watch(eloot)

    expect(registry.current_calls).to eq(1)
    expect(registry.killed).to be_empty
  end

  it 'kills the watched script when it stops running, independent of pause state' do
    registry.unpause('eloot')
    registry.kill('eloot')

    runner.looting_watch(eloot)

    expect(registry.current_calls).to eq(1)
  end

  it 'sets $bigshot_should_rest and the box reason when a box is in hand and eloot is paused' do
    registry.pause('eloot')
    BigshotLootingWatchSpec::Harness::GameObj.right_hand = BigshotLootingWatchSpec::Item.new('box')

    runner.looting_watch(eloot)

    expect($bigshot_should_rest).to be true
    expect($rest_reason).to eq("Box in hand, couldn't store")
    expect(registry.killed).to eq(['eloot'])
  end

  it 'kills the watched script when $bigshot_should_rest is already set and it is still running' do
    registry.unpause('eloot')
    $bigshot_should_rest = true

    runner.looting_watch(eloot)

    expect(registry.killed).to eq(['eloot'])
  end
end
