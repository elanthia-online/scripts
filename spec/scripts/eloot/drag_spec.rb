# frozen_string_literal: true

require_relative '../../spec_helper'

# The per-item sell loops skip an item when Inventory.drag returns false, so false has to
# mean the item really isn't coming: a slow reply (the first line back being room chatter)
# must still count once the item lands in hand, and a lost item found on a second look
# must count too.
RSpec.describe 'ELoot::Inventory.drag' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(eloot_path) }

  let(:obj) { Struct.new(:id, :name) { def empty? = false } }
  let(:skin) { obj.new('981782679', 'mottled kiramon poison gland') }

  # tenths of a second waited, and the tenth at which the item shows up in hand
  let(:clock) { { now: 0 } }
  let(:in_hand_at) { nil }
  let(:reply) { 'Bob just arrived.' }
  let(:found_on_second_look) { [] }
  let(:drags) { [] }

  let(:inventory) do
    clock = self.clock
    Module.new do
      define_singleton_method(:free_hand) { nil }
      define_singleton_method(:free_hands) { |**| nil }
      define_singleton_method(:open_single_container) { |_| nil }
      define_singleton_method(:sleep) { |_| clock[:now] += 1 }
    end
  end

  before do
    clock = self.clock
    at = in_hand_at
    first_reply = reply
    found = found_on_second_look
    drags = self.drags
    stub_const('Inventory', inventory)
    stub_const('ELoot', Module.new do
      define_singleton_method(:msg) { |**| nil }
      define_singleton_method(:get_res) do |command|
        drags << command[/#(\d+)/, 1]
        drags.size > 1 ? 'You remove a gland.' : first_reply
      end
      define_singleton_method(:in_hand?) { |_| !at.nil? && clock[:now] >= at }
    end)
    stub_const('GameObj', Module.new { define_singleton_method(:right_hand) { Struct.new(:id).new(nil) } })
    stub_const('StowList', Module.new { define_singleton_method(:stow_list) { {} } })
    stub_const('Sell', Module.new { define_singleton_method(:check_inventory) { found } })
    inventory.module_eval(extract_lic_method(source, 'drag', source_path: eloot_path))
  end

  context 'when the first line back is room chatter and the item lands in hand at 2.5s' do
    let(:in_hand_at) { 25 }

    it 'counts the drag' do
      expect(inventory.drag(skin)).to be true
    end
  end

  context 'when the item never shows up' do
    it 'gives up after about 5s' do
      expect(inventory.drag(skin)).to be false
      expect(clock[:now]).to eq(50)
    end
  end

  context 'when the game says the item is not there' do
    let(:reply) { 'I could not find what you were referring to.' }

    it 'returns false without waiting' do
      expect(inventory.drag(skin)).to be false
      expect(clock[:now]).to eq(0)
    end

    context 'and a second look finds it in another bag' do
      let(:found_on_second_look) { [skin] }
      let(:in_hand_at) { 1 }

      it 'counts the retried drag' do
        expect(inventory.drag(skin)).to be true
        expect(drags).to eq([skin.id, skin.id])
      end
    end
  end
end
