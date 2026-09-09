# frozen_string_literal: true

module BigshotQuickRunSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[EncounterPolicy EncounterController QuickGuard QuickLoot QuickSeek QuickRun].each do |name|
    body = source[/^  class #{name}\n.*?^  end$/m]
    raise "could not extract #{name}" unless body
    module_eval(body, __FILE__, __LINE__)
  end

  class Owner
    attr_accessor :active

    def execution_guard_active?
      !!@active
    end
  end

  class Engine
    attr_accessor :routine
    attr_reader :calls, :sends

    def initialize
      @calls, @sends = [], []
      @routine = ->(guard) { guard.transmit('attack #123') { @sends << 'attack #123' } }
    end

    def quick_execute(command, target, guard:, owner:, prefix:)
      @calls << { command: command, target: target, guard: guard, prefix: prefix }
      owner.active = true
      @routine.call(guard)
      guard.checkpoint!
      { outcome: guard.sends.zero? ? :skipped : :sent, sends: guard.sends }
    ensure
      owner.active = false
    end

    def quick_loot_execute(command, guard:, owner:, prefix:)
      raise ArgumentError, 'unexpected wire prefix' unless prefix == '>'
      owner.active = true
      guard.transmit(command) { @sends << command }
      @routine.call(guard) if @on_loot
      guard.checkpoint!
      { outcome: :complete, sends: guard.sends }
    ensure
      owner.active = false
    end

    attr_accessor :on_loot
  end
end
