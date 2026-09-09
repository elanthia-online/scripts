# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

# Optional isolated native replay: XMLParser -> Tracker's installed hook ->
# Processor/Parser -> Observers -> production QuickOutcomeEvidence. The world
# and incoming transport are fixtures; no outcome hashes or parser are faked.
module BigshotQuickOutcomeNativeSpec
  PROBE = <<~'RUBY'
    require 'json'
    require 'ox'
    LIB_DIR = File.join(ENV.fetch('LICH_EXECUTION_GUARD_ROOT'), 'lib')
    $LOAD_PATH.unshift(LIB_DIR)
    require 'common/xmlparser'
    require 'common/gameobj'
    require 'common/limitedarray'
    require 'common/sharedbuffer'
    require 'common/downstreamhook'
    require 'games'
    XMLData = Lich::Common::XMLParser.new
    XMLData.instance_variable_set(:@game, 'GSIV')
    XMLData.instance_variable_set(:@name, 'Probe')
    XMLData.instance_variable_set(:@room_id, 42)
    $room_count = 0
    GameObj = Lich::Common::GameObj
    DownstreamHook = Lich::Common::DownstreamHook
    INGRESS_THREAD = Thread.current
    module Script
      def self.current
        nil
      end
    end
    Game = Lich::Gemstone::Game
    class << Game
      attr_accessor :current_ingress_time

      def thread
        INGRESS_THREAD
      end
    end
    # Suppress only Tracker's automatic background bootstrap while requiring
    # native code. Never initialize/enable/configure a persisted character.
    thread_new = Thread.method(:new)
    begin
      Thread.define_singleton_method(:new) { |*_args, &_block| nil }
      require 'gemstone/combat/tracker'
    ensure
      Thread.define_singleton_method(:new, thread_new)
    end
    module Lich::Common::DB_Store
      def self.read(*)
        raise 'Unexpected persisted settings read'
      end

      def self.save(*)
        raise 'Unexpected persisted settings write'
      end
    end
    tracker = Lich::Gemstone::Combat::Tracker
    tracker.instance_variable_set(:@initialized, true)
    tracker.instance_variable_set(:@enabled, ARGV.fetch(1) != 'disabled')
    tracker.instance_variable_set(:@settings, tracker::DEFAULT_SETTINGS.merge(
      enabled: ARGV.fetch(1) != 'disabled', max_threads: 0,
      track_damage: false, track_wounds: false, track_statuses: false, track_ucs: false
    ))
    settings_before = Marshal.dump(tracker.settings)
    module Probe
    end
    source = File.read(ARGV.fetch(0)).gsub("\r\n", "\n")
    %w[EncounterSettings EncounterPolicy EncounterController QuickOutcomeEvidence].each do |name|
      body = source[/^  class #{name}\n.*?^  end$/m]
      raise "Missing production #{name}" unless body
      Probe.module_eval(body)
    end
    events, results = [], []
    scenario, queued_at = ARGV.fetch(1), nil
    collector = nil
    observer = tracker.on(:attack) do |_type, event|
      events << event
      collector.enqueue(event) if collector
    end
    transmit = lambda do |line|
      chunk = line + "\n"
      Game.current_ingress_time = case scenario
                                  when 'queued-before-arm' then queued_at
                                  when 'missing-stamp' then nil
                                  else Process.clock_gettime(Process::CLOCK_MONOTONIC)
                                  end
      XMLData.sax_parse_errors.clear
      Ox.sax_parse(XMLData, chunk, convert_special: false, symbolize: false, skip: :skip_none)
      Lich::GameBase::Game.send(:check_stream_desync!, XMLData.sax_parse_errors)
      raise 'Native hook modified transport' unless DownstreamHook.run(chunk) == chunk
    end
    own_attack = 'You swing a broadsword at <pushBold/><a exist="123" noun="rat">a giant rat</a><popBold/>!'
    prompt = '<prompt time="123">&gt;</prompt>'
    lines = case scenario
            when 'hit' then [own_attack, '... and hit for 10 points of damage!']
            when 'warded'
              ['You gesture at <pushBold/><a exist="123" noun="rat">a giant rat</a><popBold/>.',
               'CS: +100 - TD: +100 + CvA: +0 + d100: +1 == +1', 'Warded off!']
            when 'other-player'
              [own_attack.sub('You swing', '<a exist="-7" noun="Ally">Ally</a> swings'), 'A clean miss.']
            when 'other-target' then [own_attack.sub('exist="123"', 'exist="124"'), 'A clean miss.']
            when 'miss-flare'
              [own_attack, 'A clean miss.', '** Your broadsword flares with a burst of flame! **', '... 10 points of damage!']
            else [own_attack, 'A clean miss.']
            end
    replay = lambda do
      queued_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      collector = Probe::QuickOutcomeEvidence.new(context: tracker.observation_context, target_id: '123')
      raise 'Attack not armed' unless collector.arm('attack #123')
      lines.each { |line| transmit.call(line) }
      transmit.call('<nav rm="77"/>') if scenario == 'moved-before-process'
      transmit.call(prompt)
      if scenario == 'moved-after-process'
        transmit.call('<pushStream id="room"/><nav rm="77"/><popStream id="room"/>')
      end
      result = collector.result(context: tracker.observation_context)
      results << result
      result.merge(sends: 1)
    end
    tracker.send(:add_downstream_hook)
    begin
      if scenario == 'two-misses'
        policy = Probe::EncounterPolicy.new(
          Probe::EncounterSettings.normalize('max_ineffective' => 2),
          targets: { 'rat' => 'a' }, routines: { 'a' => ['attack target'] }
        )
        observation = lambda do
          { session: 'login', room_id: 42, room_epoch: XMLData.room_count, owner: true,
            connected: true, safe: true, targets: [{ id: '123', name: 'rat', noun: 'rat', hostile: true }] }
        end
        controller = Probe::EncounterController.new(policy: policy, snapshot: observation,
                                                     dispatch: ->(**_request) { replay.call })
        2.times { controller.tick }
        controller_status = controller.status
      else
        replay.call
      end
    ensure
      tracker.off(observer)
      tracker.send(:remove_downstream_hook)
    end
    raise 'Tracking settings mutated' unless Marshal.dump(tracker.settings) == settings_before
    summary = events.map do |event|
      { source: event[:source], batch: event[:observation_batch], outcomes: event[:outcomes],
        hits: event[:hits], flares: event[:flares].map { |flare| flare[:type] }, target: event[:target],
        attacker: event[:attacker], born: event[:_attack_born] }
    end
    puts JSON.generate(results: results, events: summary, controller: controller_status,
                       enabled: tracker.enabled?, emit_attacks: tracker.settings[:emit_attacks],
                       observers: Lich::Gemstone::Combat::Observers.any_for?(:attack),
                       hooks: DownstreamHook._hooks.length, connection_id: Thread.current.object_id)
  RUBY
end

RSpec.describe 'Bigshot Quick native combat outcome replay' do
  before do
    skip 'Set LICH_EXECUTION_GUARD_ROOT for native outcome replay' unless ENV['LICH_EXECUTION_GUARD_ROOT']
  end

  def probe(scenario)
    source = File.expand_path('../../scripts/bigshot.lic', __dir__)
    output, error, status = Open3.capture3(
      RbConfig.ruby, '-', source, scenario, stdin_data: BigshotQuickOutcomeNativeSpec::PROBE
    )
    expect(status.success?).to be(true), "Native outcome replay failed:\n#{output}\n#{error}"
    result = JSON.parse(output)
    expect(result.values_at('observers', 'hooks', 'emit_attacks')).to eq([false, 0, false])
    result
  end

  it 'classifies a real parsed miss with ingestion provenance and a complete native batch' do
    result = probe('miss')
    expect(result.fetch('results')).to eq([{ 'outcome' => 'ineffective', 'reason' => 'native_failure_observed' }])
    expect(result.fetch('events').first).to include('born' => true, 'outcomes' => ['miss'],
                                                    'batch' => include('index' => 0, 'size' => 1),
                                                    'source' => include('connection_id' => result['connection_id'], 'character' => 'Probe', 'room_epoch' => 0))
  end

  it 'recognizes a real parsed damage hit as effective' do
    expect(probe('hit').fetch('results').first['outcome']).to eq('effective')
  end

  it 'recognizes native warding failure without guessing from command sends' do
    result = probe('warded')
    expect(result.fetch('events').first['outcomes']).to include('warded')
    expect(result.fetch('results').first['outcome']).to eq('ineffective')
  end

  %w[other-player other-target miss-flare moved-before-process moved-after-process queued-before-arm missing-stamp].each do |scenario|
    it "keeps #{scenario} uncertain instead of charging an ineffective action" do
      result = probe(scenario)
      expect(result.fetch('events')).not_to be_empty
      expect(result.fetch('results').first['outcome']).to eq('sent')
      event = result.fetch('events').first
      expect(event['source']).to be_nil if %w[moved-before-process missing-stamp].include?(scenario)
      expect(event['source']).not_to be_nil if %w[moved-after-process queued-before-arm].include?(scenario)
      expect(event['flares']).not_to be_empty if scenario == 'miss-flare'
      expect(event['attacker']).to include('id' => -7) if scenario == 'other-player'
      expect(event['target']).to include('id' => 124) if scenario == 'other-target'
    end
  end

  it 'holds the production controller after two native observed misses' do
    result = probe('two-misses')
    expect(result.fetch('results').map { |item| item['outcome'] }).to eq(%w[ineffective ineffective])
    expect(result.fetch('controller')).to include('state' => 'held', 'reason' => 'ineffective_limit', 'actions' => 2)
  end

  it 'leaves disabled tracking and emit settings unchanged without manufacturing evidence' do
    result = probe('disabled')
    expect(result.fetch('enabled')).to be(false)
    expect(result.fetch('events')).to be_empty
    expect(result.fetch('results').first['outcome']).to eq('sent')
  end
end
