# frozen_string_literal: true

require_relative '../../spec_helper'

# RSpec for ELoot::Loot.pool_sell_recovery -- the disk-park recovery for a full inventory
# during a locksmith pool return, used when a box still holds something nothing will buy.
# It returns the stuck item to the box, parks the box on a disk, runs a box-skipping sell
# trip to free space, then goes back to the pool and re-loots the box.
#
# Replays a reported log (2026-11-01), trimmed:
#   07:26:28  a polished hornsnail shell won't fit; the boarhide pack is marked full
#   07:26:35  1 item(s) left with nowhere to sell. Parking the box, ...
#   07:26:36  You put a scuffed mithril box in the <name> disk.
#   07:26:38  The jeweler Kahlyr removes the gems and hands you a Vornavis promissory note
#   07:26:39  Sacks Full[bristly boarhide pack]: [... "polished hornsnail shell(1211317152)"]
#   07:26:39  Failed to store the promissory note.
# The jeweler had just emptied the pack, but it was still marked full during the trip, so
# the note had nowhere to go and eloot paused.
RSpec.describe 'ELoot::Loot.pool_sell_recovery' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(eloot_path) }

  let(:pack) { 'bristly boarhide pack' }
  let(:hand_class) { Struct.new(:id, :name, :noun) }
  let(:empty_hand) { hand_class.new(nil, 'Empty', nil) }
  let(:box) { Struct.new(:id, :name, :contents).new('1211317147', 'a scuffed mithril box', [Object.new]) }
  let(:shell) { hand_class.new('1211317152', 'polished hornsnail shell', 'shell') }
  let(:right_hand) { shell }
  let(:left_hand) { empty_hand }
  let(:parks_on_disk) { true }
  let(:calls) { [] }
  let(:data) { Hash.new(0) }
  let(:sacks_full) { { 'last cleared' => ['2026-11-01 07:25:16', 1448, 'sell'], pack => ['2026-11-01 07:26:28', 28719, 'polished hornsnail shell(1211317152)'] } }

  let(:eloot_data) do
    Struct.new(:sacks_full, :put_regex).new(sacks_full, /put/)
  end

  let(:harness) do
    recorder = calls
    the_box = box
    the_pack = pack
    hands = [right_hand, left_hand]
    parks = parks_on_disk
    store = eloot_data

    mod = Module.new
    mod.define_singleton_method(:msg) { |**kw| recorder << [:msg, kw[:text]] }
    mod.define_singleton_method(:go2) { |place| recorder << [:go2, place] }
    mod.define_singleton_method(:get_command) { |cmd, _regex, **| recorder << [:get_command, cmd] && [] }
    mod.define_singleton_method(:in_hand?) { |item| hands.any? { |h| h.id == item.id } }
    mod.define_singleton_method(:data) { store }
    mod.define_singleton_method(:reset_disk_full) { recorder << [:reset_disk_full] }
    mod.const_set(:ELoot, mod)

    room = Module.new
    current = Module.new
    current.define_singleton_method(:id) { 28719 }
    room.define_singleton_method(:current) { current }
    mod.const_set(:Room, room)

    gameobj = Module.new
    gameobj.define_singleton_method(:right_hand) { hands[0] }
    gameobj.define_singleton_method(:left_hand) { hands[1] }
    mod.const_set(:GameObj, gameobj)

    inventory = Module.new
    inventory.define_singleton_method(:single_drag_box) { |b| recorder << [:single_drag_box, b.id] && parks }
    inventory.define_singleton_method(:drag) { |item| recorder << [:drag, item.id] }
    mod.const_set(:Inventory, inventory)

    script = Module.new
    current_script = Object.new
    current_script.define_singleton_method(:name) { 'eloot' }
    current_script.define_singleton_method(:vars) { ['sell'] }
    current_script.define_singleton_method(:pause) { recorder << [:pause] }
    script.define_singleton_method(:current) { current_script }
    mod.const_set(:Script, script)

    mod.define_singleton_method(:box_loot) { |b, location, _data, **kw| recorder << [:box_loot, b.id, location, kw] }
    mod.const_set(:Loot, mod)

    # The sell trip: the jeweler empties the pack and pays with a note, which is stowed
    # while the trip is still running. Record what the full tracking says at that point.
    sell = Module.new
    sell.define_singleton_method(:sell) do |**kw|
      recorder << [:sell, kw, { box_protected: $sell_ignore.include?(the_box.id), pack_full: store.sacks_full.key?(the_pack) }]
    end
    mod.const_set(:Sell, sell)

    mod.module_eval(extract_lic_method(source, 'pool_sell_recovery', source_path: eloot_path))
    mod
  end

  before { $sell_ignore = [] }
  after { $sell_ignore = [] }

  def order = calls.map(&:first)
  def sell_call = calls.find { |c| c.first == :sell }

  context 'when the box can be parked on a disk' do
    it 'puts the stuck item back in the box before parking it' do
      harness.pool_sell_recovery(box, 'Solhaven', data)

      expect(calls).to include([:get_command, "put ##{shell.id} in ##{box.id}"])
      expect(calls.index([:get_command, "put ##{shell.id} in ##{box.id}"])).to be < calls.index([:single_drag_box, box.id])
    end

    it 'no longer counts an emptied container as full while the sell trip stows its payment' do
      harness.pool_sell_recovery(box, 'Solhaven', data)

      expect(sell_call[1]).to eq(skip_boxes: true)
      expect(sell_call[2][:pack_full]).to be(false)
      expect(order.index(:reset_disk_full)).to be < order.index(:sell)
    end

    it 'clears the full tracking again after the sell trip' do
      harness.pool_sell_recovery(box, 'Solhaven', data)

      expect(order.rindex(:reset_disk_full)).to be > order.index(:sell)
      expect(eloot_data.sacks_full.keys).to eq(['last cleared'])
    end

    it 'keeps the parked box out of the sell trip, then re-loots it at the pool once' do
      result = harness.pool_sell_recovery(box, 'Solhaven', data)

      expect(result).to eq(:recovered)
      expect(sell_call[2][:box_protected]).to be(true)
      expect($sell_ignore).not_to include(box.id)

      after_sell = calls.drop(order.index(:sell) + 1)
      expect(after_sell.map(&:first) - [:msg]).to eq(%i[reset_disk_full go2 drag box_loot])
      expect(after_sell).to include([:go2, 28719], [:drag, box.id], [:box_loot, box.id, 'Solhaven', { sell_recovered: true }])
      expect(order).not_to include(:pause)
    end

    context 'when a promissory note is in hand' do
      let(:right_hand) { hand_class.new('1211327406', 'Vornavis promissory note', 'note') }

      it 'never puts the note into the box, which gets trashed' do
        harness.pool_sell_recovery(box, 'Solhaven', data)

        expect(calls.select { |c| c.first == :get_command }).to be_empty
      end
    end

    context 'when the box itself is in hand' do
      let(:right_hand) { box }

      it 'does not try to put the box into itself' do
        harness.pool_sell_recovery(box, 'Solhaven', data)

        expect(calls.select { |c| c.first == :get_command }).to be_empty
      end
    end
  end

  context 'when no disk can take the box' do
    let(:parks_on_disk) { false }

    it 'pauses for the player, then clears the full tracking and re-loots without a sell trip' do
      result = harness.pool_sell_recovery(box, 'Solhaven', data)

      expect(result).to eq(:recovered)
      expect(order).to include(:pause)
      expect(order).not_to include(:sell)
      expect(order.index(:pause)).to be < order.index(:reset_disk_full)
      expect(eloot_data.sacks_full.keys).to eq(['last cleared'])
      expect(eloot_data.sacks_full['last cleared'].last).to eq('unpause')
      expect(calls).to include([:box_loot, box.id, 'Solhaven', { sell_recovered: true }])
      expect($sell_ignore).to be_empty
    end
  end
end
