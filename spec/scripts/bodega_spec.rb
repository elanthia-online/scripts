# frozen_string_literal: true

# Spec for bodega.lic's shop parser: town list and town-name fallback, the
# shop directory, SHOP BROWSE parsing (rooms, signs, prices, quantities),
# item inspection, and the smart-scan branches (unchanged, partial, server
# reboot, owner change, new shop) with their summary stats.
#
# This file is kept identical in elanthia-online/scripts
# (spec/scripts/bodega_spec.rb) and elanthia-online/bodega
# (spec/bodega_spec.rb); it finds bodega.lic in either layout.
#
# The game text below is real output captured by the bodega pipeline
# (scrape-logs artifacts), with player names swapped for placeholders.
#
# Only the script's `module Bodega` blocks are evaluated, inside a private
# Sandbox module, so nothing leaks into other specs. The script's top-level
# String/MatchData polyfills are applied as refinements, active only in the
# evaluated Bodega code, and the CLI and Assets blocks are left out (see
# BLOCKS).

require 'rspec'
require 'json'
require 'ostruct'

module BodegaSpec
  SOURCE_PATH = [
    File.expand_path('../../scripts/bodega.lic', __dir__), # elanthia-online/scripts
    File.expand_path('../automation/lich/scripts/bodega.lic', __dir__) # elanthia-online/bodega
  ].find { |path| File.exist?(path) } or raise 'bodega.lic not found'

  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")
  # Skipped: CLI runs the script, and Assets creates directories (and sets
  # $lich_dir) at load time. The parser only reaches Assets through
  # load_and_validate_town_json, which the smart-scan examples stub.
  BLOCKS = SOURCE.scan(/^module Bodega\n.*?^end\n/m).reject { |block| block.match?(/^  module (CLI|Assets)$/) }
  raise "could not extract the Bodega modules from #{SOURCE_PATH}" if BLOCKS.size < 5

  # The script's own ::String / ::MatchData polyfills, as refinements.
  module Polyfills
    %w[String MatchData].each do |klass|
      body = SOURCE[/^class ::#{klass}\n(.*?)^end\n/m, 1] or raise "could not extract the #{klass} polyfill"
      module_eval("refine #{klass} do\n#{body}end\n", SOURCE_PATH)
    end
  end

  # Replays canned game output: each command queues its response lines, and
  # get? hands them back one at a time (nil once drained, like a quiet game).
  class FakeGame
    attr_reader :sent

    def initialize(responses)
      @responses = responses
      @sent = []
      @queue = []
    end

    def send_command(command)
      @sent << command
      @queue.concat(@responses.fetch(command, []))
      command
    end

    def next_line
      @queue.shift
    end

    def dothistimeout(command, _seconds, pattern)
      send_command(command)
      line = @queue.find { |l| l.match?(pattern) }
      @queue.clear
      line
    end
  end

  class << self
    attr_accessor :game
  end

  module Sandbox
    module Script
      def self.current
        @current ||= OpenStruct.new(name: 'bodega', vars: ['bodega'])
      end
    end

    BodegaSpec::BLOCKS.each do |block|
      line = BodegaSpec::SOURCE[0, BodegaSpec::SOURCE.index(block)].count("\n") + 1
      module_eval("using BodegaSpec::Polyfills; #{block}", BodegaSpec::SOURCE_PATH, line)
    end

    Bodega::Collector.class_eval do
      private

      def fput(command) = BodegaSpec.game.send_command(command)
      def get? = BodegaSpec.game.next_line
    end

    Bodega::Parser.define_singleton_method(:dothistimeout) do |command, seconds, pattern|
      BodegaSpec.game.dothistimeout(command, seconds, pattern)
    end
  end

  TOWNS_LINE = "Unknown town specified.  Valid options include: Wehnimer's Landing, Teras Isle, Solhaven, " \
               "River's Rest, Icemule Trace, Zul Logoth, Ta'Illistim, Ta'Vaalor, Mist Harbor, Cysaegir, and Kraken's Fall."
  TOWNS = ["Wehnimer's Landing", 'Teras Isle', 'Solhaven', "River's Rest", 'Icemule Trace', 'Zul Logoth',
           "Ta'Illistim", "Ta'Vaalor", 'Mist Harbor', 'Cysaegir', "Kraken's Fall"].freeze

  KRAKEN_DIRECTORY = [
    "   ~*~ Kraken's Fall Shops ~*~",
    "    1) Shop of the Lost Things, Otter       2) Ownera's Outfitting                  3) Ownerb's General Store           ",
    "    4) Ownerc's Weaponry                    5) Ownerd's Magic Shoppe                6) The Refuse Repository            ",
    "You can use the SHOP BROWSE KRAKEN'S FALL {SHOP#} command to browse the inventory of a particular shop."
  ].freeze

  # Lines from other scripts arrive before the preamble; the Collector skips them.
  BROWSE = [
    '[infomon_reset1]>society',
    'Current society status:',
    "Ownera's Shop is located in [East Row, Ebonwood Way] (731001) at a large brick-faced store with a sturdy " \
    'cross-gabled roof, and is currently open for business.',
    " Ownera's Armory (entry)",
    '  In a gold-leafed mistwood cabinet:',
    '      102953) a soft deep red spidersilk cloak edged with grey silk trim        for    6,000,000 silver',
    '      102952) a mixed scale and steel-riveted ivory leather coat-of-plates      for    3,500,000 silver',
    '  Written on an engraved ironwood sign:',
    '    Enhancives - North Room',
    '    Armor in front room is Tier 1 Voln armor',
    " Ownera's Magic Shoppe (north)",
    '  In an engraved copper bin:',
    '      102979) some embossed imflass leg greaves                                 for    1,600,000 silver',
    '      102978) a brilliant white sunstone circlet                                for      100,000 silver',
    " Ownera's Outfitting (east)",
    '  On a plain wooden table:',
    '      101976) a spear-tipped ghostwood nib                                      for       50,000 silver (30 available)',
    '      101972) a spirit change note                                              for    3,000,000 silver (3 available)',
    'You can use the SHOP INSPECT {STOCK#} command to get details about a particular shop item.',
    'You may also click the stock numbers above to SHOP INSPECT that particular item.'
  ].freeze

  BROWSE_ROOMS = { 'entry' => %w[102953 102952], 'north' => %w[102979 102978], 'east' => %w[101976 101972] }.freeze
  BROWSE_IDS = BROWSE_ROOMS.values.flatten.freeze

  INSPECT = [
    'You request a thorough inspection of an opalescent glass jar containing uncut emeralds from Ownerb\'s General Store.',
    'You see nothing unusual.',
    'The jar can not be worn.',
    'It looks like this item has been mainly crafted out of glass, an extremely common material.',
    'It can hold a maximum of 20 items.  PUT items in to store them.  SHAKE the jar to get them back out.',
    'The glass jar will cost 189,999 coins.',
    'You can use SHOP PURCHASE 19134278 to purchase the jar.'
  ].freeze
end

RSpec.describe 'bodega.lic' do
  let(:bodega) { BodegaSpec::Sandbox::Bodega }
  let(:parser) { bodega::Parser }
  let(:opts) { OpenStruct.new }
  let(:game) { BodegaSpec::FakeGame.new(responses) }
  let(:responses) { {} }
  let(:logged) { [] }

  before do
    BodegaSpec.game = game
    allow(bodega::Opts).to receive(:parse).and_return(opts)
    allow(bodega::Log).to receive(:out) { |msg, **| logged << msg.to_s }
    parser.instance_variable_set(:@towns, nil)
    parser.instance_variable_set(:@smart_stats, nil)
    parser.clear_last_smart_stats
  end

  describe 'town list' do
    let(:responses) { { 'shop direc' => [BodegaSpec::TOWNS_LINE] } }

    it 'parses the Oxford-comma list without a stray "and" or trailing comma' do
      expect(parser.towns).to eq(BodegaSpec::TOWNS)
    end

    it 'falls back to the leading token only when no other town shares it' do
      variants = BodegaSpec::TOWNS.to_h { |town| [town, parser.shop_direc_variants(town, BodegaSpec::TOWNS)] }

      expect(variants["Kraken's Fall"]).to eq(["Kraken's Fall", 'Kraken'])
      expect(variants["Wehnimer's Landing"]).to eq(["Wehnimer's Landing", 'Wehnimer'])
      expect(variants['Icemule Trace']).to eq(['Icemule Trace', 'Icemule'])
      expect(variants["Ta'Vaalor"]).to eq(["Ta'Vaalor"])
      expect(variants["Ta'Illistim"]).to eq(["Ta'Illistim"])
      expect(variants['Solhaven']).to eq(['Solhaven'])
    end

    it 'uses the advertised town list by default' do
      expect(parser.shop_direc_variants("Ta'Vaalor")).to eq(["Ta'Vaalor"])
      expect(game.sent).to eq(['shop direc'])
    end
  end

  describe 'shop directory' do
    let(:responses) do
      {
        'shop direc'               => [BodegaSpec::TOWNS_LINE],
        "shop direc Kraken's Fall" => [BodegaSpec::TOWNS_LINE, 'Use SHOP DIRECTORY {town} to list open shops in a specified town.'],
        'shop direc Kraken'        => BodegaSpec::KRAKEN_DIRECTORY,
        "shop direc Ta'Vaalor"     => BodegaSpec::KRAKEN_DIRECTORY.map { |l| l.sub("Kraken's Fall", "Ta'Vaalor").sub("KRAKEN'S FALL", "TA'VAALOR") }
      }
    end

    before { allow(parser).to receive(:scan_shops) { |*args| args } }

    it 'falls back to "Kraken" when the game rejects the full name, and browses with it' do
      town, shops, command = parser.shops("Kraken's Fall")

      expect(town).to eq("Kraken's Fall")
      expect(command).to eq('SHOP BROWSE KRAKEN {SHOP#}')
      expect(shops).to eq(
        '1' => 'Shop of the Lost Things, Otter', '2' => "Ownera's Outfitting", '3' => "Ownerb's General Store",
        '4' => "Ownerc's Weaponry", '5' => "Ownerd's Magic Shoppe", '6' => 'The Refuse Repository'
      )
      expect(game.sent).to eq(['shop direc', "shop direc Kraken's Fall", 'shop direc Kraken'])
    end

    it 'keeps the full name and advertised browse command for a town with no fallback' do
      _town, shops, command = parser.shops("Ta'Vaalor")

      expect(command).to eq("SHOP BROWSE TA'VAALOR {SHOP#}")
      expect(shops.size).to eq(6)
      expect(game.sent).to eq(['shop direc', "shop direc Ta'Vaalor"])
    end
  end

  describe 'SHOP BROWSE parsing' do
    let(:responses) { { 'SHOP BROWSE LANDING 1' => BodegaSpec::BROWSE } }
    let(:inv) { BodegaSpec::BROWSE.drop(3).map(&:strip) }

    before { allow(parser).to receive(:scan_item) { |id, price, quantity| { id: id, cost: price, quantity: quantity }.compact } }

    it 'reads the shop owner, location and every room with its items in order' do
      shop = parser.scan_inv("Wehnimer's Landing", '1', "Ownera's Armory", 'SHOP BROWSE LANDING 1')

      expect(shop).to include(id: '1', shop_owner: 'Ownera', room_name: 'East Row, Ebonwood Way', room_number: '731001',
                              exterior: 'large brick-faced store with a sturdy cross-gabled roof')
      expect(shop[:inv].map { |room| [room[:branch], room[:items].map { |i| i[:id] }] }.to_h).to eq(BodegaSpec::BROWSE_ROOMS)
      expect(shop[:inv].first).to include(room_title: "Ownera's Armory",
                                          sign: ['Written on an engraved ironwood sign:', 'Enhancives - North Room',
                                                 'Armor in front room is Tier 1 Voln armor'])
      expect(shop[:inv].last[:items].first).to eq(id: '101976', cost: 50_000, quantity: 30)
    end

    it 'reads ids, prices and quantities without inspecting anything' do
      ids = parser.get_browse_ids(inv)

      expect(ids.keys).to eq(BodegaSpec::BROWSE_IDS)
      expect(ids['102953']).to eq(price: 6_000_000)
      expect(ids['101972']).to eq(price: 3_000_000, quantity: 3)
      expect(parser).not_to have_received(:scan_item)
    end

    it 'leaves out an item whose inspect fails instead of dropping the shop' do
      allow(parser).to receive(:scan_item).with('102979', anything, anything).and_raise(StandardError, 'no reply')

      rooms = parser.parse_inv(inv)

      expect(rooms.map { |room| room[:items].map { |i| i[:id] } }).to eq([%w[102953 102952], %w[102978], %w[101976 101972]])
      expect(logged).to include('Failed to inspect item 102979: no reply')
    end
  end

  describe 'item inspection' do
    let(:responses) { { 'shop inspect 19134278' => BodegaSpec::INSPECT } }

    it 'names the item and takes the cost from the browse price' do
      item = parser.scan_item('19134278', 189_999, 2)

      expect(item).to include(id: '19134278', name: 'an opalescent glass jar containing uncut emeralds', quantity: 2)
      expect(item[:details]).to include(cost: 189_999)
    end

    it 'keeps the raw inspect lines in raw mode' do
      item = parser.scan_item_raw('19134278', 189_999)

      expect(item).to include(name: 'an opalescent glass jar containing uncut emeralds', browse_price: 189_999)
      expect(item[:raw_inspect]).to eq(BodegaSpec::INSPECT[1..-2])
    end

    it 'gives up after the retries when the game never answers' do
      collector = bodega::Collector.new(start: 'You request', close: 'You can use SHOP PURCHASE', command: 'shop inspect 1')

      expect { collector.run(0.01) }.to raise_error(StandardError, /failed to complete/)
      expect(game.sent).to eq(['shop inspect 1'] * (bodega::Collector::MAX_TRIES + 1))
    end
  end

  describe 'smart scan' do
    let(:responses) { { 'SHOP BROWSE LANDING 1' => BodegaSpec::BROWSE } }
    let(:cached_owner) { 'Ownera' }
    let(:cached_ids) { BodegaSpec::BROWSE_IDS }
    let(:town_data) do
      { 'shops' => [{ 'id' => '1', 'shop_owner' => cached_owner,
                      'inv' => [{ 'room_title' => "Ownera's Armory", 'branch' => 'entry',
                                  'items' => cached_ids.map { |id| { 'id' => id, 'quantity' => 99 } } }] }] }
    end

    before do
      allow(parser).to receive(:load_and_validate_town_json) { town_data && JSON.parse(JSON.generate(town_data)) }
      allow(parser).to receive(:scan_item) { |id, *| { id: id } }
    end

    def scan
      parser.smart_scan_inv("Wehnimer's Landing", '1', "Ownera's Armory", 'SHOP BROWSE LANDING 1')
    end

    def stats
      parser.instance_variable_get(:@smart_stats)
    end

    def room_ids(shop)
      shop[:inv].map { |room| (room[:items] || room['items']).map { |i| (i[:id] || i['id']).to_s } }
    end

    it 'inspects nothing when every item is already cached, and refreshes quantities' do
      shop = scan

      expect(parser).not_to have_received(:scan_item)
      expect(stats).to include(new_items: 0, removed_items: 0, unchanged_items: 6, shops_scanned: 1)
      items = shop[:inv].first['items'].to_h { |i| [i['id'], i['quantity']] }
      expect(items).to include('101976' => 30, '101972' => 3)
      expect(shop[:inv].first['items'].find { |i| i['id'] == '102953' }).not_to have_key('quantity')
    end

    context 'when a few items changed' do
      let(:cached_ids) { BodegaSpec::BROWSE_IDS - ['102978'] + ['100001'] }

      it 'inspects only the new item and drops the sold one' do
        shop = scan

        expect(parser).to have_received(:scan_item).once.with('102978', 100_000, nil)
        expect(room_ids(shop).flatten).to match_array(BodegaSpec::BROWSE_IDS)
        expect(stats).to include(new_items: 1, removed_items: 1, unchanged_items: 5)
      end
    end

    context 'when a server reboot renumbered the stock of the same owner' do
      let(:cached_ids) { %w[90001 90002 90003 90004] }

      it 'parses the browse output in full so items keep their rooms, and counts the removed items' do
        shop = scan

        expect(room_ids(shop)).to eq(BodegaSpec::BROWSE_ROOMS.values)
        expect(stats).to include(new_items: 6, removed_items: 4, unchanged_items: 0)
        expect(game.sent).to eq(['SHOP BROWSE LANDING 1'])
      end
    end

    context 'when the shop number now belongs to another owner' do
      let(:cached_owner) { 'Ownerz' }

      it 'rescans the shop in full under the current owner' do
        shop = scan

        expect(shop[:shop_owner]).to eq('Ownera')
        expect(room_ids(shop)).to eq(BodegaSpec::BROWSE_ROOMS.values)
        expect(stats).to include(new_items: 6, unchanged_items: 0)
      end
    end

    context 'when the shop is not cached' do
      let(:town_data) { nil }

      it 'scans the shop in full' do
        shop = scan

        expect(room_ids(shop)).to eq(BodegaSpec::BROWSE_ROOMS.values)
        expect(stats).to include(new_items: 6, unchanged_items: 0)
      end
    end

    it 'keeps the summary stats for headless.lic and resets them for the next run' do
      scan
      parser.display_smart_summary

      expect(parser.last_smart_stats).to include(new_items: 0, unchanged_items: 6, shops_scanned: 1)
      expect(stats).to be_nil
      expect(logged).to include('*** NO CHANGES DETECTED - All items matched cache ***')

      parser.clear_last_smart_stats
      expect(parser.last_smart_stats).to be_nil
    end
  end
end
