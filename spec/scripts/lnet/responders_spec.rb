# frozen_string_literal: true

require_relative 'support/harness'

# Requests other players send for this character's information (their
# ';locate Name' and friends) and the request types scripts register with
# LNet.add_callback. Requests arrive as XML through the real parser and
# listener; replies are read back from what the script writes to the server.
module LnetSpec
  STOCK_TYPES = %w[spells skills info locate health bounty].freeze
end

RSpec.describe 'lnet.lic request handling' do
  let(:server) { LnetSpec::FakeServer.new }

  before { lnet.server = server }

  def request(type, from: 'GSIV:Bob')
    feed(%(<request type="#{type}" from="#{from}"/>))
  end

  # @return [Array<Hash>] each <data> reply: its attributes plus the decoded payload
  def replies
    server.lines.map do |line|
      element = REXML::Document.new(line).root
      next unless element&.name == 'data'

      element.attributes.to_h { |name, attribute| [name, attribute.value] }.merge('payload' => lnet::SafeMarshal.decode(element.text))
    end.compact
  end

  def reply = replies.last

  def allow_request(type, group) = lnet.options['permission'][type] = group

  describe 'who gets an answer' do
    # [permission, requester, answered?]
    [
      [nil, 'GSIV:Bob', false],
      ['none', 'GSIV:Bob', false],
      ['all', 'GSIV:Bob', true],
      ['friends', 'GSIV:Bob', false],
      ['friends', 'GSIV:Fred', true],
      ['friends', 'DR:Fred', true], # a friend listed without a game matches every game
      ['friends', 'GSIV:Prefixed', true],
      ['friends', 'DR:Prefixed', false], # but one listed with a game matches only that game
      ['enemies', 'GSIV:Bob', true],
      ['enemies', 'GSIV:Ed', false],
      ['nonsense', 'GSIV:Bob', false]
    ].each do |permission, from, answered|
      LnetSpec::STOCK_TYPES.each do |type|
        it "#{answered ? 'answers' : 'declines'} #{type} from #{from} when the permission is #{permission.inspect}" do
          lnet.options['friends'] = ['Fred', 'GSIV:Prefixed']
          lnet.options['enemies'] = ['Ed']
          allow_request(type, permission)
          allow(lnet::Responders).to receive(type).and_return({ 'answer' => type })
          request(type, from: from)
          expect(replies.size).to eq(1)
          expect(reply).to include('type' => type, 'to' => from)
          expect(reply['payload']).to(answered ? eq({ 'answer' => type }) : be_nil)
        end
      end
    end

    it 'matches list entries saved in another case, such as an old dr:Bob' do
      lnet.options['friends'] = ['dr:bob']
      lnet.options['ignore'] = ['gsiv:MAL']
      expect(lnet.friend?('DR:Bob')).to be(true)
      expect(lnet.ignored?('GSIV:Mal')).to be(true)
      expect(lnet.friend?('GSIV:Bob')).to be(false)
    end

    it 'declines someone the user ignores, even when everyone is allowed, without saying so' do
      lnet.options['ignore'] = ['Bob']
      allow_request('locate', 'all')
      out = request('locate')
      expect(reply['payload']).to be_nil
      expect(out.map(&:first)).not_to include(:echo)
    end

    it 'tells the user what it sent and what it refused' do
      allow_request('health', 'all')
      allow(lnet::Responders).to receive(:health).and_return({})
      expect(request('health')).to include([:echo, 'sending health to GSIV:Bob...'])
      expect(request('info')).to include([:echo, 'rejecting request from GSIV:Bob for stats...'])
    end

    it 'answers a bounty request without saying so, as lnet always has (scripts poll it)' do
      allow_request('bounty', 'all')
      allow(lnet::Responders).to receive(:bounty).and_return('a task')
      expect(request('bounty').map(&:first)).not_to include(:echo)
      expect(reply['payload']).to eq('a task')
    end

    it 'declines an unknown request type at once' do
      expect(request('horoscope')).to include([:echo, 'rejecting unknown request (horoscope) from GSIV:Bob...'])
      expect(reply).to include('type' => 'horoscope', 'payload' => nil)
    end

    %w[handle answer reply stock_handler own_status method instance_eval send].each do |name|
      it "treats a request typed #{name.inspect} as unknown rather than running the method of that name" do
        lnet.options['permission'][name] = 'all'
        expect(request(name)).to include([:echo, "rejecting unknown request (#{name}) from GSIV:Bob..."])
        expect(reply).to include('type' => name, 'payload' => nil)
      end
    end
    
    it 'sends nothing and raises nothing for a request without a type or sender' do
      expect { feed(%(<request from="GSIV:Bob"/><request type="info"/>)) }.not_to raise_error
      expect(server.lines).to be_empty
    end
  end

  describe 'a responder that fails' do
    it 'declines at once instead of leaving the asker to time out' do
      allow_request('skills', 'all')
      allow(lnet::Responders).to receive(:skills).and_raise(NameError, 'uninitialized constant Skills')
      out = request('skills')
      expect(reply).to include('type' => 'skills', 'payload' => nil)
      expect(out).to include([:echo, 'could not answer the skills request: NameError: uninitialized constant Skills'])
    end

    it 'declines skills and info in DragonRealms, where Skills, Spells and Stats do not exist' do
      %w[Skills Spells Stats].each { |name| hide_const("LnetSpec::Harness::#{name}") if LnetSpec::Harness.const_defined?(name, false) }
      allow_request('skills', 'all')
      allow_request('info', 'all')
      request('skills')
      request('info')
      expect(replies.map { |r| [r['type'], r['payload']] }).to eq([['skills', nil], ['info', nil]])
    end
  end

  describe 'what each stock request sends' do
    before do
      skip 'needs a lich-5 checkout for the real Skills, Spells and Stats' unless LnetSpec.lich5_attributes?
      LnetSpec::STOCK_TYPES.each { |type| allow_request(type, 'all') }
    end

    it 'names only skills and spell lists Lich really has' do
      lnet::Responders::SKILLS.each { |label, method| expect(LnetSpec::Harness::Skills).to respond_to(method), label }
      lnet::Responders::SPELL_LISTS.each { |label, method| expect(LnetSpec::Harness::Spells).to respond_to(method), label }
      lnet::Responders::STATS.each { |label, method| expect(LnetSpec::Harness::Stats).to respond_to(method), label }
    end

    it 'sends trained skills and spell lists only' do
      LnetSpec::Game.infomon.merge!('skill.edged_weapons' => 101, 'skill.dodging' => 0, 'skill.elemental_lore_air' => 24,
                                    'spell.minor_elemental' => 30, 'spell.minor_mental' => 0)
      request('skills')
      expect(reply['payload']).to eq('Edged Weapons' => 101, 'Elemental Lore - Air' => 24, 'Minor Elemental' => 30)
    end

    it 'sends stats as [value, bonus], experience as text, and mana' do
      LnetSpec::Game.infomon.merge!('stat.race' => 'Elf', 'stat.profession' => 'Wizard', 'stat.strength' => 80,
                                    'stat.strength_bonus' => 15)
      LnetSpec::Harness::XMLData.level = 100
      LnetSpec::Harness::XMLData.exp = 12_345_678
      LnetSpec::Harness::XMLData.mana = 412
      request('info')
      expect(reply['payload']).to include('Race' => 'Elf', 'Profession' => 'Wizard', 'Expr' => '12345678', 'Level' => 100,
                                          'Strength' => [80, 15], 'Wisdom' => [nil, nil], 'Mana' => 412)
    end

    it 'sends active spells by number with minutes left' do
      LnetSpec::Game.active_spells = [LnetSpec::ActiveSpell.new(101, 12.5), LnetSpec::ActiveSpell.new(1035, 0.5)]
      request('spells')
      expect(reply['payload']).to eq('101' => 12.5, '1035' => 0.5)
    end

    describe 'locate' do
      before do
        xml = LnetSpec::Harness::XMLData
        xml.room_title = '[Town Square]'
        xml.room_description = 'A square.'
        xml.room_exits_string = 'Obvious paths: north'
        LnetSpec::Game.pcs = [LnetSpec::Obj.new('Ann', 'lying down')]
        LnetSpec::Game.npcs = [LnetSpec::Obj.new('a rat', nil)]
        LnetSpec::Game.loot = [LnetSpec::Obj.new('a sword', nil)]
      end

      it 'sends the room with its map id, the people in it and this character last' do
        LnetSpec::Game.room = LnetSpec::MapRoom.new(228)
        request('locate')
        expect(reply['payload']).to eq('title' => '[Town Square]', 'description' => 'A square.', 'exits' => 'Obvious paths: north',
                                       'id' => 228, 'loot' => ['a sword'],
                                       'pcs' => [{ 'name' => 'Ann', 'status' => 'lying down' }, { 'name' => 'Tester', 'status' => nil }],
                                       'npcs' => [{ 'name' => 'a rat', 'status' => nil }])
      end

      it 'sends no id at all for a room that is not mapped, so to.lic falls back to its title search' do
        request('locate')
        expect(reply['payload']).not_to have_key('id')
      end

      it "describes this character's own state" do
        LnetSpec::Game.status = %i[stunned kneeling]
        request('locate')
        expect(reply['payload']['pcs'].last).to eq('name' => 'Tester', 'status' => 'stunned kneeling')
      end

      %i[hidden invisible].each do |state|
        it "leaves this character out while #{state}" do
          LnetSpec::Game.status = [state]
          request('locate')
          expect(reply['payload']['pcs'].map { |pc| pc['name'] }).to eq(['Ann'])
        end
      end
    end

    it 'sends health, spirit, stamina and injuries' do
      xml = LnetSpec::Harness::XMLData
      xml.injuries = { 'head' => { 'wound' => 1, 'scar' => 0 } }
      xml.health = 90
      xml.max_health = 120
      request('health')
      expect(reply['payload']).to include('injuries' => { 'head' => { 'wound' => 1, 'scar' => 0 } }, 'health' => 90, 'max_health' => 120)
    end

    it 'sends the current task' do
      LnetSpec::Game.bounty = 'You have been tasked to hunt down and kill a rat.'
      request('bounty')
      expect(reply['payload']).to eq('You have been tasked to hunt down and kill a rat.')
    end
  end

  describe 'LNet.add_callback' do
    it 'answers a new request type only for players the user allows' do
      lnet.add_callback('roundtime') { |_request| { 'hard' => 3 } }
      out = request('roundtime')
      expect(reply['payload']).to be_nil
      expect(out).to include([:echo, 'rejecting request from GSIV:Bob for roundtime info...'])
      allow_request('roundtime', 'all')
      request('roundtime')
      expect(reply['payload']).to eq('hard' => 3)
    end

    it 'hands the callback the request, including who sent it' do
      seen = nil
      lnet.add_callback(:whoami) { |req| seen = req }
      allow_request('whoami', 'all')
      request('whoami', from: 'DR:Ann')
      expect(seen).to eq('type' => 'whoami', 'from' => 'DR:Ann')
    end

    it 'uses the latest registration for a type' do
      lnet.add_callback('pick') { 'first' }
      lnet.add_callback('pick') { 'second' }
      allow_request('pick', 'all')
      request('pick')
      expect(reply['payload']).to eq('second')
    end

    it 'replaces a stock answer until the callback is removed' do
      skip 'needs a lich-5 checkout for the real Skills, Spells and Stats' unless LnetSpec.lich5_attributes?
      allow_request('bounty', 'all')
      LnetSpec::Game.bounty = 'real task'
      lnet.add_callback('bounty') { 'none of your business' }
      request('bounty')
      expect(reply['payload']).to eq('none of your business')
      lnet.remove_callback('bounty')
      request('bounty')
      expect(reply['payload']).to eq('real task')
    end

    [['a Time', -> { Time.at(0) }], ['an object', -> { Object.new }], ['a Proc', -> { proc {} }],
     ['a hash holding a Struct', -> { { 'k' => LnetSpec::Pair.new(1) } }]].each do |label, value|
      it "declines instead of sending #{label}, which the asker would refuse" do
        lnet.add_callback('odd') { value.call }
        allow_request('odd', 'all')
        out = request('odd')
        expect(reply).to include('type' => 'odd', 'payload' => nil)
        expect(out.last[1]).to start_with('could not answer the odd request:')
      end
    end

    it 'declines when the callback raises' do
      lnet.add_callback('boom') { raise 'kaboom' }
      allow_request('boom', 'all')
      expect(request('boom')).to include([:echo, 'could not answer the boom request: RuntimeError: kaboom'])
      expect(reply['payload']).to be_nil
    end

    it 'declines, without stopping the connection, when the callback raises LoadError' do
      lnet.add_callback('gem') { raise LoadError, 'cannot load such file -- missing' }
      allow_request('gem', 'all')
      out = nil
      expect { out = request('gem') }.not_to raise_error
      expect(out.last[1]).to eq('could not answer the gem request: LoadError: cannot load such file -- missing')
      expect(reply['payload']).to be_nil
    end

    it 'declines, without stopping the connection, when the callback overflows the stack' do
      lnet.add_callback('deep') { recurse = ->(n) { recurse.call(n + 1) }; recurse.call(0) }
      allow_request('deep', 'all')
      out = nil
      expect { out = request('deep') }.not_to raise_error
      expect(out.last[1]).to start_with('could not answer the deep request: SystemStackError')
      expect(reply['payload']).to be_nil
    end

    it "accepts 0net's add_callback(name, type) form" do
      lnet.add_callback(:my_roundtime, 'roundtime') { |_request| { 'hard' => 3 } }
      expect(lnet.callbacks.keys).to eq(['roundtime'])
      allow_request('roundtime', 'all')
      request('roundtime')
      expect(reply['payload']).to eq('hard' => 3)
    end

    it 'refuses a registration without a block or a type' do
      expect { lnet.add_callback('x') }.to raise_error(ArgumentError)
      expect { lnet.add_callback('') { 1 } }.to raise_error(ArgumentError)
    end

    it 'forgets every callback on clear_callbacks!' do
      lnet.add_callback('a') { 1 }
      lnet.clear_callbacks!
      expect(lnet.callbacks).to be_empty
    end
  end

  describe 'LNet.start_user_callbacks' do
    it "starts the user's lnet-callbacks script when it exists and is not running" do
      LnetSpec::Game.scripts = ['lnet-callbacks']
      expect(lnet.start_user_callbacks).to be(true)
      expect(LnetSpec::Game.started).to eq([['lnet-callbacks']])
    end

    it 'does nothing when there is no such script, or it is already running' do
      expect(lnet.start_user_callbacks).to be(false)
      LnetSpec::Game.scripts = ['lnet-callbacks']
      LnetSpec::Game.running = ['lnet-callbacks']
      expect(lnet.start_user_callbacks).to be(false)
      expect(LnetSpec::Game.started).to be_empty
    end
  end

  describe 'LNet.safe_send' do
    it 'sends at most one message every 3 seconds' do
      expect(lnet.safe_send({ 'type' => 'channel' }, 'one')).to be(true)
      expect(lnet.safe_send({ 'type' => 'channel' }, 'too soon')).to be(false)
      lnet.class_variable_set(:@@last_safe_send, Time.now - 2.9)
      expect(lnet.safe_send({ 'type' => 'channel' }, 'still too soon')).to be(false)
      lnet.class_variable_set(:@@last_safe_send, Time.now - 3)
      expect(lnet.safe_send({ 'type' => 'channel' }, 'two')).to be(true)
      expect(server.lines.grep(/<message/).size).to eq(2)
    end

    it 'is not held back by keepalives or other traffic' do
      lnet.send_ping
      lnet.send_query({ 'type' => 'connected' })
      expect(lnet.safe_send({ 'type' => 'channel' }, 'announce')).to be(true)
    end
  end
end
