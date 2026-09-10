# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

# Source-extracted actual cmd/cmd_tether, native Spell/Script and Game transport.
# Only character state and socket responses are synthetic; no live connection.
module BigshotQuickTetherSpec
  SOURCE = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  class Admission; end
  admission_source = SOURCE[/^    def self.command_supported!\(command\)\n.*?^    end$/m]
  raise 'could not extract command_supported!' unless admission_source

  Admission.class_eval(admission_source)

  class LegacyTetherHarness
    class Spell706
      attr_reader :casts

      def initialize
        @casts = 0
      end

      def known? = true
      def affordable? = true

      def force_incant(*)
        @casts += 1
        'The tenebrous chains dissolve into black mist.'
      end
    end

    TETHER_SPELL = Spell706.new
    Spell = Object.new
    Spell.define_singleton_method(:[]) { |number| number == 706 ? TETHER_SPELL : nil }

    def initialize
      @quick_native_scope = false
    end

    def debug_msg(*); end
    def dead_or_gone?(*) = false
    def still_targetable?(*) = true
    def waitrt?; end
    def waitcastrt?; end
    def get = nil
    def should_flee? = true
    def standing? = true
    def stand; end
    def sleep(*); end

    tether_source = BigshotQuickTetherSpec::SOURCE[/^  def cmd_tether\(npc, recast_on_transfer = false\)\n.*?^  end$/m]
    raise 'could not extract cmd_tether' unless tether_source

    class_eval(tether_source)
  end

  PROBE = <<~'RUBY'
    require 'json'
    require 'set'
    require 'timeout'
    LIB_DIR = File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib')
    $LOAD_PATH.unshift(LIB_DIR)
    %w[common/script common/limitedarray common/sharedbuffer common/xmlparser common/gameobj
       common/spell common/detachable_client_registry games global_defs].each { |file| require file }
    Object.include Lich::Common
    XMLData = Lich::Common::XMLParser.new
    XMLData.instance_variable_set(:@game, 'GSIV')
    Game = Lich::GameBase::Game
    Char = Struct.new(:name, :mana, :stamina, :spirit, :stance).new('Probe', 100, 100, 10, 'guarded')
    module Feat
      def self.known?(_name) = false
    end
    module Effects
      module Spells
        def self.active?(_name) = false
      end
    end
    scenario = ARGV.fetch(1)
    owner = Script.allocate
    owner.instance_variable_set(:@name, 'bigshot')
    owner.instance_variable_set(:@silent, true)
    owner.instance_variable_set(:@downstream_buffer, LimitedArray.new)
    owner.want_downstream, owner.want_downstream_xml = true, false
    Script.define_singleton_method(:current) { owner }
    Script.define_singleton_method(:__resolve_current) { owner }
    Script.define_singleton_method(:list) { [owner] }
    spell = Spell.allocate
    { num: 706, name: 'Tether', type: 'attack', circle: '7', stance: false,
      channel: false, no_incant: false }.each { |key, value| spell.instance_variable_set("@#{key}", value) }
    { known?: scenario != 'unknown', affordable?: scenario != 'unaffordable', active?: false,
      mana_cost: 1, stamina_cost: 0, spirit_cost: 0 }.each { |key, value| spell.define_singleton_method(key) { value } }
    inactive = Object.new
    inactive.define_singleton_method(:known?) { false }
    Spell.define_singleton_method(:[]) { |number| number == 706 ? spell : inactive }
    source = File.read(ARGV.fetch(0)).gsub("\r\n", "\n")
    module Probe; end
    %w[QuickGuard QuickIO QuickExecution].each do |name|
      body = source[/^  (?:class|module) #{name}\n.*?^  end$/m]
      raise "Missing #{name}" unless body
      Probe.module_eval(body)
    end
    class Probe::Engine
      include Probe::QuickIO
      include Probe::QuickExecution
      attr_accessor :wait_entered
      def initialize
        @COMMANDS_REGISTRY, @OOM = {}, 0
        initialize_command_data
      end
      def debug_msg(*); end
      def check_for_deaders_prone; end
      def escape_rooms; end
      def change_stance(*); end
      def dead_or_gone?(_target) = false
      def still_targetable?(_id) = true
      def valid_target?(_target) = true
      def standing? = true
      def should_flee?
        wait_entered << true if wait_entered && wait_entered.empty?
        false
      end
    end
    %w[cmd initialize_command_data command_check check_state_condition once_commands_register
       repeatdelay_blocked? bs_put cmd_tether reset_variables].each do |name|
      body = source[/^  def #{Regexp.escape(name)}(?:\([^\n]*\))?[^\n]*\n.*?^  end$/m]
      raise "Missing production #{name}" unless body
      Probe::Engine.class_eval(body)
    end
    select = lambda do |id|
      Ox.sax_parse(XMLData, "<dropDownBox id=\"dDBTarget\" content_value=\"##{id}\"/>",
                   convert_special: false, symbolize: false, skip: :skip_none)
    end
    select.call('777')
    writes, casts = [], 0
    socket = Object.new
    socket.define_singleton_method(:puts) do |wire|
      writes << wire
      command = wire.delete_prefix('<c>')
      response = if command.start_with?('target #')
                   select.call(command.delete_prefix('target #'))
                   'You are now targeting an ogre.'
                 elsif command == 'incant 706'
                   casts += 1
                   select.call('999') if scenario.include?('drift') && casts == 1
                   if scenario.include?('hindrance')
                     '[Spell Hindrance for fixture]'
                   elsif casts == 1 && %w[retry preparation_drift budget].include?(scenario)
                     '[Spell preparation time: 0 seconds]'
                   elsif %w[immediate legacy].include?(scenario)
                     'The tenebrous chains dissolve into black mist.'
                   else
                     'Cast Roundtime 3 Seconds.'
                   end
                 else
                   raise "Unexpected native wire #{wire.inspect}"
                 end
      owner.downstream_buffer.push(response)
      if response == 'Cast Roundtime 3 Seconds.'
        owner.downstream_buffer.push('The tenebrous chains dissolve into black mist.') unless %w[cancel timeout broken recast].include?(scenario)
        owner.downstream_buffer.push('You feel your connection to the dark presence fade away.') if scenario == 'broken'
      end
    end
    Game.instance_variable_set(:@socket, socket)
    Game.instance_variable_set(:@mutex, Mutex.new)
    $_CLIENTBUFFER_ = LimitedArray.new
    $cmd_prefix = '<c>'
    identity = { session: 'login', room_id: 42, room_epoch: 1, target_id: '123' }
    observed = identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running)
    guard = Probe::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                                  max_sends: scenario == 'budget' ? 2 : 10, max_seconds: scenario == 'timeout' ? 0.2 : 2)
    engine = Probe::Engine.new
    cancel_queue = Queue.new
    if scenario == 'cancel'
      engine.wait_entered = cancel_queue
      canceller = Thread.new { cancel_queue.pop; observed[:control] = :held }
    end
    # Detect reader creation rather than relying only on eventual thread exit.
    spawned = []
    original_new = Thread.method(:new)
    Thread.define_singleton_method(:new) { |*args, &block| original_new.call(*args, &block).tap { |thread| spawned << thread } }
    begin
      result = Timeout.timeout(4) do
        target = Struct.new(:id, :name, :noun).new('123', 'ogre', 'ogre')
        if scenario == 'legacy'
          engine.cmd('tether', target)
        else
          engine.quick_execute(scenario == 'recast' ? 'tether recast' : 'tether',
                               target, guard: guard, owner: owner, prefix: '<c>')
        end
      end
    rescue Probe::QuickGuard::Interrupted => error
      reason = error.reason
    ensure
      cancel_queue << true
      canceller&.join(1)
    end
    # Timeout has its own watchdog; only helper-created readers are forbidden.
    readers = spawned.reject { |thread| thread.name.to_s.include?('Timeout') }
    puts JSON.generate(writes: writes, casts: casts, result: result, reason: reason, sends: guard.sends,
                       reader_count: readers.length, reader_alive: readers.any?(&:alive?),
                       cast_lock: Spell.class_variable_get(:@@cast_lock).include?(owner),
                       native_scope: owner.execution_guard_active?, selector_scope: engine.instance_variable_get(:@quick_incant_selector),
                       stream_flags: [owner.want_downstream, owner.want_downstream_xml])
  RUBY
end

RSpec.describe 'Quick plain tether admission' do
  it 'admits the selected-target helper with existing modifiers and wrappers' do
    ['tether', 'TETHER(once)', 'force tether until 2', '506 tether'].each do |command|
      expect(BigshotQuickTetherSpec::Admission.command_supported!(command)).to be(true)
    end
  end

  it 'rejects recast and extra arguments before any native execution' do
    ['tether recast', 'tether #123', 'tether target', 'tether Fred', 'tethered', 'force tether recast until 2'].each do |command|
      expect { BigshotQuickTetherSpec::Admission.command_supported!(command) }.to raise_error(ArgumentError, /single selected target/)
    end
  end
end

RSpec.describe 'Legacy tether helper' do
  it 'keeps the ordinary non-Quick cast path executable without native guard support' do
    target = Struct.new(:id).new('123')
    spell = BigshotQuickTetherSpec::LegacyTetherHarness::TETHER_SPELL
    before = spell.casts
    BigshotQuickTetherSpec::LegacyTetherHarness.new.cmd_tether(target)
    expect(spell.casts).to eq(before + 1)
  end
end

RSpec.describe 'Quick plain tether through native Spell and owner-thread completion' do
  before { skip 'Set LICH_EXECUTION_GUARD_ROOT for native tether integration' unless ENV['LICH_EXECUTION_GUARD_ROOT'] }

  def probe(scenario)
    source = File.expand_path('../../../scripts/bigshot.lic', __dir__)
    output, error, status = Open3.capture3(RbConfig.ruby, '-', source, scenario, stdin_data: BigshotQuickTetherSpec::PROBE)
    expect(status.success?).to be(true), "Native tether probe failed:\n#{output}\n#{error}"
    JSON.parse(output).tap do |result|
      expect(result).to include('reader_count' => 0, 'reader_alive' => false, 'cast_lock' => false,
                                'native_scope' => false, 'selector_scope' => nil, 'stream_flags' => [true, false])
    end
  end

  it 'confirms the exact selector and completes on immediate, delayed, or broken tether messages' do
    %w[normal immediate broken].each do |scenario|
      expect(probe(scenario)).to include('writes' => ['<c>target #123', '<c>incant 706'], 'sends' => 2, 'reason' => nil)
    end
  end

  it 'preserves native preparation retry and the five-hindrance ceiling' do
    expect(probe('retry')).to include('casts' => 2, 'sends' => 3, 'reason' => nil)
    expect(probe('hindrance')).to include('casts' => 5, 'sends' => 6, 'reason' => nil)
  end

  it 'rejects selector drift during native preparation and between outer hindrance attempts' do
    %w[preparation_drift hindrance_drift].each do |scenario|
      expect(probe(scenario)).to include('casts' => 1, 'sends' => 2, 'reason' => 'incant_selector_changed')
    end
  end

  it 'bounds retries and completion waits and cooperatively cancels without a reader leak' do
    expect(probe('budget')).to include('casts' => 1, 'sends' => 2, 'reason' => 'command_limit')
    expect(probe('cancel')).to include('casts' => 1, 'reason' => 'held')
    expect(probe('timeout')).to include('casts' => 1, 'reason' => 'time_limit')
  end

  it 'keeps ineligible skips silent and refuses recast before any sends' do
    %w[unknown unaffordable].each { |scenario| expect(probe(scenario)).to include('writes' => [], 'sends' => 0) }
    expect(probe('recast')).to include('writes' => [], 'reason' => 'tether_recast_unsupported')
  end
end
