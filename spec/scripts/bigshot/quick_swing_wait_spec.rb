module BigshotQuickSwingWaitSpec
  SOURCE = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  Creature = Struct.new(:id, :name, :noun)

  class Harness
    module QuickGuard
      class Interrupted < StandardError; end
    end

    module Script
      class << self
        attr_accessor :current
      end
    end

    module Lich
      module Gemstone
        module Group
          class << self
            attr_accessor :verified, :roster

            def checked? = @verified
            def _members = @roster
            def members = raise('must not issue GROUP while waiting')
          end
        end

        module Combat
          module Definitions
            module Attacks
              ATTACK_LOOKUP = [[/(?<attacker>.+?) swings (?<weapon>.+?) at (?<target>[^!]+)!/, :attack]].freeze
            end
          end

          # Native parser contract stand-in. The inbound swing and thorn-barrier
          # messages below come from Lich's combat replay regression fixtures.
          module Parser
            TARGET_LINK_PATTERN = /<a exist="(?<id>[^"]+)" noun="(?<noun>[^"]+)">(?<name>[^<]+)<\/a>/

            def self.strip_links(text)
              text.gsub(/<[^>]+>/, '')
            end

            def self.parse_attack(line)
              match = Definitions::Attacks::ATTACK_LOOKUP.first.first.match(line)
              return unless match

              attacker = TARGET_LINK_PATTERN.match(match[:attacker])
              return unless attacker

              { attacker: { id: attacker[:id].to_i }, inbound: match[:target] == 'you' }
            end
          end
        end
      end
    end

    class Owner
      attr_accessor :want_downstream, :want_downstream_xml, :cancelled, :on_read, :active
      attr_reader :reads, :clear_count

      def initialize(clock, lines)
        @clock, @lines = clock, lines.dup
        @want_downstream, @want_downstream_xml = true, false
        @reads, @clear_count = [], 0
        @active = true
      end

      def execution_guard_active? = @active

      def check_execution_guard!
        raise QuickGuard::Interrupted, 'manual_hold' if @cancelled
      end

      def clear
        @clear_count += 1
      end

      def gets(timeout)
        check_execution_guard!
        @reads << timeout
        @on_read&.call(self)
        check_execution_guard!
        line = @lines.shift
        @clock[0] += timeout unless line
        line
      end
    end

    attr_accessor :prone
    attr_reader :stances

    def initialize(deadline)
      @quick_native_scope = true
      @quick_guard = Struct.new(:deadline).new(deadline)
      @WANDER_STANCE = 'defensive'
      @stances = []
    end

    def debug_msg(*); end
    def npc_prone?(_target) = @prone
    def bs_hostile_creatures = [:target]
    def gameobj_npc_check = 1
    def standing? = true
    def should_flee? = false

    def change_stance(*values)
      @stances << values
    end

    class_eval(SOURCE[/^  def wait_for_swing\(seconds, target = nil\)\n.*?^  end$/m])
  end
end

RSpec.describe BigshotQuickSwingWaitSpec::Harness do
  let(:clock) { [10.0] }
  let(:target) { BigshotQuickSwingWaitSpec::Creature.new('17', 'an ogre', 'ogre') }
  let(:attacker) { '<pushBold/><a exist="17" noun="ogre">An ogre</a><popBold/>' }
  let(:subject) { described_class.new(12.0) }

  before do
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock.first }
    described_class::Lich::Gemstone::Group.verified = true
    described_class::Lich::Gemstone::Group.roster = [BigshotQuickSwingWaitSpec::Creature.new('-5', 'Friend', 'Friend')]
  end

  def install_owner(*lines)
    described_class::Script.current = described_class::Owner.new(clock, lines)
  end

  it 'waits on the owner for an exact target swing at the character' do
    owner = install_owner("#{attacker.sub('17', '117')} swings a club at you!", "#{attacker} swings a club at you!")
    previous = [$stop_wait, $global_target, $pcs]
    subject.wait_for_swing(5, target)
    expect(owner.reads.size).to eq(2)
    expect(owner.clear_count).to eq(1)
    expect([$stop_wait, $global_target, $pcs]).to eq(previous)
    expect([owner.want_downstream, owner.want_downstream_xml]).to eq([true, false])
  end

  it 'accepts a verified group recipient from a native target link or exact name' do
    ['<a exist="-5" noun="Friend">Friend</a>', 'Friend'].each do |recipient|
      owner = install_owner("#{attacker} swings a club at #{recipient}!")
      subject.wait_for_swing(5, target)
      expect(owner.reads.size).to eq(1)
    end
  end

  it 'ignores room echoes and attacks on unrelated players' do
    owner = install_owner("<component id='room objs'>#{attacker} swings a club at you!</component>",
                          "#{attacker} swings a club at Stranger!", "#{attacker} swings a club at you!")
    subject.wait_for_swing(5, target)
    expect(owner.reads.size).to eq(3)
  end

  it 'does not query an unverified group and still recognizes an inbound self swing' do
    described_class::Lich::Gemstone::Group.verified = false
    owner = install_owner("#{attacker} swings a club at Friend!", "#{attacker} swings a club at you!")
    subject.wait_for_swing(5, target)
    expect(owner.reads.size).to eq(2)
  end

  it 'recognizes the native thorn-barrier interception for this attacker' do
    owner = install_owner("The thorny barrier surrounding you blocks the attack from #{attacker}!")
    subject.wait_for_swing(5, target)
    expect(owner.reads.size).to eq(1)
  end

  it 'bounds an empty stream by both requested duration and the guard deadline' do
    owner = install_owner
    subject.wait_for_swing(0.25, target)
    expect(clock.first).to be_within(0.0001).of(10.25)
    expect(owner.reads.max).to be <= 0.1
    clock[0] = 10.0
    install_owner
    subject.wait_for_swing(30, target)
    expect(clock.first).to be_within(0.0001).of(12.0)
  end

  it 'restores both original stream flags when the native guard interrupts a read' do
    owner = install_owner
    owner.want_downstream, owner.want_downstream_xml = false, true
    owner.on_read = ->(script) { script.cancelled = true }
    expect { subject.wait_for_swing(5, target) }.to raise_error(described_class::QuickGuard::Interrupted, 'manual_hold')
    expect([owner.want_downstream, owner.want_downstream_xml]).to eq([false, true])
  end

  it 'stops before waiting when the target is already down' do
    owner = install_owner
    subject.prone = true
    subject.wait_for_swing(5, target)
    expect(owner.reads).to be_empty
    expect(subject.stances).to be_empty
  end

  it 'rejects invalid waits or missing guard support before changing stream flags' do
    owner = install_owner
    expect { subject.wait_for_swing(Float::INFINITY, target) }.to raise_error(ArgumentError)
    expect { subject.wait_for_swing(-1, target) }.to raise_error(ArgumentError)
    owner.active = false
    expect { subject.wait_for_swing(5, target) }.to raise_error(described_class::QuickGuard::Interrupted, 'swing_observation_unavailable')
    expect([owner.want_downstream, owner.want_downstream_xml]).to eq([true, false])
  end
end
