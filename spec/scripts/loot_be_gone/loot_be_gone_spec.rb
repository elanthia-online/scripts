# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'open3'
require 'tempfile'

# Gem stockpile bookkeeping (CharSettings[:jars]) in loot-be-gone.lic.
#
# The stockpile examples run loot-be-gone's real stockpile and raid_stockpile
# procs against lich-5's real Settings/CharSettings and a temporary lich.db3,
# in a child process (see jar_driver.rb for why). Each example checks the
# :jars row read back from the database against the gems actually left in
# the simulated jars, and against fixed expected values. They need a lich-5
# checkout with the SQLite-backed Settings (5.12 or newer) and skip without
# one, like the other lich-5-backed specs.
module LootBeGoneSpec
  LIC_PATH = find_lic_source('loot-be-gone.lic', from: File.expand_path('..', __dir__))
  DRIVER = File.join(__dir__, 'jar_driver.rb')
  LICH5 = lich5_path
  SETTINGS_AVAILABLE = !LICH5.nil? && File.exist?(File.join(LICH5, 'lib/common/settings/settings_proxy.rb'))

  def self.run(scenario)
    Tempfile.create(['loot-be-gone-scenario', '.json']) do |file|
      file.write(JSON.generate(scenario))
      file.flush
      out, err, status = Open3.capture3(RbConfig.ruby, DRIVER, LICH5, LIC_PATH, file.path)
      raise "jar_driver failed (#{status.exitstatus}):\n#{err}#{out}" unless status.success?

      JSON.parse(out.lines.last)
    end
  end

  def self.gems(*names)
    names.each_with_index.map { |name, i| { 'id' => (310 + i).to_s, 'name' => name } }
  end
end

RSpec.describe 'loot-be-gone.lic gem stockpile bookkeeping' do
  before { skip 'no lich-5 checkout with SQLite Settings (set LICH5_PATH)' unless LootBeGoneSpec::SETTINGS_AVAILABLE }

  def jars(list)
    list.map { |j| j.transform_keys(&:to_s) }.sort_by { |j| j['gem'] }
  end

  # What is really in the jars, in the shape stockpile records it.
  def truth(result)
    jars(result['locker'].select { |j| j['count'].positive? }.map { |j| j.slice('gem', 'count', 'full') })
  end

  def stored(result)
    expect(result['stored_jars']).to be_a(Array), "stored :jars is not an Array: #{result['stored_jars']}"
    expect(result['log']).to eq([])
    jars(result['stored_jars'])
  end

  describe 'stockpile' do
    it 'saves every gem added to a jar started this run' do
      result = LootBeGoneSpec.run(
        'saved'    => { 'jars' => [], 'empty_jar_count' => 1 },
        'locker'   => [{ 'id' => '202', 'capacity' => 10 }],
        'lootsack' => LootBeGoneSpec.gems('ruby', 'ruby', 'ruby', 'ruby'),
        'steps'    => [{ 'run' => 'stockpile' }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'rubies', count: 4, full: false }]))
      expect(stored(result)).to eq(truth(result))
    end

    it 'saves the count and the full flag of a jar started and filled this run, leaving the rest in the sack' do
      result = LootBeGoneSpec.run(
        'saved'    => { 'jars' => [], 'empty_jar_count' => 1 },
        'locker'   => [{ 'id' => '202', 'capacity' => 3 }],
        'lootsack' => LootBeGoneSpec.gems('ruby', 'ruby', 'ruby', 'ruby', 'ruby'),
        'steps'    => [{ 'run' => 'stockpile' }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'rubies', count: 3, full: true }]))
      expect(stored(result)).to eq(truth(result))
    end

    it 'saves a single-gem new jar (count 1 is what was pushed, so it is right before and after)' do
      result = LootBeGoneSpec.run(
        'saved'    => { 'jars' => [], 'empty_jar_count' => 1 },
        'locker'   => [{ 'id' => '202', 'capacity' => 10 }],
        'lootsack' => LootBeGoneSpec.gems('ruby'),
        'steps'    => [{ 'run' => 'stockpile' }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'rubies', count: 1, full: false }]))
    end

    it 'records the locker on a first run and saves both the existing jar and one started in the same run' do
      result = LootBeGoneSpec.run(
        'saved'    => nil,
        'locker'   => [{ 'id' => '201', 'gem' => 'opal', 'count' => 5, 'capacity' => 10 }, { 'id' => '202', 'capacity' => 10 }],
        'lootsack' => LootBeGoneSpec.gems('opal', 'ruby', 'opal', 'ruby', 'ruby'),
        'steps'    => [{ 'run' => 'stockpile' }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'opals', count: 7, full: false }, { gem: 'rubies', count: 3, full: false }]))
      expect(stored(result)).to eq(truth(result))
    end

    it 'saves two jars started in the same run (the last one is not left behind)' do
      result = LootBeGoneSpec.run(
        'saved'    => { 'jars' => [], 'empty_jar_count' => 2 },
        'locker'   => [{ 'id' => '202', 'capacity' => 10 }, { 'id' => '203', 'capacity' => 10 }],
        'lootsack' => LootBeGoneSpec.gems('ruby', 'ruby', 'ruby', 'opal', 'opal'),
        'steps'    => [{ 'run' => 'stockpile' }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'rubies', count: 3, full: false }, { gem: 'opals', count: 2, full: false }]))
      expect(stored(result)).to eq(truth(result))
    end

    it 'adds to a jar from an earlier run and marks it full when it fills' do
      result = LootBeGoneSpec.run(
        'saved'    => { 'jars' => [{ 'gem' => 'opals', 'count' => 5, 'full' => false }], 'empty_jar_count' => 0 },
        'locker'   => [{ 'id' => '201', 'gem' => 'opal', 'count' => 5, 'capacity' => 6 }],
        'lootsack' => LootBeGoneSpec.gems('opal', 'opal', 'opal'),
        'steps'    => [{ 'run' => 'stockpile' }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'opals', count: 6, full: true }]))
      expect(stored(result)).to eq(truth(result))
    end

    it 'leaves the other saved jars alone when it updates one' do
      result = LootBeGoneSpec.run(
        'saved'    => { 'jars' => [{ 'gem' => 'rubies', 'count' => 9, 'full' => true }, { 'gem' => 'opals', 'count' => 5, 'full' => false }], 'empty_jar_count' => 0 },
        'locker'   => [{ 'id' => '200', 'gem' => 'ruby', 'count' => 9, 'capacity' => 9 }, { 'id' => '201', 'gem' => 'opal', 'count' => 5, 'capacity' => 10 }],
        'lootsack' => LootBeGoneSpec.gems('opal', 'opal'),
        'steps'    => [{ 'run' => 'stockpile' }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'rubies', count: 9, full: true }, { gem: 'opals', count: 7, full: false }]))
    end
  end

  describe 'raid_stockpile' do
    it 'saves the lower count and clears the full flag' do
      result = LootBeGoneSpec.run(
        'saved'  => { 'jars' => [{ 'gem' => 'rubies', 'count' => 4, 'full' => false }, { 'gem' => 'opals', 'count' => 5, 'full' => true }], 'empty_jar_count' => 0 },
        'locker' => [{ 'id' => '200', 'gem' => 'ruby', 'count' => 4, 'capacity' => 10 }, { 'id' => '201', 'gem' => 'opal', 'count' => 5, 'capacity' => 5 }],
        'steps'  => [{ 'run' => 'raid', 'gem' => 'opal', 'count' => 2 }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'rubies', count: 4, full: false }, { gem: 'opals', count: 3, full: false }]))
      expect(stored(result)).to eq(truth(result))
    end

    it 'drops the entry of a jar it empties and keeps the others' do
      result = LootBeGoneSpec.run(
        'saved'  => { 'jars' => [{ 'gem' => 'opals', 'count' => 2, 'full' => false }, { 'gem' => 'rubies', 'count' => 4, 'full' => false }], 'empty_jar_count' => 0 },
        'locker' => [{ 'id' => '201', 'gem' => 'opal', 'count' => 2, 'capacity' => 10 }, { 'id' => '200', 'gem' => 'ruby', 'count' => 4, 'capacity' => 10 }],
        'steps'  => [{ 'run' => 'raid', 'gem' => 'opal', 'count' => 2 }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'rubies', count: 4, full: false }]))
      expect(stored(result)).to eq(truth(result))
    end

    it 'saves gems stockpiled into a new jar and then raided in the same run' do
      result = LootBeGoneSpec.run(
        'saved'    => { 'jars' => [], 'empty_jar_count' => 1 },
        'locker'   => [{ 'id' => '202', 'capacity' => 10 }],
        'lootsack' => LootBeGoneSpec.gems('ruby', 'ruby', 'ruby', 'ruby', 'ruby'),
        'steps'    => [{ 'run' => 'stockpile' }, { 'run' => 'raid', 'gem' => 'ruby', 'count' => 2 }]
      )
      expect(stored(result)).to eq(jars([{ gem: 'rubies', count: 3, full: false }]))
      expect(stored(result)).to eq(truth(result))
    end
  end
end

# The herb-drop-room lookup in the herb bundling step, extracted from the
# script and run against stand-in CharSettings/Vars hashes.
RSpec.describe 'loot-be-gone.lic herb-drop-room setting' do
  source = File.read(LootBeGoneSpec::LIC_PATH)
  chain = extract_from_source(source, /^    if CharSettings\['herb drop room'\]\.nil\?\n.*?^    end\n/m,
                              label: 'herb drop room lookup', source_path: LootBeGoneSpec::LIC_PATH)

  def lookup(chain, setting, vars)
    mod = Module.new
    mod.const_set(:CharSettings, { 'herb drop room' => setting })
    mod.const_set(:Vars, vars)
    mod.instance_variable_set(:@echoes, [])
    mod.module_eval(<<~RUBY, LootBeGoneSpec::LIC_PATH)
      def self.echoes = @echoes
      def self.echo(msg) = @echoes << msg
      def self.run
        herb_drop_room = :unset
        #{chain}
        herb_drop_room
      end
    RUBY
    [mod.run, mod.echoes]
  end

  it 'reads a room number stored in the named variable' do
    expect(lookup(chain, 'herbroom', { 'herbroom' => '1234' })).to eq([1234, []])
  end

  it 'reads an Integer stored in the named variable' do
    expect(lookup(chain, 'herbroom', { 'herbroom' => 4321 })).to eq([4321, []])
  end

  it 'warns and uses no room when the named variable holds no room number' do
    expect(lookup(chain, 'herbroom', { 'herbroom' => 'the herbalist' })).to eq([nil, ['warning: bad herb-drop-room setting']])
  end

  it 'still takes a room number given directly, and nil for no setting' do
    expect(lookup(chain, '228', {})).to eq([228, []])
    expect(lookup(chain, nil, {})).to eq([nil, []])
  end
end
