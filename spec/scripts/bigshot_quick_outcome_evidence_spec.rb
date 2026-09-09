# frozen_string_literal: true

module BigshotQuickOutcomeSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  body = source[/^  class QuickOutcomeEvidence\n.*?^  end$/m]
  raise 'QuickOutcomeEvidence missing' unless body
  module_eval(body)
end

RSpec.describe BigshotQuickOutcomeSpec::QuickOutcomeEvidence do
  let(:context) do
    { connection_id: 7, game: 'GSIV', character: String.new('Fixture'), room_epoch: 8, sequence: 10 }
  end
  let(:now) { [100.0] }
  let(:capacity) { 32 }
  let(:collector) { described_class.new(context: context, target_id: '123', capacity: capacity, clock: -> { now[0] }) }
  let(:event) do
    { source: context.merge(character: String.new(context[:character]), sequence: 11, received_at: 100.1),
      observation_batch: { id: 1, index: 0, size: 1 },
      _uid: 0, root_uid: 0, parent_uid: nil, _attack_born: true, attacker: nil, target: { id: 123 },
      hits: [], statuses: [], outcomes: [:miss], flares: [] }
  end

  def observe(value = event)
    collector.arm('attack #123')
    now[0] = 100.2
    collector.enqueue(value)
    collector.result(context: context)
  end

  it 'classifies only an exact armed own root with a complete native emission batch' do
    expect(observe).to eq(outcome: :ineffective, reason: :native_failure_observed)
  end

  described_class::FAILED.each do |outcome|
    it "accepts native definite failure #{outcome} without inventing a text parser" do
      event[:outcomes] = [outcome]
      expect(observe[:outcome]).to eq(:ineffective)
    end
  end

  it 'reports observed positive damage, hit outcomes or status without claiming overall success' do
    [{ hits: [{ damage: 4 }], outcomes: [] }, { outcomes: [:hit] }, { statuses: ['stunned'], outcomes: [] },
     { _had_status: true, outcomes: [] }].each do |facts|
      instance = described_class.new(context: context, target_id: '123', clock: -> { 100.0 })
      instance.arm('cast #123')
      instance.enqueue(event.merge(facts).merge(source: event[:source].merge(received_at: 100.0)))
      expect(instance.result(context: context)).to eq(outcome: :effective, reason: :native_effect_observed)
    end
  end

  it 'does not arm on target selection, preparation, another target or self-cast incant' do
    ['target #123', 'prepare 903', 'attack #1234', 'incant 401', 'look #123'].each do |command|
      expect(collector.arm(command)).to be(false)
    end
    now[0] = 100.2
    collector.enqueue(event)
    expect(collector.result(context: context)).to include(outcome: :sent, reason: :no_attack_write)
    expect(collector.arm('incant 903', allow_incant: true)).to be(true)
  end

  it 'downgrades native retries and multiple attack writes instead of attributing their combined outcome' do
    collector.arm('cast #123')
    collector.arm('cast #123')
    expect(collector.result(context: context)).to include(outcome: :sent, reason: :multiple_attack_writes)
  end

  it 'ignores other players, other targets, inbound, foreign, unowned, redirected and orphan events' do
    [{ attacker: { id: -1 } }, { target: { id: 999 } }, { inbound: true }, { foreign_target: true },
     { foreign_caster: true }, { unowned: true }, { redirect: {} }, { _orphan: true }].each do |flags|
      instance = described_class.new(context: context, target_id: '123', clock: -> { 100.2 })
      instance.arm('attack #123')
      instance.enqueue(event.merge(flags).merge(source: event[:source].merge(received_at: 100.2)))
      expect(instance.result(context: context)[:outcome]).to eq(:sent)
    end
  end

  it 'never counts a miss with flare, status or zero-damage hit evidence as definite failure' do
    [{ flares: [{ hits: [{ damage: 5 }] }] }, { statuses: ['prone'] }, { hits: [{ damage: 0 }] }].each do |facts|
      instance = described_class.new(context: context, target_id: '123', clock: -> { 100.2 })
      instance.arm('attack #123')
      instance.enqueue(event.merge(facts).merge(source: event[:source].merge(received_at: 100.2)))
      expect(instance.result(context: context)[:outcome]).to eq(:sent)
    end
  end

  it 'waits for every batch index including foreign events before interpreting a root' do
    event[:observation_batch][:size] = 2
    expect(observe).to include(outcome: :sent, reason: :evidence_pending)
    foreign = event.merge(attacker: { id: -1 }, _uid: 1, root_uid: 1,
                          observation_batch: { id: 1, index: 1, size: 2 })
    collector.enqueue(foreign)
    expect(collector.result(context: context)[:outcome]).to eq(:ineffective)
  end

  it 'downgrades a root when its native child arrives later, even against another target' do
    event[:observation_batch][:size] = 2
    expect(observe[:reason]).to eq(:evidence_pending)
    collector.enqueue(event.merge(_uid: 1, parent_uid: 0, target: { id: 999 }, hits: [{ damage: 5 }],
                                  observation_batch: { id: 1, index: 1, size: 2 }))
    expect(collector.result(context: context)).to include(outcome: :sent, reason: :outcome_ambiguous)
  end

  it 'deduplicates native batch indices and detects multiple roots' do
    expect(observe[:outcome]).to eq(:ineffective)
    collector.enqueue(event)
    expect(collector.result(context: context)[:outcome]).to eq(:ineffective)
    collector.enqueue(event.merge(observation_batch: { id: 2, index: 0, size: 1 }))
    expect(collector.result(context: context)).to include(outcome: :sent, reason: :outcome_ambiguous)
  end

  it 'rejects delayed room/session evidence, already received chunks and pre-window events' do
    [{ room_epoch: 7 }, { connection_id: 6 }, { character: 'Other' }, { game: 'DR' },
     { sequence: 10 }, { received_at: 99.9 }, { received_at: 101.0 }].each do |change|
      instance = described_class.new(context: context, target_id: '123', clock: -> { 100.0 })
      instance.arm('attack #123')
      instance.enqueue(event.merge(source: event[:source].merge(change)))
      expect(instance.result(context: context)[:outcome]).to eq(:sent)
    end
    expect(observe[:outcome]).to eq(:ineffective)
    expect(collector.result(context: context.merge(room_epoch: 9))[:outcome]).to eq(:sent)
  end

  it 'returns uncertain on negative/backward clocks, unavailable contexts and missing batch metadata' do
    now[0] = -1
    collector.arm('attack #123')
    expect(collector.result(context: context)).to include(outcome: :sent, reason: :outcome_clock_invalid)
    missing = described_class.new(context: nil, target_id: '123')
    expect(missing.result(context: nil)[:outcome]).to eq(:sent)
    instance = described_class.new(context: context, target_id: '123', clock: -> { 100.2 })
    instance.arm('attack #123')
    instance.enqueue(event.reject { |key, _| key == :observation_batch })
    expect(instance.result(context: context)[:reason]).to eq(:outcome_batch_unavailable)
  end

  it 'copies only evidence facts so caller mutation cannot alter an admitted miss' do
    observe
    event[:outcomes].replace([:hit])
    event[:source][:character].replace('Changed')
    expect(collector.result(context: context)).to eq(outcome: :ineffective, reason: :native_failure_observed)
  end

  it 'rejects backwards clocks and malformed native facts without raising' do
    observe
    now[0] = 99.0
    expect(collector.result(context: context)[:reason]).to eq(:outcome_clock_invalid)
    [nil, [:unknown_native_outcome]].each do |outcomes|
      instance = described_class.new(context: context, target_id: '123', clock: -> { 100.2 })
      instance.arm('attack #123')
      instance.enqueue(event.merge(outcomes: outcomes).merge(source: event[:source].merge(received_at: 100.2)))
      expect(instance.result(context: context)[:outcome]).to eq(:sent)
    end
  end

  it 'counts foreign siblings delivered on observer threads without sharing mutable event trees' do
    event[:observation_batch][:size] = 2
    observe
    foreign = event.merge(attacker: { id: -1 }, _uid: 1, root_uid: 1,
                          observation_batch: { id: 1, index: 1, size: 2 })
    worker = Thread.new { collector.enqueue(foreign) }
    expect(worker.join(1)).to eq(worker)
    expect(collector.result(context: context)[:outcome]).to eq(:ineffective)
  end

  it 'treats another own root in the same completed batch as ambiguous multi-target evidence' do
    event[:observation_batch][:size] = 2
    observe
    collector.enqueue(event.merge(_uid: 1, root_uid: 1, target: { id: 999 },
                                  observation_batch: { id: 1, index: 1, size: 2 }))
    expect(collector.result(context: context)[:outcome]).to eq(:sent)
  end

  context 'with one event of capacity' do
    let(:capacity) { 1 }

    it 'latches queue overflow as uncertainty' do
      observe
      collector.enqueue(event.merge(observation_batch: { id: 2, index: 0, size: 1 }))
      expect(collector.result(context: context)).to include(outcome: :sent, reason: :outcome_queue_overflow)
    end
  end
end
