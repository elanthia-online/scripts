# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

module BigshotQuickELootNativeSpec
  # Real Script.start_child, worker ownership, cleanup/join, execution scope and
  # Game socket boundary. The child is a definitions-only fixture API, not a
  # claim that this test exercises eLoot's inventory algorithms.
  PROBE = <<~'RUBY'
    require 'json'
    require 'set'
    require 'tmpdir'
    require 'fileutils'
    LIB_DIR = File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib')
    $LOAD_PATH.unshift(LIB_DIR)
    %w[common/script common/limitedarray common/sharedbuffer common/detachable_client_registry games].each { |file| require file }
    Object.include Lich::Common
    module Lich
      def self.log(_message); end
    end
    def respond(*); end
    Game = Lich::GameBase::Game
    LOADER_BARRIER = Queue.new
    LOAD_OBSERVATIONS = []
    API_OBSERVATIONS = []
    mode = ARGV.fetch(1)
    source = File.read(ARGV.fetch(0)).gsub("\r\n", "\n")
    module Probe; end
    %w[QuickGuard QuickIO QuickExecution].each do |name|
      Probe.module_eval(source[/^  (?:class|module) #{name}\n.*?^  end$/m])
    end
    class Probe::Engine
      include Probe::QuickIO
      include Probe::QuickExecution
    end
    writes = []
    socket = Object.new
    socket.define_singleton_method(:puts) { |wire| writes << wire }
    Game.instance_variable_set(:@socket, socket)
    Game.instance_variable_set(:@mutex, Mutex.new)
    $_CLIENTBUFFER_ = LimitedArray.new
    $cmd_prefix = '>'
    Dir.mktmpdir('quick-eloot-native') do |root|
      Object.const_set(:SCRIPT_DIR, root)
      FileUtils.mkdir_p(File.join(root, 'custom'))
      definitions = <<~SOURCE
        # quiet
        LOAD_OBSERVATIONS << [Script.current.vars[0], Script.current.execution_guard_active?]
        #{mode == 'hold' ? 'LOADER_BARRIER.pop' : ''}
        #{mode == 'failure' ? "raise 'loader fixture failed'" : ''}
        module ELoot
          ROOM_LOOT_API_VERSION = 1
          def self.restore_room_hands(owner:)
            owner.want_downstream, owner.want_downstream_xml = false, true
            Game._puts('>put #789 in #987')
            Game._puts('>stand')
            { outcome: :complete }.freeze
          end
          def self.room_loot(corpse_ids:, floor:, owner:, script_name:, recoverable:)
            raise 'wrong owner' unless Script.current.equal?(owner) && owner.execution_guard_active?
            API_OBSERVATIONS << [owner.object_id, Thread.current.object_id, corpse_ids, floor, script_name]
            owner.want_downstream, owner.want_downstream_xml = false, true
            Game._puts('>inventory')
            Game._puts('>search #123')
            #{%w[recovery window].include?(mode) ? "10.times { Game._puts('>skin #123') }" : ''}
            { outcome: :complete }.freeze
          end
        end
      SOURCE
      File.write(File.join(root, 'custom', 'eloot.lic'), definitions)
      children = []
      native_start = Script.method(:start_child)
      Script.define_singleton_method(:start_child) do |*args|
        child = native_start.call(*args)
        children << child
        child.join(2) if child && mode == 'fast'
        child
      end
    result, reason, owner_id, owner_thread, flags, sends, recovery, cancelled_reason = nil
      parent = Script.subscript do
        owner = Script.current
        owner_id, owner_thread = owner.object_id, Thread.current.object_id
        identity = { session: 'login', room_id: 100, room_epoch: 1, target_id: 'loot' }
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        guard = Probe::QuickGuard.new(identity: identity, max_sends: 5, max_seconds: 3, snapshot: lambda {
          control = mode == 'hold' && Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 0.1 ? :held : :running
          expired = 'operation_work_deadline' if mode == 'window' && writes.length >= 2
          identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: control, operation_expired: expired)
        })
        begin
          engine = Probe::Engine.new
          result = engine.quick_loot_execute('loot #123', guard: guard, owner: owner, prefix: '>')
        rescue Probe::QuickGuard::Interrupted => error
          reason = error.reason
          if (mode == 'recovery' && reason == 'command_limit') || (mode == 'window' && reason == 'operation_work_deadline')
            restore_guard = Probe::QuickGuard.new(identity: identity, max_sends: 2, max_seconds: 3,
              snapshot: -> { identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running) })
            recovery = engine.quick_loot_restore(guard: restore_guard, owner: owner, prefix: '>')
            begin
              guard.checkpoint!
            rescue Probe::QuickGuard::Interrupted => original
              cancelled_reason = original.reason
            end
          end
        rescue StandardError => error
          reason = error.message
        ensure
          flags = [owner.want_downstream, owner.want_downstream_xml, owner.execution_guard_active?]
          sends = guard.sends
        end
      end
      raise 'parent did not finish' unless parent.join(8)
      puts JSON.generate(result: result, reason: reason, writes: writes, sends: sends, flags: flags,
                         recovery: recovery, cancelled_reason: cancelled_reason,
                         loader: LOAD_OBSERVATIONS, calls: API_OBSERVATIONS, owner: owner_id, thread: owner_thread,
                         children: children.map { |child| [child&.running?, !!child&.join(0)] },
                         remaining: Script.list.map(&:name), parent_success: parent.completed_successfully?)
    end
  RUBY
end

RSpec.describe 'Quick native definitions-child lifecycle' do
  before { skip 'Set LICH_EXECUTION_GUARD_ROOT for native eLoot loader integration' unless ENV['LICH_EXECUTION_GUARD_ROOT'] }

  def probe(mode)
    output, error, status = Open3.capture3(RbConfig.ruby, '-', File.expand_path('../../scripts/bigshot.lic', __dir__), mode,
                                           stdin_data: BigshotQuickELootNativeSpec::PROBE)
    expect(status.success?).to be(true), "Native loader probe failed:\n#{output}\n#{error}"
    JSON.parse(output).tap do |result|
      expect(result).to include('children' => [[false, true]], 'remaining' => [], 'flags' => [true, false, false], 'parent_success' => true)
      expect(result['loader']).to eq([['--load-room-api', false]])
    end
  end

  it 'accepts a fast already-joined child and executes the loaded API on its exact guarded parent' do
    result = probe('fast')
    expect(result).to include('result' => { 'outcome' => 'complete', 'sends' => 2 }, 'writes' => ['>inventory', '>search #123'])
    expect(result['calls']).to eq([[result['owner'], result['thread'], ['123'], false, 'eloot']])
  end

  it 'cancels and joins a blocked definitions child before reporting hold without any game send' do
    expect(probe('hold')).to include('reason' => 'held', 'calls' => [], 'writes' => [], 'sends' => 0)
  end

  it 'uses a separate bounded recovery scope without reviving the cancelled work guard' do
    result = probe('recovery')
    expect(result).to include('reason' => 'command_limit', 'sends' => 5, 'cancelled_reason' => 'command_limit',
                              'recovery' => { 'outcome' => 'complete', 'sends' => 2 })
    expect(result['writes'].last(2)).to eq(['>put #789 in #987', '>stand'])
    expect(result['writes'].size).to eq(7)
  end

  it 'rejects a failed child without calling its API or leaving its worker alive' do
    result = probe('failure')
    expect(result['reason']).to match(/room API version 1/)
    expect(result).to include('calls' => [], 'writes' => [], 'sends' => 0)
  end

  it 'propagates the work cutoff through native I/O and permits only the recovery scope afterward' do
    result = probe('window')
    expect(result).to include('reason' => 'operation_work_deadline', 'sends' => 2,
                              'cancelled_reason' => 'operation_work_deadline',
                              'recovery' => { 'outcome' => 'complete', 'sends' => 2 })
    expect(result['writes']).to eq(['>inventory', '>search #123', '>put #789 in #987', '>stand'])
  end
end
