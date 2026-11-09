# frozen_string_literal: true

require_relative 'support/harness'

# LNet::Listener and LNet::Thoughts: what each element from the server does,
# fed through the real parser.
RSpec.describe 'lnet.lic listener' do
  around do |example|
    saved = [$frontend, $_CLIENT_, $_SERVERBUFFER_]
    $frontend = 'stormfront'
    $_CLIENT_ = LnetSpec::FakeClient.new
    $_SERVERBUFFER_ = []
    example.run
  ensure
    $frontend, $_CLIENT_, $_SERVERBUFFER_ = saved
  end

  let(:server) { LnetSpec::FakeServer.new }

  before { lnet.server = server }

  def kinds(out, kind) = out.select { |k, _| k == kind }.map(&:last)

  describe 'aliases' do
    before { lnet.alias['GSIV:Jeril'] = 'StrangerDanger' }

    it 'show the alias to the user and the real name to scripts' do
      out = feed(%(<message type="private" from="GSIV:Jeril">slack_token: abc</message>))
      expect(kinds(out, :_respond).first).to include('[Private]-StrangerDanger: "slack_token: abc"')
      expect(kinds(out, :downstream)).to eq(['[Private]-GSIV:Jeril: "slack_token: abc"'])
      expect(kinds(out, :downstream_xml).first).to include('[Private]-GSIV:Jeril:')
      expect($_SERVERBUFFER_.first).to include('[Private]-GSIV:Jeril:')
    end

    it "let lich-5 SlackBot's token pattern and inbox.lic's pattern match an aliased sender" do
      out = feed(%(<message type="private" from="GSIV:Jeril">slack_token: abc</message>))
      line = kinds(out, :downstream).first
      expect(line).to match(/\[Private\]-.*:Jeril: "slack_token: (?<token>.*)"/)
      expect(line).to match(/^\[Private\]-GSIV:(?<from>.*?): "(?<body>.*?)"/)
    end

    it 'on Wizard, show the alias in the client line' do
      $frontend = 'wizard'
      out = feed(%(<message type="private" from="GSIV:Jeril">hi</message>))
      expect(kinds(out, :client).first).to include('[Private]-StrangerDanger echo in your mind')
      expect(kinds(out, :downstream)).to eq(['[Private]-GSIV:Jeril: "hi"'])
    end
  end

  it 'echoes your own long private message' do
    long = 'x' * 600
    out = feed(%(<message type="privateto" to="GSIV:Bob">#{long}</message>))
    expect(kinds(out, :downstream)).to eq([%([PrivateTo]-GSIV:Bob: "#{long}")])
  end

  it 'shows a message split into several text parts as one line' do
    out = feed(%(<message type="channel" from="GSIV:Ann" channel="General">one <![CDATA[two]]> three</message>))
    expect(kinds(out, :downstream)).to eq(['[General]-GSIV:Ann: "one two three"'])
  end

  it 'shows nothing for an empty message and keeps the reply target' do
    lnet.last_priv = 'GSIV:Ann'
    expect(feed(%(<message type="private" from="GSIV:Mal"/><message type="channel" from="GSIV:Bob" channel="General"/>))).to be_empty
    expect(lnet.last_priv).to eq('GSIV:Ann')
  end

  it 'remembers who sent the last private message, for ;reply' do
    feed(%(<message type="private" from="GSIV:Ann">hi</message>))
    expect(lnet.last_priv).to eq('GSIV:Ann')
  end

  it 'hides chat from an ignored sender from the user but still passes it to scripts' do
    lnet.options['ignore'] = ['Ann']
    out = feed(%(<message type="channel" from="GSIV:Ann" channel="General">hi</message>))
    expect(kinds(out, :_respond)).to be_empty
    expect(kinds(out, :downstream)).to eq(['[General]-GSIV:Ann: "hi"'])
  end

  it 'ignores a channel message without a sender or channel, and a private one without a sender' do
    out = feed(%(<message type="channel" from="GSIV:Ann">a</message><message type="channel" channel="X">b</message><message type="private">c</message>))
    expect(out).to be_empty
  end

  it 'shows the greeting only when the greeting option is on' do
    lnet.options['greeting'] = false
    expect(feed(%(<message type="greeting">Welcome\x07!</message>))).to be_empty
    lnet.options['greeting'] = true
    expect(feed(%(<message type="greeting">Welcome!&#10;Line two</message>))).to eq([[:respond, "Welcome!\nLine two"]])
  end

  it 'explains a refused password and stops lnet instead of reconnecting with it' do
    script = double('script', name: 'lnet')
    expect(script).to receive(:kill)
    lnet.script = script
    out = feed(%(<message type="server">incorrect password for Tester</message>))
    expect(kinds(out, :respond).first).to include('type: ;lnet password=<password>')
    expect(kinds(out, :downstream)).to eq(['[server]: "incorrect password for Tester"'])
  ensure
    lnet.script = nil
  end

  it 'answers a ping with a pong and notes that something arrived' do
    lnet.class_variable_set(:@@last_recv, Time.at(0))
    feed('<ping/>')
    expect(server.lines).to eq(['<pong/>'])
    expect(lnet.last_recv).to be > Time.now - 5
  end

  it 'disconnects and waits when the server announces a restart' do
    feed(%(<notify type="server-restart"/>))
    expect(lnet.server_restart).to be(true)
    expect(server.closed?).to be(true)
    expect(lnet.connected?).to be(false)
  end

  it 'treats an empty <data> reply as no data' do
    asker = Thread.new { lnet.get_data('Bob', 'info') }
    sleep 0.01 until server.lines.any? || !asker.alive?
    feed(%(<data type="info" from="Bob"/>))
    expect(asker.join(2).value).to be_nil
  end

  it 'reports an error from handling one element and carries on with the next' do
    allow(lnet::Responders).to receive(:handle).and_raise('boom')
    out = feed(%(<request type="info" from="Bob"/><ping/>))
    expect(out).to include([:echo, 'error: boom'])
    expect(server.lines).to eq(['<pong/>'])
  end

  describe 'LNet.debug' do
    it 'echoes only when the debug option is on' do
      expect(LnetSpec.capture { lnet.debug('detail') }).to be_empty
      lnet.options['debug'] = true
      expect(LnetSpec.capture { lnet.debug('detail') }).to eq([[:echo, 'detail']])
    end
  end
end
