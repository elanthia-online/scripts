# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

module BigshotQuickLeechSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  class Admission; end
  Admission.class_eval(source[/^    def self.command_supported!\(command\)\n.*?^    end$/m])

  # Real native Spell.cast, Script scopes, Game socket guard and XML selector;
  # only character resources, room state and server responses are fixtures.
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
      module Cooldowns
        def self.time_left(_name) = (ARGV.fetch(1) == 'cooldown' ? 15 : 14)
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
    { num: 516, name: 'Mana Leech', type: 'attack', circle: '5', stance: false,
      channel: false, no_incant: false }.each { |key, value| spell.instance_variable_set("@#{key}", value) }
    { known?: scenario != 'unknown', affordable?: scenario != 'unaffordable', active?: false,
      mana_cost: 1, stamina_cost: 0, spirit_cost: 0 }.each { |key, value| spell.define_singleton_method(key) { value } }
    inactive = Object.new
    inactive.define_singleton_method(:known?) { false }
    Spell.define_singleton_method(:[]) { |number| number == 516 ? spell : inactive }
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
    end
    %w[cmd initialize_command_data command_check check_state_condition once_commands_register
       repeatdelay_blocked? bs_put cmd_leech reset_variables].each do |name|
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
                 elsif command == 'incant 516'
                   casts += 1
                   select.call('999') if scenario == 'drift' && casts == 1
                   if casts == 1 && %w[retry drift budget].include?(scenario)
                     '[Spell preparation time: 0 seconds]'
                   else
                     'Cast Roundtime 3 Seconds.'
                   end
                 else
                   raise "Unexpected native wire #{wire.inspect}"
                 end
      owner.downstream_buffer.push(response)
    end
    Game.instance_variable_set(:@socket, socket)
    Game.instance_variable_set(:@mutex, Mutex.new)
    $_CLIENTBUFFER_ = LimitedArray.new
    $cmd_prefix = '<c>'
    identity = { session: 'login', room_id: 42, room_epoch: 1, target_id: '123' }
    observed = identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running)
    guard = Probe::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                                  max_sends: scenario == 'budget' ? 2 : 10, max_seconds: 3)
    engine = Probe::Engine.new
    begin
      result = Timeout.timeout(5) do
        if scenario == 'legacy'
          engine.cmd_leech
          :legacy
        else
          engine.quick_execute('leech', Struct.new(:id).new('123'), guard: guard, owner: owner, prefix: '<c>')
        end
      end
    rescue Probe::QuickGuard::Interrupted => error
      reason = error.reason
    end
    puts JSON.generate(writes: writes, result: result, reason: reason, sends: guard.sends,
                       selector: XMLData.current_target_id, native_scope: owner.execution_guard_active?,
                       stream_flags: [owner.want_downstream, owner.want_downstream_xml])
  RUBY
end

RSpec.describe 'Quick leech helper compatibility' do
  it 'admits only the existing no-argument helper syntax after native modifiers/wrappers' do
    ['leech', 'LEECH(m20)', 'force leech until 2', '506 leech'].each do |command|
      expect(BigshotQuickLeechSpec::Admission.command_supported!(command)).to be(true)
    end
    ['leech target', 'leech #123', 'leech Fred', 'leech516', 'leeching', 'force leech Fred until 2'].each do |command|
      expect { BigshotQuickLeechSpec::Admission.command_supported!(command) }.to raise_error(ArgumentError, /leech does not accept arguments/)
    end
  end

  context 'with native Lich spell execution and socket guard' do
    before { skip 'Set LICH_EXECUTION_GUARD_ROOT for native leech integration' unless ENV['LICH_EXECUTION_GUARD_ROOT'] }

    def probe(scenario)
      output, error, status = Open3.capture3(
        RbConfig.ruby, '-', File.expand_path('../../../scripts/bigshot.lic', __dir__), scenario,
        stdin_data: BigshotQuickLeechSpec::PROBE
      )
      expect(status.success?).to be(true), "Native leech probe failed:\n#{output}\n#{error}"
      JSON.parse(output).tap do |result|
        expect(result).to include('native_scope' => false, 'stream_flags' => [true, false])
      end
    end

    it 'uses production cmd and cmd_leech with confirmed target selection before native Spell.cast' do
      expect(probe('normal')).to include('writes' => ['<c>target #123', '<c>incant 516'], 'sends' => 2, 'reason' => nil)
    end

    %w[cooldown unknown unaffordable].each do |scenario|
      it "does not select or cast when the existing #{scenario} check skips leech" do
        expect(probe(scenario)).to include('writes' => [], 'sends' => 0, 'selector' => '777', 'result' => { 'outcome' => 'skipped', 'sends' => 0 })
      end
    end

    it 'preserves native preparation retries within the same selected-target scope' do
      expect(probe('retry')).to include('writes' => ['<c>target #123', '<c>incant 516', '<c>incant 516'], 'sends' => 3)
    end

    it 'blocks a native retry after the selector changes to another creature' do
      expect(probe('drift')).to include('writes' => ['<c>target #123', '<c>incant 516'], 'reason' => 'incant_selector_changed')
    end

    it 'counts selection and first cast before denying the retry at the action limit' do
      expect(probe('budget')).to include('writes' => ['<c>target #123', '<c>incant 516'], 'sends' => 2, 'reason' => 'command_limit')
    end

    it 'leaves the legacy implicit selector and native casting unchanged' do
      expect(probe('legacy')).to include('writes' => ['<c>incant 516'], 'selector' => '777', 'sends' => 0, 'result' => 'legacy')
    end
  end
end
