# frozen_string_literal: true

require_relative 'support/harness'

# LNet::StreamParser cuts the server's unframed byte stream into top-level
# elements. These examples feed it the shapes the server sends (attribute-only
# requests and notices, pings, messages, base64 <data>) in every combination
# and at every chunk boundary, and check that each element arrives exactly
# once, whole, in order.
RSpec.describe 'lnet.lic LNet::StreamParser' do
  let(:log) { LnetSpec::EventLog.new }
  let(:parser) { lnet::StreamParser.new(log) }

  # what the server writes, one kind of element each
  ELEMENTS = {
    'request' => %(<request type="info" from="GSIV:Bob"/>),
    'notify'  => %(<notify type="server-restart"/>),
    'ping'    => %(<ping/>),
    'message' => %(<message type="channel" from="GSIV:Ann" channel="General">hi &amp; bye</message>),
    'data'    => %(<data type="info" from="Bob">BAh7BkkiCVJh\nY2UGOgZFVEki\nCEVsZgY7AFQ=\n</data>)
  }.freeze

  def deliver_all(*chunks)
    chunks.each { |chunk| parser.feed(chunk) }
    log
  end

  describe 'two elements in one read' do
    ELEMENTS.to_a.product(ELEMENTS.to_a).each do |(first, first_xml), (second, second_xml)|
      it "delivers both a #{first} and the #{second} after it" do
        deliver_all("#{first_xml}\n#{second_xml}\n")
        expect(log.roots).to eq([first_xml[/<(\w+)/, 1], second_xml[/<(\w+)/, 1]])
      end
    end

    it 'delivers the message after a request without the request swallowing it' do
      deliver_all("#{ELEMENTS['request']}\n#{ELEMENTS['message']}\n")
      expect(log.events).to include([:text, 'hi & bye'])
    end
  end

  describe 'chunk boundaries' do
    let(:stream) { ELEMENTS.values.join("\n") + "\n" }
    let(:whole) { LnetSpec::EventLog.new.tap { |l| lnet::StreamParser.new(l).feed(stream) }.events }

    it 'gives the same events whichever byte the stream is split at' do
      (1...stream.bytesize).each do |cut|
        split_log = LnetSpec::EventLog.new
        split_parser = lnet::StreamParser.new(split_log)
        split_parser.feed(stream.byteslice(0, cut))
        split_parser.feed(stream.byteslice(cut..))
        expect(split_log.events).to eq(whole), "split at byte #{cut}: #{stream.byteslice(0, cut).inspect}"
      end
    end

    {
      'CDATA' => %(<message type="server">a<![CDATA[x > y </message> z]]>b</message><ping/>),
      'comment' => %(<message type="server">a<!-- q > <ping/> -->b</message><ping/>),
      'top-level comment' => %(<!-- a > <ping/> --><message type="server">hi</message>)
    }.each do |label, xml|
      it "gives the same events at every split of a #{label} section that holds '>'" do
        whole_log = LnetSpec::EventLog.new.tap { |l| lnet::StreamParser.new(l).feed(xml) }
        (1...xml.bytesize).each do |cut|
          split_log = LnetSpec::EventLog.new
          split_parser = lnet::StreamParser.new(split_log)
          split_parser.feed(xml.byteslice(0, cut))
          split_parser.feed(xml.byteslice(cut..))
          expect(split_log.events).to eq(whole_log.events), "split at byte #{cut}: #{xml.byteslice(0, cut).inspect}"
        end
        expect(whole_log.roots.count('ping')).to eq(label == 'top-level comment' ? 0 : 1)
      end
    end

    it 'gives the same events when fed one byte at a time' do
      stream.each_char { |byte| parser.feed(byte) }
      expect(log.events).to eq(whole)
    end

    it 'gives the same events for random chunkings of a long stream' do
      rng = Random.new(1_105)
      long = Array.new(60) { ELEMENTS.values.sample(random: rng) }.join("\n")
      expected = LnetSpec::EventLog.new.tap { |l| lnet::StreamParser.new(l).feed(long) }.events
      expect(expected.count { |kind, _| kind == :start }).to be >= 60
      50.times do
        chunked_log = LnetSpec::EventLog.new
        chunked = lnet::StreamParser.new(chunked_log)
        pos = 0
        while pos < long.bytesize
          size = rng.rand(1..40)
          chunked.feed(long.byteslice(pos, size))
          pos += size
        end
        expect(chunked_log.events).to eq(expected)
      end
    end

    it 'keeps a UTF-8 character that is split between two reads' do
      xml = %(<message type="channel" from="A" channel="X">caf#{LnetSpec::E_ACUTE}</message>).b
      cut = xml.index("\xC3".b) + 1
      deliver_all(xml.byteslice(0, cut), xml.byteslice(cut..))
      expect(log.events).to include([:text, "caf#{LnetSpec::E_ACUTE}"])
    end

    it 'returns how many elements each read completed' do
      expect(parser.feed(%(<ping/><notify type="x"/><message type="server">pa))).to eq(2)
      expect(parser.feed(%(rt</message>))).to eq(1)
      expect(parser.feed("\n")).to eq(0)
    end
  end

  describe 'element contents' do
    it 'delivers nested elements whole and in document order' do
      deliver_all(%(<a><b x="1">in</b>tail</a>))
      expect(log.events).to eq([[:start, 'a', {}], [:start, 'b', { 'x' => '1' }], [:text, 'in'], [:end, 'b'],
                                [:text, 'tail'], [:end, 'a']])
    end

    it 'decodes entities in attributes and text' do
      deliver_all(%(<message from="a&amp;b &lt;c&gt;" type="private">x &lt;y&gt; &quot;z&quot;</message>))
      expect(log.events).to eq([[:start, 'message', { 'from' => 'a&b <c>', 'type' => 'private' }],
                                [:text, 'x <y> "z"'], [:end, 'message']])
    end

    it "does not end a tag at a '>' inside a quoted attribute" do
      deliver_all(%(<message type="channel" from="a>b" channel='c>d'>hi</message><ping/>))
      expect(log.events.first).to eq([:start, 'message', { 'type' => 'channel', 'from' => 'a>b', 'channel' => 'c>d' }])
      expect(log.roots).to eq(%w[message ping])
    end

    it 'delivers CDATA as text and skips comments, without raising' do
      expect { deliver_all(%(<message type="server">a<![CDATA[<b>]]><!-- note -->c</message><ping/>)) }.not_to raise_error
      expect(log.events).to eq([[:start, 'message', { 'type' => 'server' }], [:text, 'a'], [:text, '<b>'], [:text, 'c'],
                                [:end, 'message'], [:start, 'ping', {}], [:end, 'ping']])
    end

    it 'skips comments, declarations and stray text between elements' do
      deliver_all(%(junk <!-- c --> <?xml version="1.0"?><!DOCTYPE x>\n<ping/> more junk <notify type="x"/>))
      expect(log.roots).to eq(%w[ping notify])
    end
  end

  describe 'input that is not valid XML' do
    it 'removes control characters rather than dropping the element' do
      deliver_all(%(<message type="private" from="Bob">a\x01b\x1Bc</message>))
      expect(log.events).to include([:text, 'abc'])
    end

    it "escapes a bare '&' or '<' rather than dropping the element" do
      deliver_all(%(<message type="private" from="Bob">fish & chips < 5</message>))
      expect(log.events).to include([:text, 'fish & chips < 5'])
    end

    it 'replaces invalid UTF-8 instead of raising' do
      deliver_all(%(<message type="private" from="Bob">a\xFFb</message>).b)
      expect(log.events).to include([:text, 'a?b'])
    end

    it 'drops an element with mismatched tags and still delivers the next one' do
      deliver_all(%(<a><b></a></b>\n#{ELEMENTS['message']}))
      expect(log.roots).to eq(['message'])
    end

    it 'drops a stray closing tag and still delivers the next element' do
      deliver_all(%(</message>\n<ping/>))
      expect(log.roots).to eq(['ping'])
    end

    it 'throws away an element that never ends once it outgrows the buffer, then recovers' do
      stub_const("#{lnet}::StreamParser::MAX_BUFFER", 256)
      parser.feed(%(<data type="x" from="Bob">))
      parser.feed('A' * 300)
      expect(log.events).to be_empty
      deliver_all(ELEMENTS['ping'])
      expect(log.roots).to eq(['ping'])
    end
  end

  describe 'deep nesting' do
    it 'delivers an element nested 20000 deep without overflowing the stack, then the next one' do
      deep = ('<a>' * 20_000) + ('</a>' * 20_000)
      expect { parser.feed("#{deep}\n<ping/>") }.not_to raise_error
      expect(log.roots).to eq(%w[a ping])
      expect(log.events.count { |kind, _| kind == :start }).to eq(20_001)
    end
  end

  describe 'an element the server never closes' do
    it 'is dropped when the next top-level element starts, so later ones still arrive' do
      deliver_all(%(<message type="channel" from="A" channel="B">unclosed\n), %(<message type="channel" from="C" channel="B">hi</message>\n<ping/>))
      expect(log.roots).to eq(%w[message ping])
      expect(log.events).to include([:text, 'hi'])
    end
  end

  describe "a stray '<'" do
    it 'never swallows the tag after it' do
      deliver_all(%(<AAAA<message type="server">later</message>))
      expect(log.roots).to eq(['message'])
      expect(log.events).to include([:text, 'later'])
    end
  end

  describe 'a long tag that has not ended' do
    it 'is not rescanned on every read' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      parser.feed('<request from="Mallory" type="')
      512.times { parser.feed('A' * 4096) }
      parser.feed('"/><ping/>')
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
      expect(log.roots).to eq(%w[request ping])
    end
  end

  describe 'a listener that raises' do
    it 'loses only the element it was handling' do
      listener = LnetSpec::EventLog.new
      def listener.tag_start(name, attributes)
        raise 'boom' if name == 'ping'

        super
      end
      raising = lnet::StreamParser.new(listener)
      expect { raising.feed(%(<ping/><notify type="x"/>)) }.not_to raise_error
      expect(listener.roots).to eq(['notify'])
    end
  end
end
