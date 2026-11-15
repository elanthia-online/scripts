# frozen_string_literal: true

require_relative '../../spec_helper'

# RSpec for ELoot::Sell.handle_ingot -- a bright gold ingot taken out of a box at the
# locksmith pool that will not fit in any container.
#
# Reported behavior (user report, 2026-11): with a dozen ingots already in the knapsack,
# every new ingot sent the character to the gemshop to sell just that one ingot and
# straight back to the pool. The coins piled up until the pool refused the next box
# ("You need to lighten your load first"), which forced a separate bank trip, then the
# next ingot started the cycle again. The fix sells every stored ingot in the same trip
# and banks the coins before going back.
RSpec.describe 'ELoot::Sell.handle_ingot' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(eloot_path) }

  let(:obj_class) { Struct.new(:id, :name, :noun, :type) }
  let(:empty_hand) { obj_class.new(nil, 'Empty', nil, nil) }
  let(:box) { obj_class.new('900', 'scuffed mithril box', 'box', 'box') }
  let(:stuck) { obj_class.new('100', 'bright gold ingot', 'ingot', 'valuable') }
  let(:stored) { %w[101 102 103].map { |id| obj_class.new(id, 'bright gold ingot', 'ingot', 'valuable') } }
  let(:gem) { obj_class.new('200', 'uncut diamond', 'diamond', 'gem') }
  let(:knapsack) { Struct.new(:id, :name, :contents).new('500', 'knapsack', stored + [gem]) }
  let(:refused_ids) { [] }
  let(:sell_exclude) { /(?!)/ }
  let(:sell_types) { %w[gem valuable] }
  let(:selling_containers) { [knapsack] }
  let(:calls) { [] }
  let(:breakdown) { Hash.new(0) }

  let(:harness) do
    recorder = calls
    hands = [stuck, box]
    sack = knapsack
    types = sell_types
    sacks = selling_containers
    refused = refused_ids
    silver = [0]
    empty = empty_hand
    ledger = breakdown
    data = Struct.new(:silver_breakdown, :sell_exclude_regex, :put_regex).new(ledger, sell_exclude, /put/)

    mod = Module.new
    mod.define_singleton_method(:go2) { |place| recorder << [:go2, place] }
    mod.define_singleton_method(:silver_check) { silver[0] }
    mod.define_singleton_method(:silver_deposit) { recorder << [:silver_deposit, ledger['Gemshop']] }
    mod.define_singleton_method(:in_hand?) { |item| hands.any? { |h| h.id == item.id } }
    mod.define_singleton_method(:data) { data }
    mod.define_singleton_method(:set_selling_containers) { |type:| recorder << [:set_selling_containers, type] && sacks }
    mod.define_singleton_method(:fresh_contents) { |container| recorder << [:look, container.id] && container.contents.to_a }
    mod.define_singleton_method(:get_command) do |cmd, _regex, **|
      recorder << [:get_command, cmd]
      if (m = cmd.match(/^put #(\d+) in #(\d+)/))
        slot = hands.index { |h| h.id == m[1] }
        hands[slot] = empty if slot
      end
      []
    end
    mod.const_set(:ELoot, mod)

    room = Module.new
    current = Module.new
    current.define_singleton_method(:id) { 4242 }
    room.define_singleton_method(:current) { current }
    mod.const_set(:Room, room)

    gameobj = Module.new
    gameobj.define_singleton_method(:right_hand) { hands[0] }
    gameobj.define_singleton_method(:left_hand) { hands[1] }
    mod.const_set(:GameObj, gameobj)

    inventory = Module.new
    inventory.define_singleton_method(:drag) do |item|
      recorder << [:drag, item.id]
      slot = hands.index { |h| h.id.nil? }
      raise 'drag would have freed a hand' unless slot

      hands[slot] = item
      sack.contents.delete(item)
      true
    end
    inventory.define_singleton_method(:single_drag) { |item| recorder << [:single_drag, item.id] }
    mod.const_set(:Inventory, inventory)

    sell = mod
    sell.define_singleton_method(:sell_item) do |item, place, _data|
      recorder << [:sell_item, item.id, place]
      next if refused.include?(item.id)

      hands[hands.index { |h| h.id == item.id }] = empty
      silver[0] += 2_245
    end
    sell.define_singleton_method(:selling_type?) { |obj| types.include?(obj.type) }
    mod.const_set(:Sell, sell)

    %w[handle_ingot sell_stored_ingots sell_stored_ingot stow_held_note].each do |name|
      mod.module_eval(extract_lic_method(source, name, source_path: eloot_path))
    end
    mod.define_singleton_method(:hands) { hands }
    mod
  end

  before { $sell_ignore = [] }
  after { $sell_ignore = [] }

  def order = calls.map(&:first)
  def sold = calls.select { |c| c.first == :sell_item }.map { |c| c[1] }

  it 'sells the stuck ingot and every stored ingot in one gemshop trip' do
    harness.handle_ingot(stuck)

    expect(calls.select { |c| c.first == :go2 }).to eq([[:go2, 'gemshop'], [:go2, 4242]])
    expect(sold).to eq(%w[100 101 102 103])
    expect(sold).not_to include(gem.id)
  end

  it 'keeps the box in hand the whole time' do
    harness.handle_ingot(stuck)

    expect(harness.hands).to include(box)
    expect(calls).not_to include([:drag, box.id])
  end

  it 'counts the sales before banking, then banks before heading back' do
    harness.handle_ingot(stuck)

    expect(calls).to include([:silver_deposit, 4 * 2_245])
    expect(order.index(:silver_deposit)).to be > order.rindex(:sell_item)
    expect(order.index(:silver_deposit)).to be < calls.index([:go2, 4242])
  end

  context 'when the dealer refuses a stored ingot' do
    let(:refused_ids) { ['102'] }

    it 'puts it back where it came from and stops trying' do
      harness.handle_ingot(stuck)

      expect(sold).to eq(%w[100 101 102])
      expect(calls).to include([:get_command, "put #102 in ##{knapsack.id}"])
      expect($sell_ignore).to include('102')
      expect(harness.hands).to include(box)
      expect(order).to include(:silver_deposit)
    end
  end

  context 'when the dealer refuses the stuck ingot' do
    let(:refused_ids) { ['100'] }

    it 'does not pull stored ingots into hand' do
      harness.handle_ingot(stuck)

      expect(sold).to eq(%w[100])
      expect(order).not_to include(:drag)
    end
  end

  it 'looks in the same containers a normal gemshop pass sells from' do
    harness.handle_ingot(stuck)

    expect(calls).to include([:set_selling_containers, 'gem'])
  end

  context 'when the knapsack is not a selling container' do
    let(:selling_containers) { [] }

    it 'leaves its ingots alone but still banks the coins' do
      harness.handle_ingot(stuck)

      expect(sold).to eq(%w[100])
      expect(order).not_to include(:look)
      expect(calls).to include([:silver_deposit, 2_245])
    end
  end

  context 'when valuables are not a selling type' do
    let(:sell_types) { %w[gem] }

    it 'still sells the stuck ingot, leaves the stored ones, and banks the coins' do
      harness.handle_ingot(stuck)

      expect(sold).to eq(%w[100])
      expect(calls).to include([:silver_deposit, 2_245])
      expect(calls.select { |c| c.first == :go2 }).to eq([[:go2, 'gemshop'], [:go2, 4242]])
    end
  end

  context 'when stored ingots are on the sell exclude list' do
    let(:sell_exclude) { /\bbright gold ingot\b/ }

    it 'leaves them alone' do
      harness.handle_ingot(stuck)

      expect(sold).to eq(%w[100])
    end
  end
end
