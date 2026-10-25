# frozen_string_literal: true

require_relative '../../spec_helper'

# RSpec for ELoot::Sell.locksmith_pool_count -- pool depth minus boxes ready to return,
# counted from the "ask about list" output alone (a deep list used to push its header
# out of reget and crash on Integer - nil).
RSpec.describe 'ELoot::Sell.locksmith_pool_count' do
  let(:mod) do
    path = find_lic_source('eloot.lic', from: File.expand_path('..', __dir__))
    body = extract_lic_method(File.read(path), 'locksmith_pool_count', source_path: path)

    Module.new { module_eval(body) }
  end

  let(:worker) { Struct.new(:id).new('214732930') }

  def list(*statuses)
    lines = ['The worker says, "Tysong, here\'s the list of boxes we have for you."']
    statuses.each_with_index do |status, i|
      lines << " #{i + 1}.  A simple iron chest a few hours ago for 750 silvers."
      lines << "     It is #{status}."
    end
    lines
  end

  def count(lines)
    stub_const('ELoot', Module.new)
    allow(ELoot).to receive(:get_command).and_return(lines)
    mod.locksmith_pool_count(worker)
  end

  it 'subtracts boxes ready to be returned from the pool depth' do
    expect(count(list('waiting to be worked on', 'ready to be RETURNED', 'waiting to be worked on'))).to eq(2)
  end

  it 'does not depend on reget for a deep pool' do
    statuses = Array.new(100) { |i| i < 10 ? 'ready to be RETURNED' : 'waiting to be worked on' }
    expect(count(list(*statuses))).to eq(90)
  end

  it 'returns 0 for an empty pool' do
    expect(count(['The worker says, "You haven\'t given us any boxes to be worked on."'])).to eq(0)
  end
end
