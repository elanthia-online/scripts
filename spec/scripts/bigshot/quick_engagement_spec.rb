# frozen_string_literal: true

# Synthetic projected-event fixtures, not live captures. Schema verified against
# Lich f1e7021675b868522272a7c305623268bb224ea0 combat/parser.rb parse_attack,
# processor.rb process/persist_event, defs/attacks.rb THIRD_PERSON_ATTACKS and
# spec/lib/gemstone/combat/processor_inbound_spec.rb's foreign-caster examples.
# No full Lich script or event parser is executed by this admission-layer suite.
module BigshotQuickEngagementSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  adapter = source[/^  class QuickEngagement\n.*?^  end$/m]
  raise 'QuickEngagement missing' unless adapter

  module_eval(adapter, __FILE__, __LINE__)
end

RSpec.describe BigshotQuickEngagementSpec::QuickEngagement do
  let(:adapter) { described_class.new }
  let(:event) do
    { name: :attack, _attack_born: true, foreign_caster: true,
      attacker: { id: -10, name: 'Ally' }, target: { id: 100, name: 'a rat' },
      at: Time.at(1_800_000_000), parent_uid: nil, hits: [] }
  end
  let(:source) { { session: 'generation-1'.dup, room_id: 42, room_epoch: 7, received_at: 10.0 } }
  let(:snapshot) do
    { session: 'generation-1', room_id: 42, room_epoch: 7, members_verified: true,
      members: [{ id: '-10', name: 'Ally' }], leader_id: '-10',
      targets: [{ id: '100', name: 'a rat', hostile: true, dead: false },
                { id: '101', name: 'a rat', hostile: true, dead: false }] }
  end

  def ingest(**overrides)
    adapter.ingest(**{ event: event, source: source, snapshot: snapshot, now: 10.5 }.merge(overrides))
  end

  it 'admits a group member initiation against its exact target among duplicate names' do
    expect(ingest).to include(accepted: true, evidence: include(member: 'Ally', actor_id: '-10', target_id: '100', at: 10.0))
    expect(ingest[:evidence][:event_at]).to eq(1_800_000_000.0)
  end

  it 'cannot authorize an ordinary native observer payload without independent source binding' do
    expect(ingest(source: nil)).to eq(accepted: false, reason: 'source_binding_unavailable')
    expect(ingest(source: source.reject { |key, _| key == :received_at })[:accepted]).to be(false)
    expect(ingest(source: source.merge(session: ''))[:accepted]).to be(false)
  end

  it 'rejects queued previous-room, previous-arrival and previous-session events' do
    adapter.enqueue(event, source: source)
    snapshot[:room_epoch] += 1
    expect(adapter.drain(snapshot: snapshot, now: 10.5).first[:reason]).to eq('room_changed')
    expect(ingest(source: source.merge(room_id: 43))[:reason]).to eq('room_changed')
    expect(ingest(source: source.merge(session: 'generation-0'))[:reason]).to eq('session_changed')
  end

  it 'rejects stale, future and invalid receipt times' do
    expect(ingest(now: 14.0)[:reason]).to eq('stale_event')
    expect(ingest(now: 9.9)[:reason]).to eq('stale_event')
    expect(ingest(source: source.merge(received_at: Float::NAN))[:accepted]).to be(false)
    expect(ingest(now: Float::INFINITY)[:reason]).to eq('invalid_clock')
  end

  it 'admits foreign_caster only with an exact present verified member identity' do
    event[:attacker] = { name: 'Ally' }
    expect(ingest[:reason]).to eq('missing_actor_id')
    event[:attacker][:id] = -11
    expect(ingest[:reason]).to eq('actor_not_current_member')
    event[:attacker][:id] = 10
    expect(ingest[:reason]).to eq('missing_actor_id')
    event[:attacker][:id] = -10
    snapshot[:members_verified] = false
    expect(ingest[:reason]).to eq('membership_unverified')
  end

  it 'rechecks leader departure and selection when draining' do
    adapter.enqueue(event, source: source)
    snapshot[:members] = []
    expect(adapter.drain(snapshot: snapshot, now: 10.5).first[:reason]).to eq('actor_not_current_member')
    snapshot[:members] = [{ id: '-10', name: 'Ally' }]
    snapshot[:leader_id] = '-11'
    expect(ingest[:reason]).to eq('actor_not_selected_leader')
    snapshot.delete(:leader_id)
    expect(ingest[:accepted]).to be(true)
  end

  it 'rejects inbound, foreign targets, effect ticks, continuations and unsupported families' do
    %i[inbound foreign_target unowned].each do |flag|
      expect(ingest(event: event.merge(flag => true))[:reason]).to eq('unsupported_event')
    end
    [event.merge(_attack_born: false), event.merge(name: :positioning_strike),
     event.merge(name: :pestilence), event.merge(parent_uid: 0),
     event.merge(parent_uid: {})].each do |payload|
      expect(ingest(event: payload)[:reason]).to eq('not_explicit_initiation')
    end
    expect(ingest(event: event.merge(at: nil))[:reason]).to eq('missing_event_time')
  end

  it 'rejects ambiguous, absent, friendly or dead targets and missing exact target IDs' do
    expect(ingest(event: event.merge(target: {}))[:reason]).to eq('missing_target_id')
    snapshot[:targets] << snapshot[:targets].first.dup
    expect(ingest[:reason]).to eq('ambiguous_target')
    snapshot[:targets].pop
    snapshot[:targets].first[:hostile] = false
    expect(ingest[:reason]).to eq('target_not_hostile')
    snapshot[:targets].first[:hostile] = true
    snapshot[:targets].first[:dead] = true
    expect(ingest[:reason]).to eq('target_not_alive')
    snapshot[:targets] = []
    expect(ingest[:reason]).to eq('target_not_present')
  end

  it 'rejects ambiguous member identity instead of using the first match' do
    snapshot[:members] << snapshot[:members].first.dup
    expect(ingest[:reason]).to eq('ambiguous_actor')
  end

  it 'bounds callback queue size and retains copied scalars independent of mutable events' do
    adapter = described_class.new(capacity: 1)
    event[:attacker][:id] = '-10'.dup
    expect(adapter.enqueue(event, source: source)).to eq(:queued)
    expect(adapter.enqueue(event, source: source)).to eq(:queue_full)
    event[:attacker][:id].replace('-99')
    source[:session].replace('changed')
    result = adapter.drain(snapshot: snapshot, now: 10.5).first
    expect(result[:accepted]).to be(true)
    expect(result[:evidence][:actor_id]).to eq('-10')
    expect(adapter.drain(snapshot: snapshot, now: 10.5)).to eq([])
  end

  it 'does not inspect unused damage arrays or accept malformed event envelopes' do
    event[:hits] = Object.new
    expect(adapter.enqueue(event, source: source)).to eq(:queued)
    expect(adapter.enqueue('quoted attack', source: source)).to eq(:malformed_event)
    expect(adapter.drain(snapshot: snapshot, now: 10.5).first[:accepted]).to be(true)
  end
end
