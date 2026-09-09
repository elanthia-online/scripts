# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

# Optional offline integration: real native Spell.force_incant/cast, retry
# helpers, Script execution guard, Game send mutex and XML selector parser.
# Character skill/resource state and the socket's game responses are fixtures.
module BigshotQuickIncantNativeSpec
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
    require 'common/spell'
    require 'common/detachable_client_registry'
    require 'games'
    require 'global_defs'
    Object.include Lich::Common
    XMLData = Lich::Common::XMLParser.new
    XMLData.instance_variable_set(:@game, 'GSIV')
    Game = Lich::GameBase::Game
    Char = Struct.new(:name, :mana, :stamina, :spirit, :stance).new('Probe', 100, 100, 10, 'guarded')
    module Feat
      def self.known?(_name)
        false
      end
    end
    module Effects
      module Spells
        def self.active?(_name)
          false
        end
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
    spell_id = scenario.include?('self') ? 401 : 903
    spell = Spell.allocate
    { num: spell_id, name: 'Fixture spell', type: 'attack', circle: '9', stance: false,
      channel: false, no_incant: false }.each { |key, value| spell.instance_variable_set("@#{key}", value) }
    { known?: true, affordable?: true, active?: false, mana_cost: 1, stamina_cost: 0,
      spirit_cost: 0 }.each { |key, value| spell.define_singleton_method(key) { value } }
    inactive = Object.new
    inactive.define_singleton_method(:known?) { false }
    inactive.define_singleton_method(:active?) { false }
    Spell.define_singleton_method(:[]) { |number| number == spell_id ? spell : inactive }
    Spell.after_stance = 'original stance'
    source = File.read(ARGV.fetch(0)).gsub("\r\n", "\n")
    module Probe
    end
    %w[QuickGuard QuickIO QuickExecution].each do |name|
      body = source[/^  (?:class|module) #{name}\n.*?^  end$/m]
      raise "Missing #{name}" unless body
      Probe.module_eval(body)
    end
    class Probe::Engine
      include Probe::QuickIO
      include Probe::QuickExecution

      def initialize
        @COMMANDS_REGISTRY, @OOM, @HUNTING_STANCE = {}, 0, 'guarded'
        initialize_command_data
      end

      def debug_msg(*); end
      def check_for_deaders_prone; end
      def escape_rooms; end
      def change_stance(*); end
      def dead_or_gone?(_target); false; end
      def still_targetable?(_id); true; end
      def valid_target?(_target); true; end
      def standing?; true; end
    end
    %w[cmd initialize_command_data command_check check_state_condition once_commands_register
       repeatdelay_blocked? bs_put cmd_spell spell_is_selfcast? cast_spell reset_variables].each do |name|
      body = source[/^  def #{Regexp.escape(name)}(?:\([^\n]*\))?[^\n]*\n.*?^  end$/m]
      raise "Missing production #{name}" unless body
      Probe::Engine.class_eval(body)
    end
    select = lambda do |id|
      content = id ? "##{id}" : ''
      Ox.sax_parse(XMLData, "<dropDownBox id=\"dDBTarget\" content_value=\"#{content}\"/>",
                   convert_special: false, symbolize: false, skip: :skip_none)
    end
    select.call('777')
    XMLData.instance_variable_set(:@prepared_spell, 'Other spell') if scenario == 'release_budget'
    writes = []
    casts = 0
    socket = Object.new
    socket.define_singleton_method(:puts) do |wire|
      writes << wire
      command = wire.delete_prefix('<c>')
      response = if command == 'target clear'
                   select.call(nil)
                   'You are no longer targeting anything.'
                 elsif command.start_with?('target #')
                   select.call(command.delete_prefix('target #'))
                   'You are now targeting an ogre.'
                 elsif command == 'release'
                   XMLData.instance_variable_set(:@prepared_spell, 'None')
                   'You feel the magic of your spell rush away from you.'
                 elsif command.start_with?('incant ')
                   casts += 1
                   select.call('999') if scenario.include?('drift') && casts == 1
                   if scenario.include?('hindrance')
                     '[Spell Hindrance for fixture]'
                   elsif casts == 1 && (scenario.include?('preparation') || scenario == 'prep_budget')
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
    observed = identity.merge(owner: true, connected: true, authorized: true,
                              target_valid: true, safe: true, control: :running)
    guard = Probe::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                                  max_sends: scenario.end_with?('budget') ? 2 : 10, max_seconds: 3)
    target = Struct.new(:id, :name, :noun).new('123', 'ogre', 'ogre')
    engine = Probe::Engine.new
    begin
      result = Timeout.timeout(5) do
        engine.quick_execute("incant #{spell_id}", target, guard: guard, owner: owner, prefix: '<c>')
      end
    rescue Probe::QuickGuard::Interrupted => error
      reason = error.reason
    end
    puts JSON.generate(writes: writes, result: result, reason: reason, sends: guard.sends,
                       after_stance: Spell.after_stance, selector: XMLData.current_target_id,
                       native_scope: owner.execution_guard_active?,
                       stream_flags: [owner.want_downstream, owner.want_downstream_xml])
  RUBY
end

RSpec.describe 'Quick incant through native Lich spell retries and socket guards' do
  before do
    skip 'Set LICH_EXECUTION_GUARD_ROOT for native incant integration' unless ENV['LICH_EXECUTION_GUARD_ROOT']
  end

  def probe(scenario)
    source = File.expand_path('../../../scripts/bigshot.lic', __dir__)
    output, error, status = Open3.capture3(
      RbConfig.ruby, '-', source, scenario, stdin_data: BigshotQuickIncantNativeSpec::PROBE
    )
    expect(status.success?).to be(true), "Native incant probe failed:\n#{output}\n#{error}"
    result = JSON.parse(output)
    expect(result).to include('after_stance' => 'original stance', 'native_scope' => false, 'stream_flags' => [true, false])
    result
  end

  it 'runs actual force_incant/cast using a selector confirmed by native XML' do
    result = probe('normal')
    expect(result).to include('writes' => ['<c>target #123', '<c>incant 903'], 'reason' => nil, 'sends' => 2)
  end

  it 'rejects the native spell-preparation retry after a selector change' do
    result = probe('preparation_drift')
    expect(result).to include('writes' => ['<c>target #123', '<c>incant 903'], 'reason' => 'incant_selector_changed')
  end

  it 'rejects Bigshot hindrance retries around the actual native spell call' do
    result = probe('hindrance_drift')
    expect(result).to include('writes' => ['<c>target #123', '<c>incant 903'], 'reason' => 'incant_selector_changed')
  end

  it 'keeps self-cast clearing explicit and does not restore a target on cancellation' do
    result = probe('self_preparation_drift')
    expect(result).to include('writes' => ['<c>target clear', '<c>incant 401'], 'reason' => 'incant_selector_changed')
  end

  it 'counts native release and target setup before allowing a cast' do
    result = probe('release_budget')
    expect(result).to include('writes' => ['<c>release', '<c>target #123'], 'reason' => 'command_limit', 'sends' => 2)
  end

  it 'counts a native incant preparation attempt before its retry' do
    result = probe('prep_budget')
    expect(result).to include('writes' => ['<c>target #123', '<c>incant 903'], 'reason' => 'command_limit', 'sends' => 2)
  end
end
