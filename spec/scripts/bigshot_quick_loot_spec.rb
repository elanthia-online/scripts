# frozen_string_literal: true

module BigshotQuickLootSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[QuickLoot].each do |name|
    body = source[/^  class #{name}\n.*?^  end$/m]
    raise "could not extract #{name}" unless body
    module_eval(body)
  end
end

RSpec.describe BigshotQuickLootSpec::QuickLoot do
  let(:settings) { { 'loot' => 'room', 'max_actions' => 5, 'max_seconds' => 10 } }
  let(:now) { [100.0] }
  let(:loot) { described_class.new(settings, character: 'Tester', clock: -> { now.first }) }
  let(:snapshot) do
    { session: 'login', room_id: 100, room_epoch: 1, targets: [],
      corpses: [{ id: '123' }, { id: '124' }], loot_ids: ['789'] }
  end
  let(:calls) { [] }
  let(:dispatch) { ->(**args) { calls << args; { outcome: :complete, sends: 1 } } }

  def tick
    loot.call(snapshot: snapshot, attacked_ids: ['123'], dispatch: dispatch)
  end

  it 'gives cold eLoot initialization an independent bounded budget' do
    tick
    expect(calls.first).to include(max_actions: 60, max_seconds: 60)
  end

  it 'uses explicit loot limits without borrowing the combat limits' do
    settings.merge!('loot_max_actions' => 35, 'loot_max_seconds' => 45)
    tick
    expect(calls.first).to include(max_actions: 35, max_seconds: 45)
  end

  it 'searches one corpse per owner tick, then the room, without repeating idle snapshots' do
    3.times { expect(tick).to eq(outcome: :pending) }
    5.times { expect(tick).to eq(outcome: :complete) }
    expect(calls.map { |call| call[:command] }).to eq(['loot #123', 'loot #124', 'loot room'])
    expect(loot.sends).to eq(3)
  end

  it 'limits own-kills to targets engaged by this run and never takes floor loot' do
    settings['loot'] = 'own-kills'
    expect(tick).to eq(outcome: :pending)
    expect(tick).to eq(outcome: :complete)
    expect(calls.map { |call| call[:command] }).to eq(['loot #123'])
  end

  it 'does nothing when disabled, assigned to another player, or a hostile is still alive' do
    settings['loot'] = 'off'
    expect(tick).to eq(outcome: :complete)
    other = described_class.new(settings.merge('loot' => 'room', 'looter' => 'Friend'), character: 'Tester')
    expect(other.call(snapshot: snapshot, attacked_ids: [], dispatch: dispatch)).to eq(outcome: :complete)
    settings['loot'] = 'room'
    active = described_class.new(settings, character: 'Tester')
    snapshot[:targets] = [{ id: '999', hostile: true }]
    expect(active.call(snapshot: snapshot, attacked_ids: [], dispatch: dispatch)).to eq(outcome: :complete)
    expect(calls).to be_empty
  end

  it 'matches the designated looter case-insensitively' do
    settings['looter'] = 'tEsTeR'
    expect(tick).to eq(outcome: :pending)
  end

  it 'does not invoke loot room in every empty room' do
    snapshot[:corpses] = []
    snapshot[:loot_ids] = []
    5.times do
      snapshot[:room_epoch] += 1
      expect(tick).to eq(outcome: :complete)
    end
    expect(calls).to be_empty
  end

  it 'notices new floor items without re-looting an unchanged floor' do
    snapshot[:corpses] = []
    tick
    expect(tick).to eq(outcome: :complete)
    snapshot[:loot_ids] << '790'
    expect(tick).to eq(outcome: :pending)
    expect(calls.length).to eq(2)
  end

  it 'resets per-room accounting on a new room epoch, even for the same room id' do
    tick
    snapshot[:room_epoch] += 1
    tick
    expect(calls.map { |call| call[:command] }).to eq(['loot #123', 'loot #123'])
  end

  it 'charges retry sends and interrupts at the room cleanup action limit' do
    settings['loot_max_actions'] = 2
    tick
    tick
    expect(tick).to eq(outcome: :interrupted, reason: 'loot_action_limit')
    expect(calls.map { |call| call[:max_actions] }).to eq([2, 1])
  end

  it 'bounds cleanup time from its first command, not the beginning of the hunt' do
    settings['loot_max_seconds'] = 10
    now[0] += 100
    tick
    now[0] += 10
    expect(tick).to eq(outcome: :interrupted, reason: 'loot_time_limit')
    expect(calls.length).to eq(1)
  end

  it 'returns an interruption and its real send count rather than claiming successful loot' do
    dispatch = ->(**_args) { { outcome: :interrupted, sends: 2, reason: 'held' } }
    expect(loot.call(snapshot: snapshot, attacked_ids: [], dispatch: dispatch)).to include(outcome: :interrupted, reason: 'held')
    expect(loot.sends).to eq(2)
  end

  it 'rejects malformed corpse identity without interpolating it into a command' do
    snapshot[:corpses] = [{ id: '123;east' }]
    expect(tick).to eq(outcome: :interrupted, reason: 'loot_identity_invalid')
    expect(calls).to be_empty
  end

  it 'deduplicates a corpse that eLoot deliberately skips without claiming a game send' do
    snapshot[:corpses] = [{ id: '123' }]
    snapshot[:loot_ids] = []
    skipped = ->(**args) { calls << args; { outcome: :complete, sends: 0 } }
    expect(loot.call(snapshot: snapshot, attacked_ids: [], dispatch: skipped)).to eq(outcome: :pending)
    expect(loot.call(snapshot: snapshot, attacked_ids: [], dispatch: skipped)).to eq(outcome: :complete)
    expect(calls.length).to eq(1)
    expect(loot.sends).to eq(0)
  end
end
