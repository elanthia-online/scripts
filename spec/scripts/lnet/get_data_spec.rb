# frozen_string_literal: true

require_relative 'support/harness'

# LNet.get_data: a script asks another player for information and waits for
# the reply. Each example runs the real get_data on a thread against a fake
# server, then feeds the reply XML through the real parser and listener.
RSpec.describe 'lnet.lic LNet.get_data' do
  let(:server) { LnetSpec::FakeServer.new }

  before { lnet.server = server }

  def requests
    server.lines.filter_map do |line|
      element = REXML::Document.new(line).root
      element.attributes.to_h { |name, attribute| [name, attribute.value] } if element&.name == 'request'
    end
  end

  def wait_for_requests(count)
    deadline = Time.now + 2
    sleep 0.005 until requests.size >= count || Time.now > deadline
    expect(requests.size).to be >= count
  end

  # Runs get_data on a thread and returns [thread, seconds it took].
  def ask(*args, **opts)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    thread = Thread.new do
      value = lnet.get_data(*args, **opts)
      [value, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
    end
    @threads = (@threads || []) << thread
    thread
  end

  after { (@threads || []).each(&:kill) }

  def answer(obj, from: 'Bob', type: 'info') = feed(data_element(obj, from: from, type: type))

  it 'returns the reply as soon as it arrives' do
    asker = ask('Bob', 'info')
    wait_for_requests(1)
    answer(LnetSpec::REAL_PAYLOADS['info'])
    value, took = asker.join(2).value
    expect(value).to eq(LnetSpec::REAL_PAYLOADS['info'])
    expect(took).to be < 1
  end

  it 'leaves the name it was given alone, frozen or not' do
    name = 'bob'
    expect(name).to be_frozen
    asker = ask(name, 'bounty')
    wait_for_requests(1)
    answer('a task', type: 'bounty')
    expect(asker.join(2).value.first).to eq('a task')
    expect(name).to eq('bob')
  end

  { 'bob' => 'Bob', ' bob ' => 'Bob', 'gsiv:bob' => 'GSIV:Bob', 'gsplat:bob' => 'GSPlat:Bob', 'dr:bob' => 'DR:Bob',
    'DRF:BOB' => 'DRF:Bob' }.each do |given, sent|
    it "sends a request for #{given.inspect} to #{sent.inspect}" do
      ask(given, 'info', timeout: 0.05).join(2)
      expect(requests).to eq([{ 'type' => 'info', 'to' => sent }])
    end
  end

  it 'returns nil when they decline, which is not the same as no answer' do
    asker = ask('Bob', 'locate')
    wait_for_requests(1)
    answer(nil, type: 'locate')
    expect(asker.join(2).value.first).to be_nil
  end

  it 'returns false when the server says there is no such user' do
    asker = ask('Nobody', 'locate')
    wait_for_requests(1)
    answer(false, from: 'Nobody', type: 'locate')
    expect(asker.join(2).value.first).to be(false)
  end

  it 'returns false at once when the reply holds something other than plain data' do
    asker = ask('Bob', 'info')
    wait_for_requests(1)
    LnetSpec::Gadget.loaded = 0
    answer(LnetSpec::Gadget.new)
    value, took = asker.join(2).value
    expect(value).to be(false)
    expect(took).to be < 1
    expect(LnetSpec::Gadget.loaded).to eq(0)
  end

  it 'returns false when nothing comes back in time' do
    value, took = ask('Bob', 'info', timeout: 0.2).join(2).value
    expect(value).to be(false)
    expect(took).to be_between(0.2, 1)
  end

  [[nil, 'info'], ['', 'info'], ['   ', 'info'], ['Bob', ''], ['Bob', :info], [:bob, 'info']].each do |name, type|
    it "returns false without sending anything for #{name.inspect}, #{type.inspect}" do
      expect(lnet.get_data(name, type)).to be(false)
      expect(server.lines).to be_empty
    end
  end

  it 'returns false without waiting when not connected' do
    lnet.server = nil
    value, took = ask('Bob', 'info').join(2).value
    expect(value).to be(false)
    expect(took).to be < 0.5
  end

  it 'returns false without waiting when the request cannot be written' do
    lnet.server = LnetSpec::FakeServer.new(fail_with: Errno::EPIPE)
    value, took = ask('Bob', 'info').join(2).value
    expect(value).to be(false)
    expect(took).to be < 0.5
  end

  it 'forgets the request afterwards, whether answered or not' do
    asker = ask('Bob', 'info')
    wait_for_requests(1)
    answer({})
    asker.join(2)
    ask('Ann', 'info', timeout: 0.05).join(2)
    expect(lnet.class_variable_get(:@@waiting)).to be_empty
  end

  describe 'which reply answers which request' do
    it 'takes a reply from the game-prefixed name for a request to the bare name' do
      asker = ask('bob', 'info')
      wait_for_requests(1)
      answer({ 'ok' => 1 }, from: 'GSIV:Bob')
      expect(asker.join(2).value.first).to eq('ok' => 1)
    end

    it 'takes a reply from the full name for a request to the start of it' do
      asker = ask('bo', 'info')
      wait_for_requests(1)
      answer({ 'ok' => 1 }, from: 'Bob')
      expect(asker.join(2).value.first).to eq('ok' => 1)
    end

    it 'ignores a reply of another type, from someone else, or from the same name in another game' do
      asker = ask('GSIV:Bob', 'info', timeout: 0.3)
      wait_for_requests(1)
      answer({ 'wrong' => 'type' }, from: 'GSIV:Bob', type: 'skills')
      answer({ 'wrong' => 'person' }, from: 'GSIV:Ann')
      answer({ 'wrong' => 'game' }, from: 'DR:Bob')
      expect(asker.join(2).value.first).to be(false)
    end

    it 'gives each of two waiting requests its own reply, whatever order the replies come in' do
      bob = ask('Bob', 'info')
      ann = ask('Ann', 'info')
      wait_for_requests(2)
      answer({ 'who' => 'Ann' }, from: 'Ann')
      answer({ 'who' => 'Bob' }, from: 'Bob')
      expect(bob.join(2).value.first).to eq('who' => 'Bob')
      expect(ann.join(2).value.first).to eq('who' => 'Ann')
    end

    [['Bob', 'a bare name'], ['GSIV:Bob', 'its game']].each do |gs_from, label|
      it "routes replies for the same name in two games to the right requests (GS reply carrying #{label})" do
        bare = ask('Bob', 'info')
        wait_for_requests(1)
        dr = ask('DR:Bob', 'info')
        wait_for_requests(2)
        answer({ 'game' => 'DR' }, from: 'DR:Bob')
        answer({ 'game' => 'GS' }, from: gs_from)
        expect(dr.join(2).value.first).to eq('game' => 'DR')
        expect(bare.join(2).value.first).to eq('game' => 'GS')
      end
    end

    it 'answers two identical requests with one reply each' do
      first = ask('Bob', 'info')
      second = ask('Bob', 'info')
      wait_for_requests(2)
      answer({ 'n' => 1 })
      answer({ 'n' => 2 })
      expect([first, second].map { |t| t.join(2).value.first }).to contain_exactly({ 'n' => 1 }, { 'n' => 2 })
    end

    it 'shows a reply nobody is waiting for any more instead of dropping it' do
      ask('Bob', 'bounty', timeout: 0.05).join(2)
      expect(answer('late task', type: 'bounty')).to include([:respond, "\nBob:\nlate task\n\n"])
    end
  end

  describe 'LNet.normalize_name' do
    { 'bob' => 'Bob', 'BOB' => 'Bob', 'gsiv:bob' => 'GSIV:Bob', 'GsPlAt:bob' => 'GSPlat:Bob', 'gst:bob' => 'GST:Bob',
      'drx:bob' => 'DRX:Bob', '' => '', 'x:' => 'X:' }.each do |given, expected|
      it "writes #{given.inspect} as #{expected.inspect}" do
        expect(lnet.normalize_name(given)).to eq(expected)
      end
    end
  end
end
