# frozen_string_literal: true

require_relative '../../spec_helper'

# A creature that can never yield a skin is added to the unskinnable list so later
# corpses of it are not knelt over and skinned again. Reported from OSA:
# "The Krolvin Captain's skin has been ruined with alchemical components; it's not
# possible to get a worthwhile skin."
RSpec.describe 'ELoot::Loot.skin_obj_types unskinnable creatures' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(eloot_path) }

  let(:obj) { Struct.new(:id, :name) }
  let(:corpse) { obj.new('1145538296', 'Krolvin Captain') }
  let(:knife) { obj.new('1', 'skinning knife') }
  let(:settings) { { unskinnable: [], skin_kneel: false, skin_resolve: false, skin_604: false } }
  let(:saved) { [] }

  let(:loot) do
    reply = skin_reply
    Module.new do
      define_singleton_method(:waitrt?) { nil }
      define_singleton_method(:dothistimeout) { |*| reply }
      define_singleton_method(:fput) { |*| nil }
    end
  end

  before do
    data = Struct.new(:settings, :weapon_inv).new(settings, [])
    saves = saved
    held = knife
    stub_const('ELoot', Module.new do
      define_singleton_method(:data) { data }
      define_singleton_method(:msg) { |**| nil }
      define_singleton_method(:ensure_items) { |**| nil }
      define_singleton_method(:in_hand?) { |_| true }
      define_singleton_method(:save_profile) { saves << data.settings[:unskinnable].dup }
    end)
    stub_const('ReadyList', Module.new { define_singleton_method(:ready_list) { { skin_weapon: held } } })
    stub_const('GameObj', Module.new do
      define_singleton_method(:left_hand) { Struct.new(:id).new('0') }
      define_singleton_method(:targets) { [] }
    end)
    loot.module_eval(extract_lic_method(source, 'skin_obj_types', source_path: eloot_path))
  end

  context 'when the skin is ruined with alchemical components' do
    let(:skin_reply) do
      "The Krolvin Captain's skin has been ruined with alchemical components; it's not possible to get a worthwhile skin."
    end

    it 'learns the creature as unskinnable' do
      loot.skin_obj_types([corpse], :normal)

      expect(settings[:unskinnable]).to eq(['Krolvin Captain'])
      expect(saved).to eq([['Krolvin Captain']])
    end
  end

  context 'when the skinning is botched' do
    let(:skin_reply) { 'You botched the attempt' }

    it 'keeps skinning the creature next time' do
      loot.skin_obj_types([corpse], :normal)

      expect(settings[:unskinnable]).to be_empty
    end
  end
end
