# frozen_string_literal: true

require_relative '../../spec_helper'

# RSpec for ELoot::Sell.furrier_sellable? -- the filter that keeps the furrier run from
# selling skins (or bulk-selling a whole container) when skin isn't a selling type.
# Extracted from eloot.lic the same way as loot_spec.rb; the predicate is pure.
RSpec.describe 'ELoot::Sell.furrier_sellable?' do
  let(:mod) do
    path = find_lic_source('eloot.lic', from: File.expand_path('..', __dir__))
    body = extract_lic_method(File.read(path), 'furrier_sellable?', source_path: path)

    Module.new { module_eval(body) }
  end

  let(:item) { Struct.new(:type, :sellable) }

  let(:skull)   { item.new('skin', 'furrier') }
  let(:reagent) { item.new('reagent,alchemy', 'furrier,gemshop') }
  let(:gem)     { item.new('gem', 'gemshop') }

  it 'skips skins when skin is not selected, even with reagent selected' do
    expect(mod.furrier_sellable?(skull, %w[reagent gem])).to be false
  end

  it 'sells skins when skin is selected' do
    expect(mod.furrier_sellable?(skull, %w[skin])).to be true
  end

  it 'sells furrier reagents when reagent is selected' do
    expect(mod.furrier_sellable?(reagent, %w[reagent])).to be true
  end

  it 'never sells things the furrier does not buy' do
    expect(mod.furrier_sellable?(gem, %w[gem skin])).to be false
  end

  it 'handles untyped objects' do
    expect(mod.furrier_sellable?(item.new(nil, nil), %w[skin])).to be false
  end
end
