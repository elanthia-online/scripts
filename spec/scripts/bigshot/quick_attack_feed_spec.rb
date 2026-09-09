# frozen_string_literal: true

# Synthetic stream fixtures. Native definition shape copied from Lich f1e70216
# combat/defs/attacks.rb THIRD_PERSON_ATTACKS (:attack). The injected parser is
# a fixture stand-in; these tests establish adapter admission, not live coverage.
module BigshotQuickAttackFeedSpec
  source = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[QuickEngagement QuickAttackFeed].each do |name|
    klass = source[/^  class #{name}\n.*?^  end$/m]
    raise "#{name} missing" unless klass

    module_eval(klass, __FILE__, __LINE__)
  end
end

RSpec.describe BigshotQuickAttackFeedSpec::QuickAttackFeed do
  let(:native_pattern) { /(?<attacker>.+?) swings (?<weapon>.+?) at (?<target>.+?)(?: in a murderous arc)?!/ }
  let(:actor) { '<a exist="-10" noun="Ally">Ally</a>' }
  let(:target) { '<pushBold/>a <a exist="100" noun="rat">rat</a><popBold/>' }
  let(:line) { "#{actor} swings a sword at #{target}!\r\n" }
  let(:snapshot) do
    { session: 'session-1', room_id: 42, room_epoch: 3, main_stream: true, received_at: 10.0,
      members_verified: true, members: [{ id: '-10', name: 'Ally' }],
      targets: [{ id: '100', hostile: true, dead: false }] }
  end
  let(:event) { { name: :attack, foreign_caster: true, attacker: { id: -10 }, target: { id: 100 } } }
  let(:parsed) { [] }
  let(:parse) { ->(text) { parsed << text; event } }
  let(:queue) { BigshotQuickAttackFeedSpec::QuickEngagement.new }
  let(:feed) do
    described_class.new(parse: parse, attacks: [[native_pattern, :attack]],
                        snapshot: -> { snapshot }, clock: -> { 10.0 },
                        wall_clock: -> { Time.at(1000) }, engagement: queue)
  end

  it 'binds a native complete initiation synchronously and queues independently checked evidence' do
    expect(feed.feed(line)).to eq([{ accepted: true, reason: 'queued' }])
    expect(parsed).to eq([line.strip])
    expect(queue.drain(snapshot: snapshot, now: 10.1).first).to include(
      accepted: true, evidence: include(room_id: 42, room_epoch: 3, session: 'session-1', target_id: '100')
    )
    expect(event).not_to have_key(:_attack_born)
  end

  it 'rejects unavailable and invalid source times without substituting the hook clock' do
    [nil, -1.0, Float::NAN, Float::INFINITY, 11.0].each do |received|
      snapshot[:received_at] = received
      expect(feed.feed(line).first[:accepted]).to be(false)
    end
    expect(queue.drain(snapshot: snapshot, now: 10.1)).to be_empty
  end

  it 'uses the original ingress for staleness and the current clock only for comparison' do
    snapshot[:received_at] = 1.0
    expect(feed.feed(line).first[:reason]).to eq('stale_event')
    expect(queue.drain(snapshot: snapshot, now: 10.1)).to be_empty
  end

  it 'rejects speech containing an inner attack even when the native regex matches it' do
    expect(feed.feed("#{actor} says, \"#{line.strip}\"\n").first[:accepted]).to be(false)
    expect(feed.feed("You hear, \"#{line.strip}\"\n").first[:accepted]).to be(false)
    expect(parsed).to be_empty
  end

  it 'rejects protocol-bearing chunks including mixed transitions, stream switches and attacks' do
    ["<popStream id=\"room\"/>#{line}", "<nav rm=\"43\"/>\n#{line}",
     "<pushStream id=\"thoughts\"/>#{line}", "#{line}<prompt time=\"1000\">&gt;</prompt>\n"].each do |chunk|
      expect(feed.feed(chunk).first[:reason]).to eq('protocol_chunk')
    end
    expect(parsed).to be_empty
  end

  it 'rejects unverified streams and membership without triggering any refresh' do
    snapshot[:main_stream] = false
    expect(feed.feed(line).first[:reason]).to eq('stream_unverified')
    snapshot[:main_stream] = true
    snapshot[:members_verified] = false
    expect(feed.feed(line).first[:reason]).to eq('membership_unverified')
    expect(queue.drain(snapshot: snapshot, now: 10.1)).to be_empty
  end

  it 'rejects malformed links or unbalanced bold markup before parsing' do
    expect(feed.feed(line.sub('</a>', '')).first[:reason]).to eq('protocol_chunk')
    expect(feed.feed(line.sub('<popBold/>', '')).first[:reason]).to eq('malformed_markup')
    expect(feed.feed(line.sub('<pushBold/>', '')).first[:reason]).to eq('malformed_markup')
    expect(parsed).to be_empty
  end

  it 'does not join incomplete chunks or accept their suffix as a fresh attack' do
    expect(feed.feed('fragment').first[:reason]).to eq('partial_chunk')
    expect(feed.feed(line).first[:reason]).to eq('partial_chunk')
    expect(parsed).to be_empty
    expect(feed.feed(line).first[:accepted]).to be(true)
  end

  it 'accepts complete protocol-free lines individually within a bounded chunk' do
    expect(feed.feed(line + line).map { |result| result[:accepted] }).to eq([true, true])
    expect(feed.feed(line * 33).first[:reason]).to eq('chunk_limit')
    expect(feed.feed(('x' * 8193) + "\n").first[:reason]).to eq('chunk_limit')
  end

  it 'rejects context changes during parsing and after queuing' do
    allow(parse).to receive(:call) { snapshot[:room_epoch] += 1; event }
    expect(feed.feed(line).first[:reason]).to eq('source_changed')
    expect(queue.drain(snapshot: snapshot, now: 10.1)).to be_empty
    allow(parse).to receive(:call).and_return(event)
    feed.feed(line)
    snapshot[:session] = 'session-2'
    expect(queue.drain(snapshot: snapshot, now: 10.1).first[:reason]).to eq('session_changed')
  end

  it 'rejects queued old-roster attacks even when the attacker remains present' do
    feed.feed(line)
    snapshot[:members] << { id: '-11', name: 'NewMember' }
    expect(queue.drain(snapshot: snapshot, now: 10.1).first[:reason]).to eq('membership_changed')
    expect(feed.feed(line).first[:accepted]).to be(true)
    result = queue.drain(snapshot: snapshot, now: 10.1).first
    expect(result[:accepted]).to be(true)
    expect(result[:evidence][:member_roster]).to eq([['-10', 'Ally'], ['-11', 'NewMember']])
    expect(result[:evidence][:member_roster]).to be_frozen
  end

  it 'rejects ambiguous target markup or disagreement with the parser' do
    expect(feed.feed("#{actor} swings a sword at #{target} and #{target}!\n").first[:reason]).to eq('ambiguous_target_markup')
    event[:target][:id] = 101
    expect(feed.feed(line).first[:reason]).to eq('parser_mismatch')
  end

  it 'fails closed on parser failure and queue exhaustion' do
    allow(queue).to receive(:enqueue).and_return(:queue_full)
    expect(feed.feed(line).first).to eq(accepted: false, reason: 'queue_full')
    allow(parse).to receive(:call).and_raise('bad parser')
    expect(feed.feed(line).first).to eq(accepted: false, reason: 'feed_error')
  end
end
