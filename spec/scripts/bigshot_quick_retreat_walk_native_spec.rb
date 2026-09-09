# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

# Optional isolated integration using real Map static Dijkstra, global move/fput,
# Script execution scope/waits and Game socket admission. Rooms and server output
# are fixtures; no scripts are launched and no live socket/map files are used.
module BigshotQuickWalkNativeSpec
  PROBE = <<~'RUBY'
    require 'json'
    require 'set'
    require 'timeout'
    LIB_DIR = File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib')
    $LOAD_PATH.unshift(LIB_DIR)
    require 'common/script'
    require 'common/limitedarray'
    require 'common/sharedbuffer'
    require 'common/xmlparser'
    require 'common/gameobj'
    require 'common/class_exts/stringproc'
    require 'common/map/map_gs'
    require 'common/detachable_client_registry'
    require 'games'
    require 'global_defs'
    Object.include Lich::Common
    XMLData = Lich::Common::XMLParser.new
    XMLData.instance_variable_set(:@game, 'GSIV')
    Game = Lich::GameBase::Game
    scenario = ARGV.fetch(1)
    owner = Script.allocate
    owner.instance_variable_set(:@name, 'bigshot')
    owner.instance_variable_set(:@silent, true)
    owner.instance_variable_set(:@downstream_buffer, LimitedArray.new)
    owner.want_downstream = true
    owner.want_downstream_xml = false
    Script.define_singleton_method(:current) { owner }
    Script.define_singleton_method(:__resolve_current) { owner }
    Script.define_singleton_method(:list) { [owner] }
    Script.define_singleton_method(:start) { |*| raise 'Unexpected child script launch' }
    module Probe
    end
    source = File.read(ARGV.fetch(0)).gsub("\r\n", "\n")
    %w[EncounterPolicy QuickRetreatWalk].each do |name|
      body = source[/^  class #{name}\n.*?^  end$/m]
      raise "Missing #{name}" unless body
      Probe.module_eval(body)
    end
    Map.class_variable_set(:@@loaded, true)
    Map.class_variable_set(:@@list, [])
    rooms = [100, 150, 200].to_h do |id|
      [id, Map.new(id, ["Fixture #{id}"], ['Fixture room'], ['Obvious exits: north'])]
    end
    rooms[100].wayto['150'], rooms[100].timeto['150'] = 'north', 0.5
    rooms[150].wayto['200'], rooms[150].timeto['200'] = 'go gate', 0.5
    # A tempting cheaper custom edge must never run or win static routing.
    rooms[100].wayto['200'] = StringProc.new('raise "Custom wayto was executed"')
    rooms[100].timeto['200'] = StringProc.new('raise "Custom timeto was executed"')
    rooms[100].wayto.delete('150') if scenario == 'custom_only'
    world = { session: 'login', room_id: 100, room_epoch: 1, stable: true,
              owner: true, connected: true, alive: true, destination_safe: false }
    XMLData.instance_variable_set(:@room_count, 1)
    writes, attempts, workers = [], Hash.new(0), []
    socket = Object.new
    socket.define_singleton_method(:puts) do |wire|
      writes << wire
      command = wire.delete_prefix('<c>')
      attempts[command] += 1
      response = if scenario == 'cancel_wait' && command == 'north'
                   workers << Thread.new { sleep 0.03; world[:escape_cancelled] = 'manual_stop' }
                   'Wait 3 seconds.'
                 elsif scenario == 'inventory' && command == 'north'
                   'You notice a sword at your feet, and do not wish to leave it behind'
                 elsif scenario.include?('retry') && command == 'north' && attempts[command] == 1
                   'Wait 1 seconds.'
                 elsif scenario == 'stand_open' && command == 'north' && attempts[command] == 1
                   'You must be standing to do that'
                 elsif scenario == 'stand_open' && command == 'go gate' && attempts[command] == 1
                   'The gate appears to be closed.'
                 elsif %w[stand].include?(command) || command == 'open gate'
                   'Done.'
                 else
                   raise "Unexpected native command #{wire.inspect}" unless ['north', 'go gate'].include?(command)
                   world[:room_id] = scenario == 'unexpected' ? 999 : (command == 'north' ? 150 : 200)
                   world[:room_epoch] += 1
                   world[:destination_safe] = world[:room_id] == 200
                   XMLData.instance_variable_set(:@room_count, world[:room_epoch])
                   'Obvious exits: north'
                 end
      owner.downstream_buffer.push(response)
    end
    Game.instance_variable_set(:@socket, socket)
    Game.instance_variable_set(:@mutex, Mutex.new)
    $_CLIENTBUFFER_ = LimitedArray.new
    $cmd_prefix = '<c>'
    adapter = Probe::QuickRetreatWalk.new(
      { 'max_actions' => scenario == 'retry_budget' ? 2 : 8, 'max_seconds' => 2 },
      destinations: ['200'], owner: owner, prefix: '<c>', movement: ->(command) { move(command) }, map: Map
    )
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Timeout.timeout(5) do
      if scenario == 'unguarded_retry'
        { outcome: move('north') == true ? :moved : :failed }
      else
        adapter.call { world.dup }
      end
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    workers.each(&:join)
    puts JSON.generate(result.merge(writes: writes, room: world[:room_id], elapsed: elapsed,
                                     scope: owner.execution_guard_active?,
                                     routes: [rooms[100].wayto['150'], rooms[150].wayto['200']]))
  RUBY
end

RSpec.describe 'Quick walking retreat through native Lich pathfinding and movement' do
  before do
    skip 'Set LICH_EXECUTION_GUARD_ROOT for native walking retreat integration' unless ENV['LICH_EXECUTION_GUARD_ROOT']
  end

  def probe(scenario)
    output, error, status = Open3.capture3(
      RbConfig.ruby, '-', File.expand_path('../../scripts/bigshot.lic', __dir__), scenario,
      stdin_data: BigshotQuickWalkNativeSpec::PROBE
    )
    expect(status.success?).to be(true), "Native walk probe failed:\n#{output}\n#{error}"
    JSON.parse(output).tap { |result| expect(result.fetch('scope')).to be(false) }
  end

  it 'walks two static edges to a verified refuge without running cheaper custom map code' do
    expect(probe('normal')).to include('outcome' => 'retreated', 'room' => 200, 'sends' => 2,
                                       'writes' => ['<c>north', '<c>go gate'], 'routes' => ['north', 'go gate'])
  end

  it 'counts the actual native movement retry' do
    expect(probe('retry')).to include('outcome' => 'retreated', 'sends' => 3,
                                      'writes' => ['<c>north', '<c>north', '<c>go gate'])
  end

  it 'enforces the action budget across native movement retries and later edges' do
    expect(probe('retry_budget')).to include('outcome' => 'unconfirmed', 'reason' => 'retreat_action_limit',
                                             'sends' => 2, 'room' => 150, 'writes' => ['<c>north', '<c>north'])
  end

  it 'preserves an ordinary unguarded native movement retry and its sleep' do
    result = probe('unguarded_retry')
    expect(result).to include('outcome' => 'moved', 'room' => 150, 'writes' => ['<c>north', '<c>north'])
    expect(result.fetch('elapsed')).to be >= 0.25
  end

  it 'counts native stand and open recovery plus repeated movement sends' do
    expect(probe('stand_open')).to include('outcome' => 'retreated', 'sends' => 6,
                                           'writes' => ['<c>north', '<c>stand', '<c>north', '<c>go gate', '<c>open gate', '<c>go gate'])
  end

  it 'interrupts a native three-second retry wait before another socket send' do
    result = probe('cancel_wait')
    expect(result).to include('outcome' => 'unconfirmed', 'reason' => 'manual_stop', 'sends' => 1, 'writes' => ['<c>north'])
    expect(result.fetch('elapsed')).to be < 0.5
  end

  it 'fails unexpected displacement instead of taking the next route edge' do
    expect(probe('unexpected')).to include('outcome' => 'unconfirmed', 'reason' => 'retreat_unexpected_displacement',
                                           'room' => 999, 'sends' => 1, 'writes' => ['<c>north'])
  end

  it 'rejects a native inventory recovery send before it reaches the socket' do
    expect(probe('inventory')).to include('outcome' => 'unconfirmed', 'reason' => 'retreat_command_denied',
                                          'sends' => 1, 'writes' => ['<c>north'])
  end

  it 'does not fall back to custom map code when no static route exists' do
    expect(probe('custom_only')).to include('outcome' => 'unconfirmed', 'reason' => 'retreat_route_unavailable',
                                            'sends' => 0, 'writes' => [])
  end
end
