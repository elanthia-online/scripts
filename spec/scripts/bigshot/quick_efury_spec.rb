# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'
require_relative '../../support/bigshot_quick_native_cmd_support'

module BigshotQuickEfurySpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  class Admission; end
  Admission.class_eval(source[/^    def self.command_supported!\(command\)\n.*?^    end$/m])
  class Engine < BigshotQuickNativeCmdSpec::Engine
    Spell = BigshotQuickNativeCmdSpec::Spell
  end
  Engine.class_eval(source[/^  def cmd_efury\(npc, extra\)\n.*?^  end$/m])

  # Native Script, Spell, selector XML and socket admission run in an isolated
  # process. Only server output, character resources and elapsed cast time are
  # synthetic. No installed character or live connection is used.
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
    owner = Script.allocate
    owner.instance_variable_set(:@name, 'bigshot')
    owner.instance_variable_set(:@silent, true)
    owner.instance_variable_set(:@downstream_buffer, LimitedArray.new)
    owner.want_downstream = true
    owner.want_downstream_xml = false
    Script.define_singleton_method(:current) { owner }
    Script.define_singleton_method(:__resolve_current) { owner }
    Script.define_singleton_method(:list) { [owner] }
    scenario = ARGV.fetch(1)
    spell = Spell.allocate
    { num: 917, name: 'Earthen Fury', type: 'attack', circle: '9', stance: false,
      channel: false, no_incant: false }.each { |key, value| spell.instance_variable_set("@#{key}", value) }
    { known?: scenario != 'unknown', affordable?: scenario != 'unaffordable', active?: false,
      mana_cost: 1, stamina_cost: 0, spirit_cost: 0 }.each { |key, value| spell.define_singleton_method(key) { value } }
    inactive = Object.new
    inactive.define_singleton_method(:known?) { false }
    Spell.define_singleton_method(:[]) { |number| number == 917 ? spell : inactive }
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
      attr_accessor :observed, :scenario
      attr_reader :wait_duration, :wait_result, :readers
      def initialize
        @COMMANDS_REGISTRY, @OOM, @readers = {}, 0, []
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
      def should_flee? = false
      def quick_wait_for_spell(npc, complete:, duration:)
        @wait_duration = duration
        @wait_result = super
      end
      def get?
        if @wait_duration
          @readers << Thread.current.object_id
          @observed[:control] = :held if @scenario == 'hold'
          @observed[:control] = :stopped if @scenario == 'stop'
        end
        super
      end
    end
    %w[cmd initialize_command_data command_check check_state_condition once_commands_register
       repeatdelay_blocked? bs_put cmd_efury reset_variables].each do |name|
      body = source[/^  def #{Regexp.escape(name)}(?:\([^\n]*\))?[^\n]*\n.*?^  end$/m]
      raise "Missing production #{name}" unless body
      Probe::Engine.class_eval(body)
    end
    select = lambda do |id|
      Ox.sax_parse(XMLData, "<dropDownBox id=\"dDBTarget\" content_value=\"##{id}\"/>",
                   convert_special: false, symbolize: false, skip: :skip_none)
    end
    select.call('777')
    elapsed_cast = 0.0
    native_clock = Process.method(:clock_gettime)
    Process.define_singleton_method(:clock_gettime) do |clock, *args|
      native_clock.call(clock, *args) + (clock == Process::CLOCK_MONOTONIC ? elapsed_cast : 0)
    end
    writes, casts = [], 0
    socket = Object.new
    socket.define_singleton_method(:puts) do |wire|
      writes << wire
      command = wire.delete_prefix('<c>')
      if command.start_with?('target #')
        select.call(command.delete_prefix('target #'))
        owner.downstream_buffer.push('You are now targeting an ogre.')
      elsif command.start_with?('incant 917')
        casts += 1
        select.call('999') if scenario == 'drift' && casts == 1
        if casts == 1 && %w[retry drift budget].include?(scenario)
          owner.downstream_buffer.push('[Spell preparation time: 0 seconds]')
        else
          elapsed_cast = 12.1 if scenario == 'expired'
          elapsed_cast = 11.8 if scenario == 'timeout'
          owner.downstream_buffer.push('Cast Roundtime 3 Seconds.')
          unless %w[expired timeout hold stop].include?(scenario)
            owner.downstream_buffer.push('The ground beneath an ogre suddenly calms.')
          end
        end
      else
        raise "Unexpected native wire #{wire.inspect}"
      end
    end
    Game.instance_variable_set(:@socket, socket)
    Game.instance_variable_set(:@mutex, Mutex.new)
    $_CLIENTBUFFER_ = LimitedArray.new
    $cmd_prefix = '<c>'
    identity = { session: 'login', room_id: 42, room_epoch: 1, target_id: '123' }
    observed = identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running)
    guard = Probe::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                                  max_sends: scenario == 'budget' ? 2 : 10, max_seconds: 30)
    engine = Probe::Engine.new
    engine.observed, engine.scenario = observed, scenario
    # Catch leaked readers at construction, not just after test teardown.
    Thread.define_singleton_method(:new) { |*| raise 'Unexpected helper thread' }
    begin
      command = scenario == 'cold' ? 'efurycold' : 'efury fire'
      result = engine.quick_execute(command, Struct.new(:id).new('123'), guard: guard, owner: owner, prefix: '<c>')
    rescue Probe::QuickGuard::Interrupted => error
      reason = error.reason
    end
    puts JSON.generate(writes: writes, result: result, reason: reason, sends: guard.sends,
                       selector: XMLData.current_target_id, native_scope: owner.execution_guard_active?,
                       wait_duration: engine.wait_duration, wait_result: engine.wait_result,
                       readers: engine.readers.uniq, owner_thread: Thread.current.object_id,
                       stream_flags: [owner.want_downstream, owner.want_downstream_xml])
  RUBY
end

RSpec.describe 'Quick efury helper compatibility' do
  it 'admits exact native fire/cold syntax, including concatenated legacy forms and wrappers' do
    ['efury', 'efury fire', 'efurycold', 'EFURYfire(m20)', 'force efury cold until 2', '506 efury fire'].each do |command|
      expect(BigshotQuickEfurySpec::Admission.command_supported!(command)).to be(true)
    end
    ['efury lightning', 'efury fire Fred', 'efury #123', 'efury target', 'efurycoldopen', 'efury fire cold',
     'efury 130', 'efuryfire130', 'force efury 130 until 2'].each do |command|
      expect { BigshotQuickEfurySpec::Admission.command_supported!(command) }.to raise_error(ArgumentError, /efury accepts only/)
    end
  end

  [false, true].each do |quick|
    it "retains immediate completion with quick=#{quick} without starting a later reader" do
      namespace = BigshotQuickNativeCmdSpec
      owner = namespace::Owner.new
      engine = BigshotQuickEfurySpec::Engine.new(owner)
      spell = namespace::NativeSpell.new(917, owner)
      namespace::Spell.entries = { 917 => spell }
      engine.instance_variable_set(:@quick_native_scope, quick)
      %i[debug_msg waitrt? waitcastrt?].each { |method| allow(engine).to receive(method) }
      allow(engine).to receive(:dead_or_gone?).and_return(false)
      allow(engine).to receive(:still_targetable?).and_return(true)
      expect(spell).to receive(:force_incant).with('fire').and_return('The ground beneath an ogre suddenly calms.')
      if quick
        expect(engine).to receive(:quick_incant_scope).with('123').and_yield
      else
        expect(engine).not_to receive(:quick_incant_scope)
      end
      expect(engine).not_to receive(:quick_wait_for_spell)
      expect(Thread).not_to receive(:new)
      engine.cmd_efury(Struct.new(:id).new('123'), 'fire')
      expect(owner.wires).to be_empty
    ensure
      namespace::Spell.entries = nil
    end
  end

  context 'with native Lich spell execution and socket guard' do
    before { skip 'Set LICH_EXECUTION_GUARD_ROOT for native efury integration' unless ENV['LICH_EXECUTION_GUARD_ROOT'] }

    def probe(scenario)
      output, error, status = Open3.capture3(
        RbConfig.ruby, '-', File.expand_path('../../../scripts/bigshot.lic', __dir__), scenario,
        stdin_data: BigshotQuickEfurySpec::PROBE
      )
      expect(status.success?).to be(true), "Native efury probe failed:\n#{output}\n#{error}"
      JSON.parse(output).tap do |result|
        expect(result).to include('native_scope' => false, 'stream_flags' => [true, false])
        expect(result['readers'] - [result['owner_thread']]).to be_empty
      end
    end

    it 'selects the exact NPC and consumes native completion on the owner thread' do
      expect(probe('normal')).to include('writes' => ['<c>target #123', '<c>incant 917 fire'], 'sends' => 2, 'wait_result' => 'complete')
    end

    it 'retains native cold options in concatenated profile syntax' do
      expect(probe('cold')).to include('writes' => ['<c>target #123', '<c>incant 917 cold'], 'wait_result' => 'complete')
    end

    %w[unknown unaffordable].each do |scenario|
      it "skips selection and casting when the native #{scenario} eligibility check fails" do
        expect(probe(scenario)).to include('writes' => [], 'sends' => 0, 'wait_duration' => nil)
      end
    end

    it 'retains guarded native preparation retries' do
      expect(probe('retry')).to include('writes' => ['<c>target #123', '<c>incant 917 fire', '<c>incant 917 fire'], 'sends' => 3)
    end

    { 'drift' => 'incant_selector_changed', 'budget' => 'command_limit' }.each do |scenario, reason|
      it "blocks further native casting on #{scenario}" do
        expect(probe(scenario)).to include('writes' => ['<c>target #123', '<c>incant 917 fire'], 'reason' => reason, 'sends' => 2)
      end
    end

    it 'does not restart the original twelve-second window after casting' do
      result = probe('timeout')
      expect(result['wait_duration']).to be_between(0, 0.21)
      expect(result['wait_result']).to eq('timeout')
      expect(result['sends']).to eq(2)
      expect(probe('expired')).to include('wait_duration' => nil, 'readers' => [], 'sends' => 2)
    end

    %w[hold stop].each do |control|
      it "interrupts the completion wait on #{control} without creating a reader or sending again" do
        expect(probe(control)).to include('reason' => (control == 'hold' ? 'held' : 'stopped'), 'sends' => 2)
      end
    end
  end
end
