# frozen_string_literal: true

require 'rexml/document'
require 'rexml/streamlistener'
require 'ostruct'
require_relative '../spec_helper'

# Spec for 0net.lic's handling of what arrives from the LNet server: <data>
# payloads (Marshal blobs written by the server and by other players'
# clients, including 0net's user callbacks) and chat messages echoed into the
# client and script streams.
#
# 0net.lic connects to the server as soon as it loads, so it can't be
# required. Its top-level classes (SafeXMLParser, WrapperHandler, Callbacks,
# LNet) are extracted verbatim and evaluated inside ZeroNetSpec::Harness,
# where bare references such as Script resolve to the stubs
# below. Incoming XML is fed through the real SafeXMLParser -> LNet listener
# path, as the script's socket loop does.
module ZeroNetSpec
  SOURCE_PATH = find_lic_source('0net.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH)

  def self.extract_class(name)
    body = extract_from_source(SOURCE, /^class #{name}\n.*?^end\n/m, label: "class #{name}", source_path: SOURCE_PATH)
    assert_parses!(body, label: "class #{name}", source_path: SOURCE_PATH)
    body
  end

  OUTPUT = []

  module Harness
    module Script
      def self.new_downstream(line) = OUTPUT << [:downstream, line]
      def self.new_downstream_xml(line) = OUTPUT << [:downstream_xml, line]
    end

    %w[SafeXMLParser WrapperHandler Callbacks LNet].each do |name|
      body = ZeroNetSpec.extract_class(name)
      module_eval(body, SOURCE_PATH, SOURCE[0...SOURCE.index(body)].count("\n") + 1)
    end

    [SafeXMLParser, LNet, LNet.singleton_class].each do |mod|
      mod.class_eval do
        define_method(:echo) { |*args| OUTPUT << [:echo, *args] }
        define_method(:respond) { |*args| OUTPUT << [:respond, *args] }
        define_method(:_respond) { |*args| OUTPUT << [:_respond, *args] }
      end
    end
  end

  class FakeClient
    def puts(line) = OUTPUT << [:client, line]
  end

  # Stand-in for any class with a load hook that happens to be loaded in the
  # Lich process.
  class Gadget
    @loaded = 0
    class << self
      attr_accessor :loaded
    end

    def marshal_dump = 'payload'
    def marshal_load(_) = (Gadget.loaded += 1)
  end

  Pair = Struct.new(:a)

  # non-ASCII test data is built at runtime (Custom/AsciiOnlySource)
  E_ACUTE = [0xe9].pack('U').freeze

  # what 0net's own example callback returns, plus the stock reply shapes
  PLAIN_PAYLOADS = [
    { hard: 3, soft: 0 },
    { 'Race' => 'Elf', 'Strength' => [80, 15], 'Discipline' => [nil, nil], 'Mana' => 412 },
    { '101' => 12.508333333333333, '401' => 250.0 },
    { 'title' => '[Town Square]', 'description' => "the #{E_ACUTE} square", 'pcs' => [{ 'name' => 'Bob', 'status' => nil }] },
    ['GSIV:Bob', 'GSIV:Ann^'],
    { '_format_' => %w[minorspiritual], '_timestamp_' => 1_647_565_036, 'GSIV:Bob' => [25] },
    'You are not currently assigned a task.', nil, false
  ].freeze

  SAFE_CLASSES = [NilClass, TrueClass, FalseClass, Integer, Float, String, Symbol, Array, Hash].freeze

  def self.plain?(obj, depth = 0)
    return false if depth > 64
    return false unless SAFE_CLASSES.include?(obj.class)

    case obj
    when Array then obj.all? { |o| plain?(o, depth + 1) }
    when Hash then plain?(obj.default, depth + 1) && obj.all? { |k, v| plain?(k, depth + 1) && plain?(v, depth + 1) }
    when String, Symbol then obj.instance_variables.empty?
    else true
    end
  end
end

RSpec.describe '0net.lic' do
  let(:lnet) { ZeroNetSpec::Harness::LNet }
  let(:output) { ZeroNetSpec::OUTPUT }

  def feed(xml)
    ZeroNetSpec::OUTPUT.clear
    ZeroNetSpec::Harness::SafeXMLParser.new(lnet.new).parse_chunk(xml)
    ZeroNetSpec::OUTPUT.dup
  end

  def data_element(obj, from: 'Bob', type: 'info')
    %(<data type="#{type}" from="#{from}">#{[Marshal.dump(obj)].pack('m').strip}</data>)
  end

  describe 'LNet.safe_unmarshal' do
    it 'loads every plain reply shape unchanged, including symbol-keyed callback results' do
      ZeroNetSpec::PLAIN_PAYLOADS.each do |payload|
        expect(lnet.safe_unmarshal(Marshal.dump(payload))).to eq(payload)
      end
    end

    it 'follows links to repeated strings, floats, bignums, containers and encodings' do
      arr = ['x', 2.5, 2**80]
      cp = 'cp'.encode('Windows-1252')
      value = [arr, arr, { 'k' => arr }, cp, 'cp2'.encode('Windows-1252'), cp, Hash.new('d'), :sym, :sym]
      blob = Marshal.dump(value)
      loaded = lnet.safe_unmarshal(blob)
      expect(loaded).to eq(value)
      expect(Marshal.dump(loaded)).to eq(Marshal.dump(Marshal.load(blob)))
    end

    [
      ['an object with marshal_load', -> { ZeroNetSpec::Gadget.new }],
      ['a hook object inside a callback-style hash', -> { { hard: [1, { soft: ZeroNetSpec::Gadget.new }] } }],
      ['an OpenStruct', -> { OpenStruct.new(a: 1) }],
      ['a Time', -> { Time.at(0) }],
      ['a Struct', -> { ZeroNetSpec::Pair.new(1) }],
      ['a Class reference', -> { String }],
      ['a Regexp', -> { /x/ }],
      ['a string with another instance variable', -> { (+'x').tap { |s| s.instance_variable_set(:@x, 1) } }],
      ['a self-referencing hash', -> { {}.tap { |h| h['me'] = h } }]
    ].each do |label, build|
      it "refuses #{label} without running any load hook" do
        blob = Marshal.dump(build.call)
        ZeroNetSpec::Gadget.loaded = 0
        expect { lnet.safe_unmarshal(blob) }.to raise_error(ArgumentError)
        expect(ZeroNetSpec::Gadget.loaded).to eq(0)
      end
    end

    it 'raises ArgumentError for every truncation, deep nesting and oversized lengths' do
      blob = Marshal.dump(ZeroNetSpec::PLAIN_PAYLOADS)
      (0...blob.bytesize).each do |len|
        expect { lnet.safe_unmarshal(blob.byteslice(0, len)) }.to raise_error(ArgumentError), "length #{len}"
      end
      expect { lnet.safe_unmarshal("\x04\x08".b + ("[\x06".b * 100_000) + '0') }.to raise_error(ArgumentError, /too deep/)
      expect { lnet.safe_unmarshal("\x04\x08[".b + [4, 0xff, 0xff, 0xff, 0x3f].pack('C*')) }.to raise_error(ArgumentError)
    end

    # Differential check against Ruby's own parser: whatever the validator
    # lets through must come back from Marshal.load as plain values only.
    it 'never lets a mutated payload load a non-plain object' do
      rng = Random.new(20_261_025)
      seeds = ZeroNetSpec::PLAIN_PAYLOADS.map { |v| Marshal.dump(v) } +
              [Marshal.dump([ZeroNetSpec::Gadget.new, OpenStruct.new(a: 1), Time.at(0), ZeroNetSpec::E_ACUTE, 2**70])]
      interesting = 'oUuSCecm/IdMl"[{}:;@if0TF'.bytes + [0, 1, 4, 5, 0xfa, 0xff]
      accepted = 0
      ZeroNetSpec::Gadget.loaded = 0
      20_000.times do
        blob = seeds.sample(random: rng).dup
        rng.rand(1..4).times do
          break if blob.bytesize < 3

          pos = rng.rand(2...blob.bytesize)
          byte = rng.rand < 0.5 ? interesting.sample(random: rng) : rng.rand(256)
          case rng.rand(3)
          when 0 then blob.setbyte(pos, byte)
          when 1 then blob = blob.byteslice(0, pos) + byte.chr + blob.byteslice(pos..)
          else blob = blob.byteslice(0, pos) + blob.byteslice((pos + 1)..)
          end
        end
        begin
          result = lnet.safe_unmarshal(blob)
        rescue StandardError
          next
        end
        accepted += 1
        expect(ZeroNetSpec.plain?(result)).to be(true), "accepted #{blob.inspect} -> #{result.inspect}"
      end
      expect(ZeroNetSpec::Gadget.loaded).to eq(0)
      expect(accepted).to be > 100
    end
  end

  describe '<data> from the server' do
    it 'never runs a load hook from an unsolicited payload, and says it ignored it' do
      ZeroNetSpec::Gadget.loaded = 0
      out = feed(data_element({ 'k' => ZeroNetSpec::Gadget.new }))
      expect(ZeroNetSpec::Gadget.loaded).to eq(0)
      expect(out.size).to eq(1)
      expect(out.first[0]).to eq(:echo)
      expect(out.first[1]).to start_with('ignored info data from Bob that contained something other than plain values')
    end

    it 'hands a plain callback reply to the waiting request' do
      waiter = { 'type' => 'roundtime', 'name' => 'Bob', 'data' => :waiting }
      lnet.class_variable_get(:@@waiting).push(waiter)
      feed(data_element({ hard: 3, soft: 0 }, type: 'roundtime'))
      expect(waiter['data']).to eq({ hard: 3, soft: 0 })
    ensure
      lnet.class_variable_get(:@@waiting).delete(waiter)
    end

    it 'fails only the matching waiting request when the reply is refused' do
      waiter = { 'type' => 'info', 'name' => 'Bob', 'data' => :waiting }
      other = { 'type' => 'skills', 'name' => 'Bob', 'data' => :waiting }
      lnet.class_variable_get(:@@waiting).push(waiter, other)
      out = feed(data_element([ZeroNetSpec::Gadget.new]))
      expect(waiter['data']).to be(false)
      expect(other['data']).to eq(:waiting)
      expect(out.map(&:first)).to eq([:echo])
    ensure
      lnet.class_variable_get(:@@waiting).delete(waiter)
      lnet.class_variable_get(:@@waiting).delete(other)
    end

    # drives the real LNet.get_data against a stub server, so this covers the
    # request -> refused reply -> return path rather than the waiter alone
    it 'returns false from get_data without waiting out the 8 second timeout' do
      server = Class.new do
        attr_reader :sent

        def initialize = @sent = Queue.new
        def closed? = false
        def puts(xml) = @sent << xml.to_s
      end.new
      saved = lnet.server
      lnet.server = server
      requester = Thread.new { lnet.get_data(+'bob', 'info') } # get_data capitalizes its argument in place
      expect(server.sent.pop(timeout: 2)).to match(/<request (?=.*type=.info.)(?=.*to=.Bob.)/)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      feed(data_element(Time.at(0)))
      expect(requester.join(3)&.value).to be(false)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    ensure
      requester&.kill
      lnet.server = saved
    end

    it 'still renders the server connected list' do
      out = feed(data_element(['GSIV:Bob', 'GSIV:Ann'], from: 'server', type: 'connected'))
      expect(out.last[0]).to eq(:respond)
      expect(out.last[1]).to include('GSIV (2):', 'Bob', 'Ann', 'Total connected: 2')
    end
  end

  describe 'chat echo' do
    around do |example|
      saved = [$frontend, $_CLIENT_, $_SERVERBUFFER_]
      $_CLIENT_ = ZeroNetSpec::FakeClient.new
      $_SERVERBUFFER_ = []
      lnet.options = { 'ignore' => [], 'permission' => {}, 'timestamps' => false, 'fam_window' => false }
      example.run
    ensure
      $frontend, $_CLIENT_, $_SERVERBUFFER_ = saved
    end

    def xml_outputs(out)
      out.select { |kind, _| %i[_respond downstream_xml].include?(kind) }.map(&:last) + $_SERVERBUFFER_
    end

    def expect_one_thought_element(xml)
      doc = REXML::Document.new("<r>#{xml}</r>")
      expect(doc.root.elements.map(&:name)).to eq(%w[pushStream popStream])
      doc
    end

    context 'on an XML front end' do
      before { $frontend = 'stormfront' }

      it 'renders ordinary chat exactly as before' do
        out = feed(%(<message type="channel" from="GSIV:Bob" channel="General">hi &amp; bye</message>))
        expect(out).to eq([
                            [:_respond, %(<pushStream id="thoughts"/>[General]-GSIV:Bob: "hi &amp; bye"\n<popStream/>\n)],
                            [:downstream_xml, %(<pushStream id="thoughts"/>[General]-GSIV:Bob: "hi &amp; bye"\n<popStream/>\n)],
                            [:downstream, %([General]-GSIV:Bob: "hi & bye")]
                          ])
      end

      it 'escapes markup in the sender and channel names' do
        out = feed(%(<message type="channel" from="Bob&lt;/pushStream&gt;&lt;prompt time=&quot;1&quot;&gt;&amp;gt;&lt;/prompt&gt;" channel="Gen&lt;b&gt;">hi</message>))
        xml_outputs(out).each do |xml|
          expect(expect_one_thought_element(xml).root.text).to include('[Gen<b>]-Bob</pushStream><prompt time="1">&gt;</prompt>: "hi"')
        end
        expect(out.last).to eq([:downstream, %([Gen<b>]-Bob</pushStream><prompt time="1">&gt;</prompt>: "hi")])
      end

      it 'escapes the sender in the familiar window' do
        lnet.options['fam_window'] = true
        out = feed(%(<message type="private" from="&lt;x/&gt;">hi</message>))
        expect(out.first[1]).to eq(%(<pushStream id="familiar" ifClosedStyle="watching"/>[Private]-&lt;x/&gt;: "hi"\n<popStream/>\n))
      end

      it 'folds line breaks in player messages but keeps them in server messages' do
        out = feed(%(<message type="private" from="Bob">hi&#13;&#10;You feel fully rested.</message>))
        expect(out.last).to eq([:downstream, %([Private]-Bob: "hi You feel fully rested.")])
        out = feed(%(<message type="server">line one&#10;line two</message>))
        expect(out.last).to eq([:downstream, %([server]: "line one\nline two")])
      end

      it 'still honours ignore by the raw sender name' do
        lnet.options['ignore'] = ['Bob']
        out = feed(%(<message type="private" from="Bob">hi</message>))
        expect(out.map(&:first)).to eq(%i[downstream_xml downstream])
      end
    end

    context 'on Wizard or Avalon' do
      before { $frontend = 'wizard' }

      it 'sends each line to scripts once' do
        out = feed(%(<message type="private" from="Bob">hi</message>))
        expect(out.count { |kind, _| kind == :downstream }).to eq(1)
        expect(out.first).to eq([:client, %(You hear the faint thoughts of [Private]-Bob echo in your mind:\n"hi"\r\n)])
      end

      # older REXML versions pass control characters through, so this calls
      # echo_thought directly rather than relying on the parser to drop them
      it 'strips control codes from the sender, channel and message' do
        ZeroNetSpec::OUTPUT.clear
        lnet.echo_thought("Bob\x1CGSo", "a\x1CGSe\x1B[2Jb\x00", "Gen\x07")
        client = output.find { |kind, _| kind == :client }[1]
        expect(client).to eq(%(You hear the faint thoughts of [Gen]-BobGSo echo in your mind:\n"aGSe[2Jb"\r\n))
      end
    end
  end
end
