# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'ELoot unskinnable-list management' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: __dir__) }
  let(:source) { File.read(eloot_path) }
  let(:settings) { { unskinnable: ['massive troll king', 'greater earth elemental'] } }
  let(:data) { Struct.new(:settings).new(settings) }
  let(:messages) { [] }

  let(:eloot) do
    data_object = data
    message_log = messages
    method_body = extract_lic_method(source, 'manage_unskinnable', source_path: eloot_path)

    Module.new do
      singleton_class.attr_accessor :save_count
      self.save_count = 0

      const_set(:ELoot, self)
      define_singleton_method(:data) { data_object }
      define_singleton_method(:save_profile) { |**| self.save_count += 1 }
      define_singleton_method(:msg) { |**message| message_log << message }
      module_eval(method_body)
    end
  end

  it 'clears the learned list and persists once' do
    eloot.manage_unskinnable('reset')

    expect(settings[:unskinnable]).to be_empty
    expect(eloot.save_count).to eq(1)
    expect(messages.last[:text]).to include('Cleared 2 creatures')
  end

  it 'does not rewrite an already-empty list' do
    settings[:unskinnable].clear

    eloot.manage_unskinnable('flush')

    expect(eloot.save_count).to eq(0)
    expect(messages.last[:text]).to include('already empty')
  end

  it 'removes one exact creature case-insensitively and preserves the rest' do
    eloot.manage_unskinnable('remove', 'Massive Troll King')

    expect(settings[:unskinnable]).to eq(['greater earth elemental'])
    expect(eloot.save_count).to eq(1)
    expect(messages.last[:text]).to include('Massive Troll King')
  end

  it 'does not persist when the requested creature is absent' do
    eloot.manage_unskinnable('remove', 'stone giant')

    expect(settings[:unskinnable]).to contain_exactly('massive troll king', 'greater earth elemental')
    expect(eloot.save_count).to eq(0)
    expect(messages.last[:type]).to eq('error')
  end

  it 'reports usage when remove has no creature name' do
    previous_lich_char = $lich_char
    $lich_char = ';'
    script = Struct.new(:name).new('eloot')
    stub_const('Script', Struct.new(:current).new(script))

    eloot.manage_unskinnable('remove')

    expect(eloot.save_count).to eq(0)
    expect(messages.last[:text]).to include(';eloot remove unskinnable <creature name>')
  ensure
    $lich_char = previous_lich_char
  end
end
