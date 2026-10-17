# frozen_string_literal: true

require_relative '../spec_helper'
require 'sequel'
require 'tmpdir'

# Spec for catalog.lic. The whole CatalogDB module is extracted and
# module_eval'd into a Harness namespace (catalog.lic runs its CLI on load and
# needs a live game). Store and Query run against an in-memory SQLite
# database; Scan is not covered, it only sends game commands.
module CatalogSpec
  SOURCE_PATH = find_lic_source('catalog.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH)

  # GEM LIST ALL, from the game
  GEM_LIST = [
    '',
    "Gemstone 1: <d cmd='gem unequip 1'>an asymmetrical cerulean jewel</d><pushBold/> (equipped)<popBold/> (greater binding)",
    "    * <d cmd='gem info flareres'>Flare Resonance</d> (Rank 5 of 5)",
    '    * Lost Arcanum',
    '    * Charged Presence',
    '',
    'Gemstone 2: a knapped pale blue jewel (equipped) (greater binding)',
    '    * Stamina Prism (Rank 4 of 5)',
    '    * Blood Boil',
    '',
    'Gemstone 3: a glossy sea blue jewel (equipped) (lesser binding)',
    '    * Twist the Knife (Rank 1 of 5)',
    '    * Infusion of Acid',
    '',
    'Gemstone 4: a triangular mahogany jewel (equipped) (greater binding)',
    '    * Hinterwilds: Warden of the Damned (Rank 1 of 5)',
    "    * Ephemera's Extension (Rank 2 of 5)",
    '',
    'Gemstone 5: a faceted amaranth jewel (equipped) (lesser binding)',
    '    * Binding Shot',
    '    * Ether Flux',
    '',
    'Gemstone 6: a polished indigo jewel (lesser binding)',
    "    * Geomancer's Spite",
    '',
    'Gemstone 7: a glossy snow white jewel (lesser binding)',
    "    * Journey's Beginning"
  ].freeze

  FakeItem = Struct.new(:id, :noun, :name, :long, :flags, :children, :parent_item) do
    def contents = children
  end

  module Harness
    DATA_DIR = Dir.tmpdir
    LICH_DIR = Dir.tmpdir
    Settings = {}

    # Types the specs need, by noun.
    class GameObj
      TYPES = { 'jar' => 'jar', 'compendium' => 'uncommon', 'orb' => 'magic,uncommon', 'diamond' => 'gem', 'sapphire' => 'gem', 'broadsword' => 'weapon', 'pouch' => 'container' }.freeze

      def initialize(_id, noun, _name)
        @noun = noun
      end

      def type
        TYPES[@noun]
      end
    end

    module_eval(extract_from_source(SOURCE, /^module CatalogDB\n.*?^end\n/m, label: 'CatalogDB', source_path: SOURCE_PATH), SOURCE_PATH)
  end
end

# Lich adds this to Numeric; Output uses it for amounts.
unless 1.respond_to?(:with_commas)
  class Integer
    def with_commas = to_s.reverse.scan(/\d{1,3}/).join(',').reverse
  end
end

RSpec.describe 'catalog' do
  let(:catalog) { CatalogSpec::Harness::CatalogDB }
  let(:parse) { catalog::Parse }

  it 'lists every constant it defines for removal on rerun' do
    listed = CatalogSpec::SOURCE.scan(/%i\[([^\]]*)\]\.each \{ \|name\| remove_const/).flatten.flat_map(&:split)
    assigned = CatalogSpec::SOURCE.scan(/^ +([A-Z][A-Za-z_]*) = /).flatten
    expect(assigned - listed).to be_empty
  end

  describe 'Parse' do
    it 'reads TICKET BALANCE' do
      lines = [
        "You take a moment to recall the alternative currencies you've collected...",
        '',
        '         General - 500 tickets.',
        '  Duskruin Arena - 44,068 bloodscrip.',
        '            Reim - 480 ethereal scrip.',
        '       Ebon Gate - 27,374 soul shards.',
        '     Rumor Woods - 21,995 raikhen.'
      ]
      expect(parse.tickets(lines)).to eq([
                                           { source: 'General', currency: 'tickets', amount: 500 },
                                           { source: 'Duskruin Arena', currency: 'bloodscrip', amount: 44_068 },
                                           { source: 'Reim', currency: 'ethereal scrip', amount: 480 },
                                           { source: 'Ebon Gate', currency: 'soul shards', amount: 27_374 },
                                           { source: 'Rumor Woods', currency: 'raikhen', amount: 21_995 }
                                         ])
    end

    it 'reads EVENT ENTRIES' do
      lines = [
        '             Event Entries',
        ' --------------------------------------',
        '  Duskruin Entries:                  0',
        '  Ebon Gate Entries:                 2',
        '  Rumor Woods Entries:               0',
        '  Inquisitor Entries:                0',
        '  Trials of Lumnis Entries:      1,000',
        '',
        'To create physical entries, type EVENT ENTRIES {type} {amount}.  Current options include: DUSKRUIN  RUMOR  EBON  LUMNIS  INQUISITOR'
      ]
      expect(parse.entries(lines)).to eq([
                                           { event: 'Duskruin', amount: 0 },
                                           { event: 'Ebon Gate', amount: 2 },
                                           { event: 'Rumor Woods', amount: 0 },
                                           { event: 'Inquisitor', amount: 0 },
                                           { event: 'Trials of Lumnis', amount: 1000 }
                                         ])
    end

    it 'reads GEM LIST ALL, one row per property' do
      rows = parse.gemstones(CatalogSpec::GEM_LIST)
      expect(rows.size).to eq(13)
      expect(rows[0]).to eq(slot: 1, jewel: 'asymmetrical cerulean jewel', equipped: true, binding: 'greater binding',
                            property: 'Flare Resonance', mnemonic: 'flareres', rank: 5, max_rank: 5)
      expect(rows[1].values_at(:property, :rank, :max_rank)).to eq(['Lost Arcanum', 0, 0])
      expect(rows.last.values_at(:slot, :equipped, :binding, :property)).to eq([7, false, 'lesser binding', "Journey's Beginning"])
    end

    it 'keeps a gemstone with no properties yet' do
      expect(parse.gemstones(['Gemstone 1: a plain jewel']).map { |r| r[:property] }).to eq([''])
    end

    it 'reads a property rarity from GEM INFO' do
      lines = ['<output class="mono"/>', '', 'Property:    Flare Resonance', 'Mnemonic:    flareres', 'Description: Something.', 'Rarity:      Common']
      expect(parse.gem_rarity(lines)).to eq('common')
    end

    it 'reads no gemstones when they are not unlocked' do
      expect(parse.gemstones(['You have not yet unlocked Gemstones.'])).to eq([])
    end

    it 'reads BANK ACCOUNT without the total' do
      lines = [
        'You currently have the following amounts on deposit:',
        '  First Elanith Secured Bank: 12,345',
        '  Great Bank of Kharam-Dzu: 100',
        '  Total: 12,445',
        'You currently have 3 inter-town bank transfer options available.'
      ]
      expect(parse.bank(lines)).to eq([
                                        { bank: 'First Elanith Secured Bank', amount: 12_345 },
                                        { bank: 'Great Bank of Kharam-Dzu', amount: 100 }
                                      ])
    end

    it 'reads a free account single bank line' do
      line = 'You currently have an account with the Icemule Trace Bank in the amount of 2,000 silver.'
      expect(parse.bank([line])).to eq([{ bank: 'Icemule Trace Bank', amount: 2000 }])
    end

    it 'turns account types into subscriptions' do
      expect(%w[FREE NORMAL PREMIUM PLATINUM].map { |t| parse.subscription(t) }).to eq(%w[f2p standard premium premium])
    end

    it 'makes plural item names singular' do
      expect(parse.singular('uncut diamonds')).to eq('uncut diamond')
      expect(parse.singular('blue rubies')).to eq('blue ruby')
      expect(parse.singular('pieces of glass')).to eq('piece of glass')
    end

    describe '.manifest' do
      let(:lines) do
        [
          "Thinking back, you recall the following items in your locker in Wehnimer's Landing:",
          '  On an armor stand:',
          '      some full leather (registered)',
          '  In a magical item bin:',
          '      a glass jar containing uncut diamonds (12/50)',
          '      a leather pouch',
          '        a blue sapphire',
          'Obvious items: 4'
        ]
      end

      it 'reads paths, flags and jar contents' do
        rows, shown, read = parse.manifest(lines, 11)
        expect([shown, read]).to eq([4, 4])
        expect(rows.map { |r| r.values_at(:path, :name, :amount, :stack, :status, :registered) }).to eq([
                                                                                                          ['stand', 'full leather', 1, '', '', true],
                                                                                                          ['bin', 'glass jar containing uncut diamonds', 1, '', 'partial', false],
                                                                                                          ['bin > jar', 'uncut diamond', 12, 'jar', '', false],
                                                                                                          ['bin', 'leather pouch', 1, '', '', false],
                                                                                                          ['bin > pouch', 'blue sapphire', 1, '', '', false]
                                                                                                        ])
      end
    end

    it 'reads registered/marked/hidden from INVENTORY FULL by item id' do
      lines = [
        'You are currently wearing:',
        '  a <a exist="101" noun="cloak">voluminous mist tartan cloak</a> lined in silver-tipped aquerne (registered) (marked)',
        '      a <a exist="102" noun="cube">solid moonstone cube</a>',
        '      a <a exist="103" noun="orb">shimmering indigo orb</a> (marked)',
        ' ',
        '(Items: 3)'
      ]
      expect(parse.inventory_flags(lines)).to eq(
        '101' => { marked: true, registered: true, hidden: false },
        '102' => { marked: false, registered: false, hidden: false },
        '103' => { marked: true, registered: false, hidden: false }
      )
    end

    it "drops the game's uncommon tag from item types" do
      expect(parse.item_type('bronze-bound compendium', 'compendium')).to eq('unknown')
      expect(parse.item_type('indigo orb', 'orb')).to eq('magic')
    end

    it 'turns an inventory tree into rows' do
      pack = CatalogSpec::FakeItem.new('1', 'pack', 'a pack', 'a scuffed pack', [], [], nil)
      gem = CatalogSpec::FakeItem.new('2', 'diamond', 'an uncut diamond', nil, ['marked'], [], pack)
      pack.children << gem
      rows = parse.tree_rows(pack, 2)
      expect(rows.map { |r| r.values_at(:level, :path, :name, :type, :marked) }).to eq([
                                                                                         [0, '', 'scuffed pack', 'unknown', false],
                                                                                         [1, 'pack', 'uncut diamond', 'gem', true]
                                                                                       ])
    end
  end

  describe 'Store and Query' do
    let(:db) { catalog::Store.connect }
    let(:store) { catalog::Store }

    before do
      store.db = db
      @account = store.save_account('Acct', 'premium', 100)
      @xan = store.save_character('Xanlin', 'GS3', { account_id: @account, prof: 'Wizard', level: 100 }, 100)
      @bob = store.save_character('Bob', 'GS3', { account_id: @account }, 100)
    end

    after { store.db = nil }

    def item(name, **fields)
      { location_id: 2, level: 0, path: '', type: 'gem', name: name, noun: name.split.last, amount: 1,
        stack: '', status: '', marked: false, registered: false, hidden: false }.merge(fields)
    end

    def sync_items(character_id, rows, now, location_id: 2)
      owner = { account_id: @account, character_id: character_id, game: 'GS3', location_id: location_id }
      store.sync(:item, owner, store::ITEM_KEY, rows.map { |r| r.merge(location_id: location_id) }, now)
    end

    it 'keeps first_seen, moves last_seen, and counts what changed' do
      expect(sync_items(@xan, [item('uncut diamond'), item('uncut diamond'), item('blue sapphire')], 100))
        .to eq(inserted: 2, updated: 0, deleted: 0)
      expect(db[:item].where(name: 'uncut diamond').get(:amount)).to eq(2)

      expect(sync_items(@xan, [item('uncut diamond'), item('green emerald')], 200))
        .to eq(inserted: 1, updated: 1, deleted: 1)
      diamond = db[:item].where(name: 'uncut diamond').first
      expect(diamond.values_at(:amount, :first_seen, :last_seen)).to eq([1, 100, 200])
      expect(db[:item].select_order_map(:name)).to eq(['green emerald', 'uncut diamond'])
    end

    it 'keeps family vault items on the account, apart from the characters' do
      sync_items(nil, [item('vault gem')], 100, location_id: catalog::FAMILY_VAULT)
      sync_items(@xan, [], 100, location_id: catalog::FAMILY_VAULT)
      expect(db[:item].where(character_id: nil).count).to eq(1)
    end

    it 'shrinks the database file as rows are deleted' do
      Dir.mktmpdir do |dir|
        file_db = catalog::Store.connect(File.join(dir, 'catalog.db3'))
        expect(file_db.fetch('PRAGMA auto_vacuum').single_value).to eq(1)
        file_db.disconnect
      end
    end

    it 'counts a single-row save as inserted, then updated only when it changes' do
      lumnis = { status: '', triple: 10, double: 0, total: 20, start_day: '', start_time: '', last_schedule: '' }
      expect(store.save_row(:lumnis, @xan, lumnis, 100)).to eq(inserted: 1, updated: 0, deleted: 0)
      expect(store.save_row(:lumnis, @xan, lumnis, 200)).to eq(inserted: 0, updated: 0, deleted: 0)
      expect(store.save_row(:lumnis, @xan, lumnis.merge(triple: 5), 300)).to eq(inserted: 0, updated: 1, deleted: 0)
    end

    it 'deletes a character with everything saved for it' do
      sync_items(@xan, [item('uncut diamond')], 100)
      store.sync(:silver, { character_id: @xan }, %i[bank], [{ bank: 'Teras', amount: 5 }], 100)
      db[:character].where(id: @xan).delete
      expect([db[:item].count, db[:silver].count]).to eq([0, 0])
    end

    describe 'queries' do
      let(:cli) { catalog::CLI }

      before do
        sync_items(@xan, [item('uncut diamond', amount: 3), item('glass jar', type: 'jar', status: 'full', marked: true)], 100)
        sync_items(@bob, [item('uncut diamond')], 100)
        sync_items(nil, [item('blue sapphire')], 100, location_id: catalog::FAMILY_VAULT)
      end

      def run(action, target, *args)
        filters, extras = cli.parse(args)
        filters << { name: 'game', op: '=', value: 'GS3' }
        catalog::Query.run(db, action, target, filters, extras)
      end

      it 'searches item names, with * as a wildcard' do
        _headers, rows = run('query', 'item', 'unc*mond')
        expect(rows.map { |r| [r[0], r[3]] }).to eq([['Bob', 1], ['Xanlin', 3]])
      end

      it 'filters by character, flag and regex' do
        expect(run('query', 'item', 'char=xan*', 'm=y')[1].map(&:last)).to eq(['glass jar'])
        expect(run('query', 'item', 'char=xan')[1]).to be_empty
        expect(run('query', 'item', '/^(BLUE|glass) /')[1].map(&:last)).to eq(['blue sapphire', 'glass jar'])
        expect(run('query', 'item', 'name!=/diamond/')[1].size).to eq(2)
      end

      it 'shows family vault items under the account name' do
        expect(run('query', 'item', 'loc=fam')[1].map(&:first)).to eq(['Acct'])
      end

      it 'adds up items by type with a total' do
        headers, rows = run('sum', 'item', 'type=gem')
        expect(headers).to eq(%i[type qty item])
        expect(rows).to eq([['gem', 4, 'uncut diamond'], ['gem', 1, 'blue sapphire'], ['gem', 5, 'total']])
      end

      it 'adds up bank accounts with a grand total' do
        store.sync(:silver, { character_id: @xan }, %i[bank], [{ bank: 'Teras', amount: 5 }], 100)
        store.sync(:silver, { character_id: @bob }, %i[bank], [{ bank: 'Teras', amount: 7 }], 100)
        rows = run('sum', 'bank')[1]
        expect(rows.map { |r| r[0..1] }).to eq([['Teras', 12], ['grand total', 12]])
        expect(rows[0][2].split(', ')).to contain_exactly('Bob', 'Xanlin')
      end

      it 'lists event entries' do
        store.sync(:entries, { character_id: @xan }, %i[event], [{ event: 'Ebon Gate', amount: 2 }], 100)
        expect(run('query', 'entries', 'amount>0')[1].map { |r| r[0..2] }).to eq([['Xanlin', 'Ebon Gate', 2]])
      end

      it 'lists gemstones and who has each property' do
        gem_rows = parse.gemstones(CatalogSpec::GEM_LIST)
        store.sync(:gemstone, { character_id: @xan }, %i[slot jewel property], gem_rows, 100)
        store.sync(:gemstone, { character_id: @bob }, %i[slot jewel property], gem_rows.first(1), 100)
        headers, rows = run('query', 'gemstones', 'char=Xanlin')
        expect(headers).to eq(%i[name gem eq binding jewel properties])
        expect(rows.first[0..4]).to eq(['Xanlin', 1, true, 'greater', 'asymmetrical cerulean jewel'])
        expect(rows.first[5].split(', ')).to contain_exactly('Flare Resonance (5/5)', 'Lost Arcanum', 'Charged Presence')
        db[:gemstone_property].insert(mnemonic: 'flareres', rarity: 'common')
        flare = run('sum', 'gemstones', 'flare*')[1]
        expect(flare.map { |r| r[0..2] }).to eq([['Flare Resonance', 'common', 2]])
        expect(flare[0][3].split(', ')).to contain_exactly('Bob', 'Xanlin')
        expect(run('query', 'gemstones', 'rarity=common')[1].map { |r| r[0..1] }).to contain_exactly(['Xanlin', 1], ['Bob', 1])
        expect(run('query', 'gemstones', 'equipped=n')[1].map { |r| r[1] }).to eq([6, 7])
      end

      it 'counts carried items on the character list' do
        headers, rows = run('query', 'character')
        expect(rows.to_h { |r| [r[headers.index(:name)], r[headers.index(:inv)]] }).to eq('Bob' => 1, 'Xanlin' => 4)
      end
    end
  end

  describe 'CLI' do
    let(:cli) { catalog::CLI }

    it 'takes abbreviated actions and targets' do
      args = %w[q i golden]
      expect([cli.take(args, cli::ACTIONS), cli.take(args, cli::TARGETS), args]).to eq(['query', 'item', ['golden']])
      expect(cli.abbreviation('inv', cli::TARGETS)).to eq('inventory')
      expect(cli.abbreviation('l', cli::TARGETS)).to eq('locker')
      expect(%w[silver scrip].map { |w| cli.abbreviation(w, cli::TARGETS) }).to eq(%w[bank tickets])
    end

    it 'treats a whole target name with no action as a query of it' do
      expect(%w[item inv bank gemstones].map { |word| cli.command([word]) }).to eq([
                                                                                     ['query', nil, 'item'], ['query', nil, 'inventory'],
                                                                                     ['query', nil, 'bank'], ['query', nil, 'gemstones']
                                                                                   ])
      args = %w[i golden]
      expect([cli.command(args), args]).to eq([['query', nil, 'item'], %w[i golden]])
      args = %w[silver wand]
      expect([cli.command(args), args]).to eq([['query', nil, 'item'], %w[silver wand]])
      expect(cli.command(%w[export sum bank])).to eq(%w[export sum bank])
      expect(cli.command(%w[refresh])).to eq(['refresh', nil, 'all'])
    end

    it 'splits filters, extras and search words' do
      filters, extras = cli.parse(['t=gem', 'qty>5', 'c=Xan|Bob', 'orderby="qty-"', 'limit=3', 'golden', 'glim'])
      expect(filters).to eq([
                              { name: 'type', op: '=', value: 'gem' },
                              { name: 'amount', op: '>', value: 5 },
                              { name: 'character', op: '=', value: %w[Xan Bob] },
                              { name: 'search', op: '=', value: 'golden glim' }
                            ])
      expect(extras).to eq(orderby: 'qty desc', limit: 3)
    end

    it 'keeps a regex with spaces together' do
      filters, = cli.parse(['name=/blue', 'star/', 'gem'])
      expect(filters.map { |f| f[:value] }).to eq([/blue star/, 'gem'])
    end
  end

  describe 'Output' do
    it 'shows change counts as numbers, not dates' do
      lines = catalog::Output.table(%i[table inserted updated deleted], [['lumnis', 0, 1, 0]], dates: [])
      expect(lines[3]).to eq('lumnis |        0 |       1 |       0')
    end

    it 'right-aligns numbers and marks flags' do
      lines = catalog::Output.table(%i[name qty m item], [['Xanlin', 1234, true, 'uncut diamond']])
      expect(lines[1]).to eq('name   |   qty | m | item')
      expect(lines[3]).to eq('Xanlin | 1,234 | Y | uncut diamond')
    end
  end
end
