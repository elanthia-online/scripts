# frozen_string_literal: true

# Pure external-world fixtures around source-extracted production Bigshot cmd.
# This establishes existing-engine reuse, not complete live Lich compatibility.
# Optional companion mode exercises its actual guard and Script scope methods.
if ENV['LICH_EXECUTION_GUARD_ROOT']
  require File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script_execution_guard')
end

module BigshotQuickNativeCmdSpec
  module Script
    class << self
      attr_accessor :current

      def self
        current
      end
    end
  end

  module Char
    def self.mana
      10
    end
  end

  module Spell
    class << self
      attr_accessor :entries

      def [](number)
        entries.fetch(number)
      end

      def after_stance=(value)
        class_variable_set(:@@after_stance, value)
      end
    end
  end

  class Scope
    class Interrupted < StandardError; end

    def initialize(callback)
      @callback = callback
    end

    def checkpoint!(command: nil)
      raise Interrupted if @closed
      @closed = @callback.call(command) != true
      raise Interrupted if @closed
      true
    end

    def close!
      @closed = true
    end
  end

  class Owner
    attr_reader :wires, :downstream_buffer
    attr_accessor :response, :on_send

    def initialize
      @wires, @downstream_buffer = [], []
      @response = 'Roundtime: 3 sec.'
    end

    def execution_guard_active?
      !@scope.nil?
    end

    def with_execution_guard(callback)
      raise ArgumentError, 'scope active' if execution_guard_active?
      @scope = Scope.new(callback)
      begin
        @scope.checkpoint!
        result = yield @scope
        @scope.checkpoint!
        result
      ensure
        @scope.close!
        @scope = nil
      end
    end

    def check_execution_guard!(command: nil)
      @scope ? @scope.checkpoint!(command: command) : true
    end

    def emit(wire)
      check_execution_guard!(command: wire)
      @wires << wire
      @downstream_buffer << @response
      @on_send&.call(wire)
    end
  end

  if ENV['LICH_EXECUTION_GUARD_ROOT']
    native_source = File.read(File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script.rb')).gsub("\r\n", "\n")
    Owner.const_set(:ScriptExecutionGuard, Lich::Common::ScriptExecutionGuard)
    Owner.const_set(:EXECUTION_GUARD_MUTEX_INITIALIZER, Mutex.new)
    %w[with_execution_guard execution_guard_active? check_execution_guard! execution_guard_mutex].each do |name|
      code = native_source[/^      def #{Regexp.escape(name)}(?:\([^\n]*\))?\n.*?^      end$/m]
      raise "native Script##{name} missing" unless code
      Owner.class_eval(code, __FILE__, __LINE__)
    end
  end

  class NativeSpell
    attr_reader :num, :calls
    attr_accessor :result

    def initialize(number, owner, known: true)
      @num, @owner, @known = number, owner, known
      @calls = []
      @result = 'Cast Roundtime 3 Seconds.'
    end

    def known?
      @known
    end

    def active?
      false
    end

    def affordable?
      true
    end

    def cast(*arguments)
      @calls << [self, arguments]
      @owner.emit(">prepare #{@num}")
      @owner.emit(">cast #{arguments.first}")
      @result
    end
  end

  class Transport
    def put(*messages)
      messages.each { |message| @owner.emit('>' + message) }
    end

    def get?
      @owner.check_execution_guard!
      @owner.downstream_buffer.shift
    end

    def clear
      @owner.downstream_buffer.clear
    end
  end

  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[EncounterPolicy EncounterController QuickGuard QuickIO QuickExecution QuickRun].each do |name|
    code = source[/^  (?:class|module) #{name}\n.*?^  end$/m]
    raise "#{name} missing" unless code
    module_eval(code, __FILE__, __LINE__)
  end

  class Engine < Transport
    include QuickIO
    include QuickExecution

    def initialize(owner)
      super()
      @owner = owner
      @COMMANDS_REGISTRY = {}
      @OOM = 0
      initialize_command_data
    end
  end

  %w[cmd initialize_command_data command_check check_state_condition once_commands_register
     repeatdelay_blocked? bs_put cmd_spell spell_is_selfcast? cast_spell cmd_unarmed reset_variables].each do |name|
    code = source[/^  def #{Regexp.escape(name)}(?:\([^\n]*\))?[^\n]*\n.*?^  end$/m]
    raise "native Bigshot##{name} missing" unless code
    Engine.class_eval(code, __FILE__, __LINE__)
  end
end
