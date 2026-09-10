# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

# Offline full-source smoke, not Script.start lifecycle coverage. Native
# TRUSTED_SCRIPT_BINDING and Script guard methods execute the complete .lic;
# only runtime discovery/character state and the never-instantiated GTK base
# class are fixtures. Each probe has its own process and temporary data root.
module BigshotQuickFullFileSpec
  PROBE = <<~'RUBY'
    require 'json'
    require 'set'
    require 'tmpdir'
    require 'timeout'
    LIB_DIR = File.expand_path('lib', ENV.fetch('LICH_EXECUTION_GUARD_ROOT'))
    $LOAD_PATH.unshift(LIB_DIR)
    require 'common/script'
    require 'common/class_exts/nilclass'
    require 'common/xmlparser'
    require 'common/gameobj'
    require 'common/upstreamhook'
    require 'common/downstreamhook'
    require 'gemstone/creature'
    require 'gemstone/combat/parser'
    require 'gemstone/combat/tracker'
    Object.include Lich::Common
    LICH_VERSION = '5.99.0'
    XMLData = Lich::Common::XMLParser.new
    XMLData.instance_variable_set(:@game, 'GSIV')
    XMLData.instance_variable_set(:@room_id, 42)
    Char = Struct.new(:name, :max_stamina, :percent_encumbrance, :percent_mana).new('Probe', 100, 0, 100)
    module Gtk
      class Builder
        def initialize(*)
          raise 'A non-UI Quick command instantiated GTK'
        end
      end
    end
    module Effects
      module Debuffs
        def self.to_h
          {}
        end
      end
    end
    module Lich::Gemstone::Experience
      def self.percent_fxp
        0
      end
    end
    module Lich::Gemstone::Group
      def self.checked?
        true
      end

      def self._members
        []
      end
    end
    # Only native runtime discovery is replaced: no live connection or tracker
    # enable/persistence occurs. Tracker subscriptions remain the native API.
    module Lich::Gemstone::Combat::Tracker
      def self.enabled?
        ENV.fetch('BIGSHOT_PROBE_TRACKING') != 'disabled'
      end

      def self.observation_context
        return nil if ENV.fetch('BIGSHOT_PROBE_TRACKING') == 'missing-provenance'

        { connection_id: 1, game: XMLData.game, character: Char.name, room_epoch: XMLData.room_count }.freeze
      end
    end
    module Room
      def self.current
        Struct.new(:id).new(XMLData.room_id)
      end
    end
    class ReadOnlySettings < Hash
      def []=(*arguments)
        raise "Unexpected settings write: #{arguments.inspect}"
      end
    end
    CharSettings = ReadOnlySettings['targetable' => [], 'untargetable' => []]
    CharSettings.each_value(&:freeze)
    CharSettings.freeze
    module UserVars
      PROFILE = { 'profile_current' => 'normal', 'targets' => 'ogre', 'hunting_commands' => 'attack target' }.freeze

      def self.op
        PROFILE
      end

      def self.op=(*)
        raise 'Unexpected UserVars replacement'
      end

      def self.save
        raise 'Unexpected UserVars save'
      end
    end
    $probe_output, $probe_sends = [], []
    module Game
      def self.closed?
        false
      end

      def self.puts(*commands)
        $probe_sends.concat(commands)
        raise 'Unexpected outbound game command'
      end

      class << self
        alias _puts puts
      end
    end
    module ProbeHelpers
      def echo(message = '')
        $probe_output << message.to_s
      end

      def put(*commands)
        Game.puts(*commands)
      end
      alias fput put
      alias move put

      def dead?
        false
      end

      def checkpcs
        []
      end
    end
    Object.include ProbeHelpers
    source = File.read(ARGV.fetch(0))
    args = ARGV.drop(1)
    owner = Lich::Common::Script.allocate
    owner.instance_variable_set(:@name, 'bigshot')
    owner.instance_variable_set(:@vars, [args.join(' '), *args])
    owner.define_singleton_method(:inspect) { source }
    Lich::Common::Script.define_singleton_method(:current) { owner }
    Lich::Common::Script.define_singleton_method(:list) { [owner] }
    Lich::Common::Script.define_singleton_method(:running) { [owner] }
    $cmd_prefix = '<c>'
    $clean_lich_char = ';'
    $bigshot_aim = :sentinel
    profile_before = Marshal.dump(UserVars.op)
    settings_before = Marshal.dump(CharSettings)
    Dir.mktmpdir('bigshot-full-file-') do |data_root|
      $data_dir = data_root
      begin
        Timeout.timeout(3) do
          eval(source, Lich::Common::TRUSTED_SCRIPT_BINDING.call, ARGV.fetch(0), 1)
        end
      rescue SystemExit => error
        raise 'Unexpected failure exit' unless error.success?
      end
      raise 'UserVars changed' unless Marshal.dump(UserVars.op) == profile_before
      raise 'CharSettings changed' unless Marshal.dump(CharSettings) == settings_before
      raise 'Unexpected profile directory or file' unless Dir.children(data_root).empty?
    end
    puts JSON.generate(output: $probe_output, sends: $probe_sends, reset: $bigshot_aim != :sentinel,
                       hooks: UpstreamHook._hooks.length + DownstreamHook._hooks.length,
                       runtime_published: owner.respond_to?(:quick_combat_runtime))
  RUBY
end

RSpec.describe 'Bigshot complete-file Quick CLI smoke' do
  before do
    skip 'Set LICH_EXECUTION_GUARD_ROOT to run companion native integration' unless ENV['LICH_EXECUTION_GUARD_ROOT']
  end

  def probe(*arguments, tracking: 'enabled')
    source = File.expand_path('../../../scripts/bigshot.lic', __dir__)
    output, error, status = Open3.capture3(
      { 'BIGSHOT_PROBE_TRACKING' => tracking }, RbConfig.ruby, '-', source, *arguments, stdin_data: BigshotQuickFullFileSpec::PROBE
    )
    expect(status.success?).to be(true), "Full-source probe failed:\n#{output}\n#{error}"
    result = JSON.parse(output)
    expect(result.fetch('sends')).to be_empty
    expect(result.fetch('hooks')).to eq(0)
    expect(result.fetch('runtime_published')).to be(false)
    result
  end

  it 'loads the entire script and answers help without initialization or settings writes' do
    result = probe('quick', 'help')
    expect(result.fetch('output').join).to include('Quick Combat:')
    expect(result.fetch('reset')).to be(false)
  end

  it 'rejects a malformed extended Quick option without falling through to hunting initialization' do
    result = probe('quick', 'clear', '--bogus')
    expect(result.fetch('output').join).to include('Unknown quick option')
    expect(result.fetch('reset')).to be(false)
  end

  it 'constructs and completes clear in an empty native creature roster without sends' do
    result = probe('quick', 'clear')
    expect(result.fetch('output').join).to include('Quick Combat started.', 'completed')
    expect(result.fetch('output').join).not_to include('did not finish')
    expect(result.fetch('reset')).to be(true)
  end

  %w[disabled missing-provenance].each do |tracking|
    it "refuses #{tracking} combat tracking before global reset or outbound commands" do
      result = probe('quick', 'clear', tracking: tracking)
      expect(result.fetch('output').join).to include('ineffective-action monitoring requires enabled native combat tracking with observation provenance')
      expect(result.fetch('output').join).not_to include('Quick Combat started.')
      expect(result.fetch('reset')).to be(false)
    end
  end
end
