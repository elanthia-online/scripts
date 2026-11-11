# frozen_string_literal: true

require_relative '../../spec_helper'

# Lich only updates a container's contents when the game sends a refresh, and none came
# for a skin sack the furrier emptied or for skins dragged out of it, so the cached
# contents kept listing them. Replays a reported log (glands and foreclaws in a grey
# suede satchel):
# - first run: the bulk sell succeeded, then every cached skin was dragged for and sold
#   again ("I could not find what you were referring to.", "What were you referring to?")
# - next run: the satchel was empty ("Realizing it's empty"), but the same skins were
#   chased again, about 5s each
RSpec.describe 'ELoot sell sacks read fresh contents' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(eloot_path) }
  # Region.furrier/gemshop come first in the file; the Sell ones follow selling_type?
  let(:sell_source) { source[source.index('    def self.selling_type?')..] }

  let(:obj) { Struct.new(:id, :name, :noun, :type, :sellable, :contents) }
  let(:gland) { obj.new('981782679', 'mottled kiramon poison gland', 'gland', 'skin', 'furrier') }
  let(:foreclaw) { obj.new('981799128', 'glittering kresh foreclaw', 'foreclaw', 'skin', 'furrier') }
  let(:chitin) { obj.new('981789961', 'some glossy kiramon chitin', 'chitin', 'skin', 'furrier') }
  let(:opal) { obj.new('981800001', 'white opal', 'opal', 'gem', 'gemshop') }
  let(:satchel) { obj.new('981542360', 'plum-corded grey suede satchel', 'satchel', 'container', nil, cached) }

  # what the cache lists, and what the game actually has in the sack
  let(:cached) { [gland, foreclaw] }
  let(:in_sack) { [gland, foreclaw] }
  let(:closed) { false }
  let(:exclude) { /\A\z/ }

  let(:commands) { [] }
  let(:sold) { [] }
  # [commands issued so far, whether the sack still counted as full] at each free_hands
  let(:stows) { [] }

  let(:game) do
    Struct.new(:sack, :in_sack, :closed, :commands, :sold) do
      def look_in
        commands << "look in ##{sack.id}"
        return ['That is closed.'] if closed

        sack.contents = in_sack.dup
        ["In the #{sack.noun}:"]
      end

      # A shop takes what it buys and hands the sack back with no contents refresh
      def bulk_sell(buys)
        commands << "sell ##{sack.id}"
        taken = in_sack.select(&buys)
        self.in_sack -= taken
        taken.empty? ? "Realizing it's empty, he returns it." : 'inspects the contents carefully'
      end

      def drag(item)
        commands << "_drag ##{item.id}"
        in_sack.include?(item)
      end
    end.new(satchel, in_sack.dup, closed, commands, sold)
  end

  let(:data) do
    Struct.new(:settings, :look_regex, :sell_exclude_regex, :alchemy_mode, :silver_breakdown, :disk, :sacks_full)
          .new({ sell_loot_types: %w[skin gem], sell_appraise_types: [] }, /In the/, exclude, false, Hash.new(0), nil,
               { 'last cleared' => [] })
  end

  let(:eloot) do
    game = self.game
    data = self.data
    sacks = [satchel]

    Module.new do
      define_singleton_method(:data) { data }
      define_singleton_method(:msg) { |**| nil }
      define_singleton_method(:go2) { |place| game.commands << "go2 #{place}" }
      define_singleton_method(:silver_check) { 0 }
      define_singleton_method(:read_note) { 0 }
      define_singleton_method(:time_between) { |*| false }
      define_singleton_method(:set_selling_containers) { |**| sacks }
      define_singleton_method(:fwi_return) { nil }
      define_singleton_method(:get_command) do |command, *, **|
        command == "look in ##{game.sack.id}" ? game.look_in : (game.commands << command && [])
      end
    end
  end

  let(:inventory) do
    game = self.game
    data = self.data
    stows = self.stows
    Module.new do
      # free_hands is where a bulk sale's note gets stowed; note whether the sack still counts as full then
      define_singleton_method(:free_hands) { |**| stows << [game.commands.length, data.sacks_full.key?(game.sack.name)] }
      define_singleton_method(:drag) { |item, *| game.drag(item) }
      define_singleton_method(:wear) { |_| nil }
    end
  end

  let(:sell) do
    game = self.game
    Module.new do
      define_singleton_method(:checkleft) { nil }
      define_singleton_method(:checkright) { nil }
      define_singleton_method(:bounty?) { '' }
      define_singleton_method(:sleep) { |*| nil }
      define_singleton_method(:dothistimeout) do |command, *|
        buys = command.include?(game.sack.id) ? ->(i) { i.sellable == 'furrier' || i.sellable == 'gemshop' } : nil
        buys && game.bulk_sell(buys)
      end
      define_singleton_method(:sell_item) { |item, *| game.sold << item.id }
    end
  end

  before do
    $sell_ignore = []
    stub_const('ELoot', eloot)
    stub_const('Inventory', inventory)
    stub_const('Sell', sell)
    eloot.module_eval(extract_lic_method(source, 'fresh_contents', source_path: eloot_path))
    sell.module_eval(%w[selling_type? furrier gemshop].map do |m|
      extract_lic_method(sell_source, m, source_path: eloot_path)
    end.push(*%w[check_bounty_furrier check_bounty_gems].map do |m|
      extract_lic_method(source, m, source_path: eloot_path)
    end).join("\n"))
  end

  after { $sell_ignore = [] }

  def drags = commands.grep(/\A_drag #(?!#{satchel.id})/)

  describe 'Sell.furrier' do
    it 'looks in the sack again after a bulk sell instead of chasing what the furrier took' do
      sell.furrier

      expect(commands).to include("sell ##{satchel.id}")
      expect(commands.rindex("look in ##{satchel.id}")).to be > commands.index("sell ##{satchel.id}")
      expect(drags).to be_empty
      expect(sold).to be_empty
    end

    context 'when the cache is left over from an earlier run and the sack is empty' do
      let(:in_sack) { [] }

      it 'sees the sack is empty and neither sells it nor drags for the cached skins' do
        sell.furrier

        expect(commands.first(2)).to eq(['go2 furrier', "look in ##{satchel.id}"])
        expect(commands).not_to include("sell ##{satchel.id}")
        expect(drags).to be_empty
      end
    end

    context 'when the sack cannot be looked in and a cached skin is gone' do
      let(:closed) { true }
      let(:cached) { [gland, chitin] }
      let(:in_sack) { [chitin] }
      # an excluded skin turns off the bulk sell, so each skin is sold on its own
      let(:exclude) { /kiramon chitin/ }

      it 'does not try to sell a skin it could not pick up' do
        sell.furrier

        expect(drags).to eq(["_drag ##{gland.id}"])
        expect(sold).to be_empty
      end
    end
  end

  describe 'Sell.gemshop' do
    let(:cached) { [opal] }
    let(:in_sack) { [opal] }

    before do
      stub_const('Spell', Class.new)
      data.settings.merge!(sell_gold_rings: false, keep_transmogs: false)
    end

    it 'looks in the sack again after a bulk sell instead of chasing what the gem dealer took' do
      sell.gemshop

      expect(commands.rindex("look in ##{satchel.id}")).to be > commands.index("sell ##{satchel.id}")
      expect(drags).to be_empty
    end
  end

  describe 'Sell.check_bounty_furrier' do
    let(:task) { Struct.new(:skin, :type) { def skin? = true }.new('kiramon poison gland', 'skin') }

    before do
      bounty_task = task
      stub_const('Bounty', Module.new { define_singleton_method(:task) { bounty_task } })
      stub_const('Region', Module.new { define_singleton_method(:furrier) { 9471 } })
    end

    context 'when the cached bounty skins are already gone' do
      let(:in_sack) { [] }

      it 'does not walk to the furrier' do
        sell.check_bounty_furrier

        expect(commands).to eq(["look in ##{satchel.id}"])
      end
    end
  end

  # A sack marked full earlier in the trip (an item that "won't fit") stayed marked after
  # the shop emptied it, so the promissory note it paid with had nowhere to go and eloot
  # paused with "Failed to store the promissory note." Replays a reported log: a feras
  # hammer filled a velveteen longcloak, then the jeweler bought its 21 gems for a note.
  describe 'a sack marked full before the bulk sale' do
    before { data.sacks_full[satchel.name] = ['2026-11-11 09:23:56', 28719, 'feras hammer(167201249)'] }

    def stows_after_sale
      sale = commands.index("sell ##{satchel.id}")
      stows.select { |at, _| at > sale }.map(&:last)
    end

    shared_examples 'counts the sack as having room again' do
      it 'no longer counts the sack as full when stowing what the shop paid with' do
        run_sale

        expect(stows_after_sale).not_to be_empty
        expect(stows_after_sale).to all(be(false))
        expect(data.sacks_full).to include('last cleared')
      end
    end

    describe 'Sell.furrier' do
      def run_sale = sell.furrier

      include_examples 'counts the sack as having room again'
    end

    describe 'Sell.gemshop' do
      let(:cached) { [opal] }
      let(:in_sack) { [opal] }

      before do
        stub_const('Spell', Class.new)
        data.settings.merge!(sell_gold_rings: false, keep_transmogs: false)
      end

      def run_sale = sell.gemshop

      include_examples 'counts the sack as having room again'
    end

    describe 'Sell.check_bounty_furrier' do
      # only the bounty skin, so the sack is sold whole
      let(:cached) { [gland] }
      let(:in_sack) { [gland] }

      before do
        task = Struct.new(:skin, :type) { def skin? = true }.new('kiramon poison gland', 'skin')
        stub_const('Bounty', Module.new { define_singleton_method(:task) { task } })
        stub_const('Region', Module.new { define_singleton_method(:furrier) { 9471 } })
      end

      def run_sale = sell.check_bounty_furrier

      include_examples 'counts the sack as having room again'
    end

    describe 'Sell.check_bounty_gems' do
      let(:cached) { [opal] }
      let(:in_sack) { [opal] }

      before do
        task = Struct.new(:type) { def gem? = true }.new('gem')
        stub_const('Bounty', Module.new do
          define_singleton_method(:task) { task }
          define_singleton_method(:requirements) { { gem: 'white opal' } }
        end)
        stub_const('Region', Module.new { define_singleton_method(:gemshop) { 9472 } })
        sell.define_singleton_method(:checkbounty) { '' }
      end

      def run_sale = sell.check_bounty_gems

      include_examples 'counts the sack as having room again'
    end
  end
end
