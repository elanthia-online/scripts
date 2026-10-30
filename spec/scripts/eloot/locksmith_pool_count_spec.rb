# frozen_string_literal: true

require_relative '../../spec_helper'

# RSpec for ELoot::Sell.locksmith_pool_count -- pool depth minus boxes ready to return.
# Counts from the "ask about list" output; when issue_command times out and hands back
# a partial list, falls back to the whole server buffer (reget), but only if this
# list's header was seen. The old code found the header in reget(300) alone and died
# on Integer - nil when it was missing.
RSpec.describe 'ELoot::Sell.locksmith_pool_count' do
  let(:sell) do
    path = find_lic_source('eloot.lic', from: File.expand_path('..', __dir__))
    source = File.read(path)
    header = source[/^    POOL_LIST_HEADER = .*$/]
    body = %w[locksmith_pool_count pool_list_counts].map { |m| extract_lic_method(source, m, source_path: path) }.join("\n")

    Module.new { module_eval("#{header}\n#{body}") }
  end

  let(:worker) { Struct.new(:id).new('214732930') }
  let(:prompt) { '<prompt time="1790919494">&gt;</prompt>' }
  let(:buffer) { nil }

  before do
    stub_const('Sell', sell)
    stub_const('ELoot', Module.new)
    allow(ELoot).to receive(:msg)
    buffered = buffer
    sell.define_singleton_method(:reget) { |*| buffered }
  end

  def list(*statuses)
    lines = ['The worker says, "Tysong, here\'s the list of boxes we have for you."']
    statuses.each_with_index do |status, i|
      lines << format('%2d.  A simple iron chest a few hours ago for 750 silvers.', i + 1)
      lines << "     It is #{status}."
    end
    lines
  end

  def deep_pool
    list(*Array.new(100) { |i| i < 90 ? 'waiting to be worked on' : 'ready to be RETURNED' })
  end

  def count(results)
    allow(ELoot).to receive(:get_command).and_return(results)
    sell.locksmith_pool_count(worker)
  end

  it 'subtracts boxes ready to be returned from the pool depth' do
    expect(count(list('waiting to be worked on', 'ready to be RETURNED', 'waiting to be worked on') + [prompt])).to eq(2)
  end

  it 'gives the list command longer than the default timeout' do
    count(list('waiting to be worked on') + [prompt])
    expect(ELoot).to have_received(:get_command).with(/about list/, anything, hash_including(timeout: 15))
  end

  it 'counts a full 100-box pool from the results alone' do
    expect(count(deep_pool + [prompt])).to eq(90)
    expect(ELoot).not_to have_received(:msg)
  end

  it 'returns 0 for an empty pool' do
    expect(count(['The worker says, "You haven\'t given us any boxes to be worked on."', prompt])).to eq(0)
  end

  context 'when the results were cut off by the timeout' do
    let(:buffer) { ['some earlier line'] + deep_pool }

    it 'uses the fuller list in the server buffer and warns' do
      expect(count(deep_pool.first(121))).to eq(90)
      expect(ELoot).to have_received(:msg).with(hash_including(text: /incomplete/))
    end
  end

  context 'when the results were cut between a box and its status line' do
    let(:buffer) { list('waiting to be worked on', 'ready to be RETURNED') }

    it 'takes the status from the buffer instead of counting the box as waiting' do
      expect(count(list('waiting to be worked on', 'ready to be RETURNED').first(4))).to eq(1)
    end
  end

  context 'when the results never saw the header' do
    let(:buffer) { list('waiting to be worked on', 'ready to be RETURNED') }

    it 'does not trust an older list in the buffer, and does not crash' do
      expect(count([])).to eq(0)
      expect(ELoot).to have_received(:msg).with(hash_including(text: /incomplete/))
    end
  end

  context 'when the buffer has no list at all (reget returns nil)' do
    it 'falls back to the partial results instead of crashing' do
      expect(count(deep_pool.first(41))).to eq(20)
    end
  end
end
