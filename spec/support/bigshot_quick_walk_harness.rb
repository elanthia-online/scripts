# frozen_string_literal: true

module BigshotQuickWalkSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[EncounterPolicy QuickRetreatWalk].each do |name|
    body = source[/^  class #{name}\n.*?^  end$/m]
    raise "could not extract #{name}" unless body

    module_eval(body)
  end

  class Owner
    class Denied < StandardError; end
    attr_accessor :on_sleep
    attr_reader :writes

    def initialize = (@writes = [])
    def execution_guard_active? = !@policy.nil?

    def with_execution_guard(policy, **)
      @policy, @cancelled = policy, false
      check_execution_guard!
      value = yield
      check_execution_guard!
      value
    ensure
      @policy = nil
    end

    def check_execution_guard!(command: nil)
      @cancelled = true unless @policy.call(command).equal?(true)
      raise Denied if @cancelled
    end

    def emit(command)
      check_execution_guard!(command: command)
      @writes << command
    end

    def execution_sleep(seconds)
      check_execution_guard!
      @on_sleep.call(seconds)
      check_execution_guard!
    end
  end

  if ENV['LICH_EXECUTION_GUARD_ROOT']
    require File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script_execution_guard')
    native = File.read(File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib/common/script.rb')).gsub("\r\n", "\n")
    Owner.const_set(:ScriptExecutionGuard, Lich::Common::ScriptExecutionGuard)
    Owner.const_set(:EXECUTION_GUARD_MUTEX_INITIALIZER, Mutex.new)
    Owner.send(:remove_const, :Denied)
    Owner.const_set(:Denied, Lich::Common::ScriptExecutionGuard::Interrupted)
    %w[with_execution_guard execution_guard_active? check_execution_guard! execution_guard_mutex].each do |name|
      body = native[/^      def #{Regexp.escape(name)}(?:\([^\n]*\))?\n.*?^      end$/m]
      raise "could not extract native Script##{name}" unless body

      Owner.class_eval(body)
    end
  end
  Room = Struct.new(:wayto, :timeto)
end
