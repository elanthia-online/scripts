# frozen_string_literal: true

require_relative '../../spec_helper'

# RSpec for ELoot::Sell.selling_type? -- whether an item's type is one of the user's
# selected sell types. Extracted from eloot.lic the same way as loot_spec.rb; the
# predicate is pure when sell_types is passed explicitly.
RSpec.describe 'ELoot::Sell.selling_type?' do
  let(:mod) do
    path = find_lic_source('eloot.lic', from: File.expand_path('..', __dir__))
    body = extract_lic_method(File.read(path), 'selling_type?', source_path: path)

    Module.new { module_eval(body) }
  end

  let(:item) { Struct.new(:type) }

  def selling?(type, sell_types)
    mod.selling_type?(item.new(type), sell_types)
  end

  it 'skips skins when skin is not selected, even with reagent selected' do
    expect(selling?('skin', %w[reagent gem])).to be false
  end

  it 'matches any of a multi-type item' do
    expect(selling?('reagent,skin', %w[skin])).to be true
  end

  it 'lets "alchemy" cover the alchemy product and equipment types' do
    expect(selling?('alchemy product', %w[alchemy])).to be true
    expect(selling?('alchemy equipment', %w[alchemy])).to be true
  end

  it 'does not match on a partial word' do
    expect(selling?('gemstone', %w[gem])).to be false
  end

  it 'matches nothing when no sell types are selected' do
    expect(selling?('gem', [])).to be false
  end

  it 'handles untyped objects' do
    expect(selling?(nil, %w[skin])).to be false
  end
end
