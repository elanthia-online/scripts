# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

# Optional source integration, isolated from the scripts suite's Lich stubs:
# LICH_EXECUTION_GUARD_ROOT=/path/to/lich-5 rspec this_spec.rb
# Uses native XMLParser, Ox, Game's parse-error policy, LimitedArray,
# DownstreamHook and Combat::Parser. Only the connected character/room and
# controller receiver and parser-thread ingress scope are fixtures; no attack
# regex or parser is reimplemented. Native Game queue stamping is covered in
# the companion's games_spec; this replay exercises its actual read-only getter.
module BigshotQuickNativeAttackSpec
  PROBE = <<~'RUBY'
    require 'json'
    require 'ox'
    LIB_DIR = File.expand_path('lib', ENV.fetch('LICH_EXECUTION_GUARD_ROOT'))
    $LOAD_PATH.unshift(LIB_DIR)
    module Lich
      def self.log(message)
        raise message
      end
    end
    require 'common/xmlparser'
    require 'common/gameobj'
    require 'common/limitedarray'
    require 'common/sharedbuffer'
    require 'common/downstreamhook'
    require 'gemstone/combat/parser'
    require 'games'
    Game = Lich::GameBase::Game
    Game.instance_variable_set(:@thread, Thread.current)
    XMLData = Lich::Common::XMLParser.new
    XMLData.instance_variable_set(:@game, 'GSIV')
    XMLData.instance_variable_set(:@room_id, 42)
    GameObj = Lich::Common::GameObj
    DownstreamHook = Lich::Common::DownstreamHook
    module Script
      def self.current
        @owner ||= Struct.new(:name).new('bigshot')
      end
    end
    module Room
      def self.current
        Struct.new(:id).new(XMLData.room_id)
      end
    end
    module Probe
    end
    source = File.read(ARGV.fetch(0)).gsub("\r\n", "\n")
    %w[QuickExecution EncounterPolicy QuickEngagement QuickAttackFeed].each do |name|
      body = source[/^  (?:class|module) #{name}\n.*?^  end$/m]
      raise "Missing production #{name}" unless body
      Probe.module_eval(body)
    end
    engine = Class.new { include Probe::QuickExecution }.new
    observation = lambda do
      { session: 'login', room_id: Room.current.id, room_epoch: XMLData.room_count,
        owner: true, connected: true, members_verified: true, members: ['Ally'],
        member_records: [{ id: '-10', name: 'Ally' }],
        targets: [{ id: '100', hostile: true, dead: false }] }
    end
    evidence = []
    run = Object.new
    run.define_singleton_method(:observe_engagement) { |**item| evidence << item }
    attack = '<a exist="-10" noun="Ally">Ally</a> swings a broadsword at <pushBold/><a exist="100" noun="ogre">an ogre</a><popBold/>!' + "\n"
    chunks = case ARGV.fetch(1)
             when 'normal', 'old_ingress', 'missing_ingress', 'off_thread' then [attack]
             when 'stream' then ["<pushStream id=\"thoughts\"/>\n", attack, "<popStream/>\n"]
             when 'speech' then ['Someone says, "' + attack.chomp + "\"\n"]
             when 'mixed_movement' then ["<nav rm=\"77\"/>" + attack]
             when 'queued_movement' then [attack, "<nav rm=\"77\"/>\n"]
             else raise 'Unknown probe scenario'
             end
    $_SERVERBUFFER_ = Lich::Common::LimitedArray.new
    main_stream = []
    ingress_times = []
    engine.with_quick_attack_feed(run, owner: Script.current, observation: observation, attack_observation: observation) do |drain|
      chunks.each do |chunk|
        # Native games.rb pushes the raw buffer, then parses XML, then invokes
        # serial downstream hooks. Keep exactly that ordering here.
        $_SERVERBUFFER_.push(chunk)
        XMLData.sax_parse_errors.clear
        Ox.sax_parse(XMLData, chunk, convert_special: false, symbolize: false, skip: :skip_none)
        Lich::GameBase::Game.send(:check_stream_desync!, XMLData.sax_parse_errors)
        main_stream << engine.quick_main_stream?
        ingress = Process.clock_gettime(Process::CLOCK_MONOTONIC) - (ARGV.fetch(1) == 'old_ingress' ? 10.0 : 0.1)
        ingress = nil if ARGV.fetch(1) == 'missing_ingress'
        Game.instance_variable_set(:@thread, nil) if ARGV.fetch(1) == 'off_thread'
        begin
          Thread.current.thread_variable_set(:lich_game_ingress_time, ingress)
          ingress_times << Game.current_ingress_time
          raise 'Hook modified incoming text' unless DownstreamHook.run(chunk) == chunk
        ensure
          Thread.current.thread_variable_set(:lich_game_ingress_time, nil)
        end
      end
      drain.call
    end
    puts JSON.generate(evidence: evidence, main_stream: main_stream, ingress_times: ingress_times,
                       room_id: XMLData.room_id, hooks_after_scope: DownstreamHook._hooks.length,
                       raw_buffer_class: $_SERVERBUFFER_.class.name)
  RUBY
end

RSpec.describe 'Bigshot Quick native XML and attack-hook integration' do
  before do
    skip 'Set LICH_EXECUTION_GUARD_ROOT to run companion native integration' unless ENV['LICH_EXECUTION_GUARD_ROOT']
  end

  def probe(scenario)
    source = File.expand_path('../../scripts/bigshot.lic', __dir__)
    output, error, status = Open3.capture3(
      RbConfig.ruby, '-', source, scenario, stdin_data: BigshotQuickNativeAttackSpec::PROBE
    )
    expect(status.success?).to be(true), "Native probe failed:\n#{output}\n#{error}"
    result = JSON.parse(output)
    expect(result.fetch('hooks_after_scope')).to eq(0)
    result
  end

  it 'accepts a complete native player attack through actual main-stream fields' do
    result = probe('normal')
    expect(result.fetch('main_stream')).to eq([true])
    expect(result.fetch('raw_buffer_class')).to eq('Lich::Common::LimitedArray')
    expect(result.fetch('evidence')).to contain_exactly(
      include('member' => 'Ally', 'target_id' => '100', 'room_id' => 42, 'room_epoch' => 0)
    )
    expect(result.fetch('evidence').first.fetch('at')).to eq(result.fetch('ingress_times').first)
  end

  it 'rejects stale, absent and off-thread native ingress instead of stamping hook time' do
    %w[old_ingress missing_ingress off_thread].each do |scenario|
      expect(probe(scenario).fetch('evidence')).to be_empty
    end
  end

  it 'rejects otherwise valid attack text received within a native non-main stream' do
    result = probe('stream')
    expect(result.fetch('main_stream')).to eq([false, false, true])
    expect(result.fetch('evidence')).to be_empty
  end

  it 'rejects native attack syntax embedded in speech' do
    expect(probe('speech').fetch('evidence')).to be_empty
  end

  it 'rejects an attack chunk containing a native room change' do
    result = probe('mixed_movement')
    expect(result.fetch('room_id')).to eq(77)
    expect(result.fetch('evidence')).to be_empty
  end

  it 'drops previously queued engagement when native movement occurs before the owner drains' do
    result = probe('queued_movement')
    expect(result.fetch('room_id')).to eq(77)
    expect(result.fetch('evidence')).to be_empty
  end
end
