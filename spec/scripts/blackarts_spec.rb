# Spec for BlackArts.lic's mushroom forage names: the game names several
# mushrooms longer than it accepts in a FORAGE command ("golden hook mushroom"
# is foraged as "golden mushroom"), so fix_name has to shorten the item name
# and normalize_herb has to lengthen the forage name back for room tag lookups.

require_relative '../spec_helper'

module BlackArtsSpec
  SOURCE_PATH = find_lic_source('BlackArts.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")
  METHODS = %w[mushroom_forage_names normalize_herb fix_name].map do |name|
    extract_lic_method(SOURCE, name, source_path: SOURCE_PATH)
  end

  # Nested under the spec module so the real BlackArts namespace is never touched.
  module Util
    BlackArtsSpec::METHODS.each { |src| module_eval(src) }
  end
end

RSpec.describe 'BlackArts mushroom forage names' do
  util = BlackArtsSpec::Util

  mappings = {
    'black hook mushroom'     => 'black mushroom',
    'black trafel mushroom'   => 'trafel mushroom',
    'golden hook mushroom'    => 'golden mushroom',
    'red trafel mushroom'     => 'red mushroom',
    'soft white mushroom'     => 'soft mushroom',
    'white hook mushroom'     => 'white mushroom',
    'withered black mushroom' => 'withered mushroom',
  }

  it 'maps every mushroom the game names longer than FORAGE accepts' do
    expect(util.mushroom_forage_names).to eq(mappings)
  end

  mappings.each do |full, short|
    it "forages for #{full} as #{short}" do
      expect(util.fix_name(full)).to eq(short)
    end

    it "looks up #{short} by its full name #{full}" do
      expect(util.normalize_herb(short)).to eq(full)
    end

    it "leaves the full name #{full} alone when normalizing" do
      expect(util.normalize_herb(full)).to eq(full)
    end
  end

  it 'does not shorten a mushroom the game already accepts by its full name' do
    expect(util.fix_name('trollear mushroom')).to eq('trollear mushroom')
  end
end
