# frozen_string_literal: true

require_relative '../../spec_helper'

# RSpec for ELoot.silver_deposit(keep_hands: true) -- banking while a pool box is still in
# hand (a gold ingot trip from Sell.handle_ingot, or a box with more coins than the
# character can carry).
#
# Without it, silver_deposit calls use_coin_hand. With the coin bag kept inside a
# container, that frees a hand to drag the coin hand out. With an ingot in one hand and
# the box in the other, freeing a hand stows the box (the right hand unless favor_left).
# This runs the real silver_deposit and use_coin_hand. Inventory.free_hand is modeled on
# the real one: it does nothing while a hand is empty, otherwise it stows the right-hand item.
RSpec.describe 'ELoot.silver_deposit keep_hands' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(eloot_path) }

  let(:obj_class) { Struct.new(:id, :name, :noun) }
  let(:empty_hand) { obj_class.new(nil, 'Empty', nil) }
  let(:box) { obj_class.new('900', 'scuffed mithril box', 'box') }
  let(:ingot) { obj_class.new('100', 'bright gold ingot', 'ingot') }
  let(:coin_bag) { obj_class.new('300', 'leather coin bag', 'bag') }
  let(:cloak) { obj_class.new('400', 'black brocade warcloak', 'warcloak') }
  let(:calls) { [] }

  def harness(hands)
    recorder = calls
    silver = [8_980]
    empty = empty_hand
    bag = coin_bag
    settings = { sell_deposit_coinhand: false, sell_keep_silver: 0, sell_share_silvers: false }
    data = Struct.new(:coin_hand, :coin_bag, :coin_bag_full, :gambling_kit, :gambling_kit_full, :coin_container,
                      :settings, :deposit_regex, :withdraw_regex, :silent_open)
                 .new(bag, bag, false, nil, false, cloak, settings, /deposit/, /withdraw/, /open/)

    mod = Module.new
    mod.define_singleton_method(:refuse_room_operation!) { |_why| nil }
    mod.define_singleton_method(:msg) { |**| nil }
    mod.define_singleton_method(:data) { data }
    mod.define_singleton_method(:silver_check) { silver[0] }
    mod.define_singleton_method(:f2p?) { false }
    mod.define_singleton_method(:wait_rt) { nil }
    mod.define_singleton_method(:go2) { |place| recorder << [:go2, place] }
    mod.define_singleton_method(:fput) { |cmd| recorder << [:fput, cmd] }
    mod.define_singleton_method(:dothistimeout) do |cmd, _timeout, _regex|
      recorder << [:command, cmd]
      silver[0] = 0 if cmd == 'deposit all'
      ''
    end
    mod.const_set(:ELoot, mod)

    util = Module.new
    util.define_singleton_method(:issue_command) do |cmd, _regex|
      recorder << [:command, cmd]
      silver[0] = 0
      ['You place your silver in the coin bag.']
    end
    lich = Module.new
    lich.const_set(:Util, util)
    mod.const_set(:Lich, lich)

    xml = Module.new
    xml.define_singleton_method(:room_title) { '[Town Bank]' }
    mod.const_set(:XMLData, xml)

    gameobj = Module.new
    gameobj.define_singleton_method(:right_hand) { hands[0] }
    gameobj.define_singleton_method(:left_hand) { hands[1] }
    mod.const_set(:GameObj, gameobj)

    default_sack = Struct.new(:contents).new([])
    stow_list = Module.new
    stow_list.define_singleton_method(:stow_list) { { default: default_sack } }
    mod.const_set(:StowList, stow_list)

    inventory = Module.new
    inventory.define_singleton_method(:free_hand) do
      recorder << [:free_hand]
      next if hands.any? { |h| h.id.nil? }

      recorder << [:stowed, hands[0].id]
      hands[0] = empty
    end
    inventory.define_singleton_method(:open_single_container) { |c| recorder << [:open, c.id] }
    inventory.define_singleton_method(:drag) do |item|
      recorder << [:drag, item.id]
      slot = hands.index { |h| h.id.nil? }
      hands[slot] = item if slot
    end
    inventory.define_singleton_method(:single_drag) { |item| recorder << [:single_drag, item.id] }
    inventory.define_singleton_method(:store_item) { |bag_container, item| recorder << [:store_item, bag_container.id, item.id] }
    mod.const_set(:Inventory, inventory)

    %w[silver_deposit use_coin_hand].each do |name|
      mod.module_eval(extract_lic_method(source, name, source_path: eloot_path))
    end
    mod
  end

  def stowed = calls.select { |c| c.first == :stowed }.map(&:last)

  context 'with an ingot in one hand and the box in the other' do
    it 'stows the box without keep_hands (the path this guards against)' do
      harness([box, ingot]).silver_deposit

      expect(stowed).to include(box.id)
    end

    it 'keeps the box in hand and still banks the coins with keep_hands' do
      hands = [box, ingot]
      harness(hands).silver_deposit(keep_hands: true)

      expect(stowed).to be_empty
      expect(hands).to include(box)
      expect(calls).not_to include([:drag, coin_bag.id])
      expect(calls).to include([:go2, 'bank'], [:command, 'deposit all'])
    end
  end

  context 'with the box in one hand and the other hand empty' do
    it 'stows the box without keep_hands once the coin bag fills the free hand' do
      harness([box, empty_hand]).silver_deposit

      expect(stowed).to include(box.id)
    end

    it 'keeps the box in hand with keep_hands' do
      hands = [box, empty_hand]
      harness(hands).silver_deposit(keep_hands: true)

      expect(stowed).to be_empty
      expect(hands).to include(box)
      expect(calls).to include([:command, 'deposit all'])
    end
  end
end
