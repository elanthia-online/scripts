# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

# Production Bigshot go2 delegation, native child startup/teardown and Game
# socket guard. The go2 body and world are fixtures, not live navigation proof.
module BigshotQuickGo2NativeSpec
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
      def self.log(*); end
    end
    def respond(*messages); warn(messages.join("\n")); end
    Game = Lich::GameBase::Game
    source = File.read(ARGV.fetch(0)).gsub("\r\n", "\n")
    mode = ARGV.fetch(1)
    module Probe; end
    Probe.module_eval(source[/^  class QuickGo2Travel\n.*?^  end$/m])
    class Probe::Engine
      def debug_msg(*); end
    end
    Probe::Engine.class_eval(source[/^  def go2\(.*?^  end$/m])
    WORLD = { session: 'fixture', room_id: 100, room_epoch: 1, stable: true, alive: true, connected: true, owner: true }
    writes = []
    socket = Object.new
    socket.define_singleton_method(:puts) do |wire|
      writes << wire
      WORLD[:room_id] += 1
      WORLD[:room_epoch] += 1
      WORLD[:owner] = false if mode == 'revoke'
    end
    Game.instance_variable_set(:@socket, socket)
    Game.instance_variable_set(:@mutex, Mutex.new)
    $_CLIENTBUFFER_ = LimitedArray.new
    $cmd_prefix = '>'
    map = Object.new
    map.define_singleton_method(:[]) { |_| true }
    result = nil
    owner = nil
    Dir.mktmpdir('quick-go2-native') do |root|
      Object.const_set(:SCRIPT_DIR, root)
      FileUtils.mkdir_p(File.join(root, 'custom'))
      File.write(File.join(root, 'custom', 'go2.lic'), <<~SOURCE)
        # quiet
        if #{mode.start_with?('nested') } && !$probe_spawn_attempted
          $probe_spawn_attempted = true
          WORLD[:owner] = false if #{mode == 'nested_revoke'}
          Script.run('go2', { force: true })
        end
        Script.current.at_exit_procs << proc { Game._puts('>north') } if #{mode == 'denied'}
        #{mode == 'denied' ? "Game._puts('>withdraw 1000 silvers')" : ''}
        #{mode == 'empty' ? 0 : 32}.times { Game._puts('>north') }
      SOURCE
      parent = Script.subscript do
        owner = Script.current
        engine = Probe::Engine.new
        travel = Probe::QuickGo2Travel.new(destination: 132, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2,
          owner: owner, prefix: '>', map: map, launch: ->(id, policy) { engine.go2(id, execution_guard: policy) })
        result = travel.call do
          current = Script.current
          accepted = current.equal?(owner) || (owner.respond_to?(:quick_refuge_travel_child?) && owner.quick_refuge_travel_child?(current))
          WORLD.merge(owner: WORLD[:owner] && accepted)
        end
      end
      unless parent.join(4)
        parent.kill_sync
        raise 'native go2 test timed out'
      end
      raise 'native parent failed' unless parent.completed_successfully?
      puts JSON.generate(result.merge(writes: writes, children: owner.child_scripts.length,
        detached: Script.list.reject { |script| script.equal?(owner) }.map(&:name),
        predicate_left: owner.respond_to?(:quick_refuge_travel_child?)))
    end
  RUBY
end

RSpec.describe 'Quick refuge go2 with native Lich child and socket guards' do
  before do
    skip 'Set LICH_EXECUTION_GUARD_ROOT for native go2 handoff coverage' unless ENV['LICH_EXECUTION_GUARD_ROOT']
  end

  def probe(mode)
    output, errors, status = Open3.capture3(RbConfig.ruby, '-',
                                            File.expand_path('../../../scripts/bigshot.lic', __dir__), mode,
                                            stdin_data: BigshotQuickGo2NativeSpec::PROBE)
    expect(status.success?).to be(true), "#{output}\n#{errors}"
    JSON.parse(output).tap do |result|
      expect(result).to include('children' => 0, 'detached' => [], 'predicate_left' => false)
    end
  end

  it 'guards the first go2 send, reaches the destination and releases its exact native child' do
    expect(probe('normal')).to include('outcome' => 'retreated', 'sends' => 32, 'writes' => Array.new(32, '>north'))
  end

  it 'keeps denied native sends denied during child cleanup' do
    expect(probe('denied')).to include('outcome' => 'unconfirmed', 'sends' => 0, 'writes' => [])
  end

  it 'stops subsequent native writes after authority is revoked' do
    expect(probe('revoke')).to include('outcome' => 'unconfirmed', 'sends' => 1, 'writes' => ['>north'])
  end

  it 'does not infer arrival from a successful empty child' do
    expect(probe('empty')).to include('outcome' => 'unconfirmed', 'reason' => 'refuge_travel_arrival_unconfirmed')
  end

  it 'rejects real native recursive go2 startup before an unowned child can send' do
    expect(probe('nested')).to include('outcome' => 'unconfirmed', 'sends' => 0, 'writes' => [])
  end

  it 'cannot escape revoked authority by starting another native go2' do
    expect(probe('nested_revoke')).to include('outcome' => 'unconfirmed', 'sends' => 0, 'writes' => [])
  end
end
