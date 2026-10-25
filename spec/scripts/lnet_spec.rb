# frozen_string_literal: true

require 'rexml/document'
require 'rexml/streamlistener'
require 'ostruct'
require_relative '../spec_helper'

# Spec for lnet.lic's handling of what arrives from the LNet server: <data>
# payloads (Marshal blobs written by the server and by other players'
# clients) and chat messages echoed into the client and script streams.
#
# lnet.lic connects to the server as soon as it loads, so it can't be
# required. Its three top-level classes (SafeXMLParser, WrapperHandler, LNet)
# are extracted verbatim and evaluated inside LnetSpec::Harness, where bare
# references such as Script resolve to the stubs below. Incoming XML is fed
# through the real SafeXMLParser -> LNet listener path, as the script's
# socket loop does.
module LnetSpec
  SOURCE_PATH = find_lic_source('lnet.lic', from: __dir__)
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

    %w[SafeXMLParser WrapperHandler LNet].each do |name|
      body = LnetSpec.extract_class(name)
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

  # non-ASCII test data is built at runtime (Custom/AsciiOnlySource)
  E_ACUTE = [0xe9].pack('U').freeze

  def self.bytes(*list) = list.pack('C*')

  Pair = Struct.new(:a)
  module Mixin; end

  # every shape lnet.lic itself sends, plus what the server sends back
  REAL_PAYLOADS = {
    'info'         => { 'Race' => 'Elf', 'Profession' => 'Wizard', 'Age' => 33, 'Expr' => '1234567', 'Level' => 100,
                'Strength' => [80, 15], 'Discipline' => [nil, nil], 'Mana' => 412 },
    'spells'       => { '101' => 12.508333333333333, '401' => 250.0, '1035' => 0.5 },
    'skills'       => { 'Two Weapon Combat' => 201, 'Minor Elemental' => 102 },
    'locate'       => { 'title' => '[Wehnimer\'s Landing, Town Square]', 'description' => "This is the #{E_ACUTE} square.",
                  'exits' => 'Obvious paths: north, south', 'loot' => ['a sword'],
                  'pcs' => [{ 'name' => 'Bob', 'status' => nil }, { 'name' => 'Ann', 'status' => 'lying down' }],
                  'npcs' => [] },
    'health'       => { 'injuries' => { 'head' => { 'scar' => 0, 'wound' => 1 } }, 'health' => 100, 'max_health' => 120 },
    'bounty'       => 'You are not currently assigned a task.',
    'connected'    => ['GSIV:Bob', 'GSIV:Ann^', 'DR:Cid*', 'loner'],
    'channels'     => [{ 'name' => 'General', 'tuned' => 1234, 'status' => 'default', 'description' => 'chat' }],
    'server stats' => { 'uptime' => 864_000, 'character connections' => [[86_400, 1500]],
                        'own_channels' => { 'Mine' => { 'moderators' => [], 'invited' => nil,
                                                        'banned' => [['Eve', nil], ['Mal', 3600]], 'gagged' => [] } },
                        'mod_channels' => {} },
    'spell-ranks'  => { '_format_' => %w[minorspiritual majorspiritual], '_timestamp_' => 1_647_565_036,
                       'GSIV:Bob' => [25, 3] },
    'declined'     => nil,
    'no such user' => false
  }.freeze

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

RSpec.describe 'lnet.lic' do
  let(:lnet) { LnetSpec::Harness::LNet }
  let(:output) { LnetSpec::OUTPUT }

  def feed(xml)
    LnetSpec::OUTPUT.clear
    LnetSpec::Harness::SafeXMLParser.new(lnet.new).parse_chunk(xml)
    LnetSpec::OUTPUT.dup
  end

  def data_element(obj, from: 'Bob', type: 'info')
    %(<data type="#{type}" from="#{from}">#{[Marshal.dump(obj)].pack('m').strip}</data>)
  end

  describe 'LNet.safe_unmarshal' do
    LnetSpec::REAL_PAYLOADS.each do |type, payload|
      it "loads the #{type} payload unchanged" do
        expect(lnet.safe_unmarshal(Marshal.dump(payload))).to eq(payload)
      end
    end

    it 'loads edge-case plain values: encodings, bignums, links, hash defaults' do
      shared = 'shared'
      value = [
        'binary'.b, 'cp1252'.encode('Windows-1252'), :"sym#{LnetSpec::E_ACUTE}", :plain, :plain,
        -1, -123, -256, -65_536, 2**30, -(2**30) - 1, 2**64, -(2**100),
        1.5, -0.0, Float::INFINITY, shared, shared, Hash.new(7).merge('a' => 1), [[], {}]
      ]
      loaded = lnet.safe_unmarshal(Marshal.dump(value))
      expect(loaded).to eq(value)
      expect(loaded[1].encoding).to eq(Encoding::Windows_1252)
      expect(loaded[16]).to be(loaded[17])
      expect(loaded[18].default).to eq(7)
      expect(lnet.safe_unmarshal(Marshal.dump(Float::NAN)).nan?).to be(true)
    end

    # links are numbered by Marshal in the order objects start; a validator
    # that numbered them differently would refuse these legitimate repeats
    it 'follows links to every kind of repeated object' do
      big = 2**80
      float = 1.0 / 3
      str = LnetSpec::E_ACUTE.dup
      arr = ['x', 2.5, big]
      hash = { 'k' => arr }
      nested = [Hash.new('d'), str, float, big, arr, hash, 'binary'.b.then { |b| [b, b] }]
      value = [nested, str, float, big, arr, hash, nested[0], nested[6], 'Windows'.encode('Windows-1252').then { |s| [s, s] }]
      loaded = lnet.safe_unmarshal(Marshal.dump(value))
      expect(loaded).to eq(value)
      expect(loaded[4]).to be(loaded[0][4])
      expect(loaded[5]['k']).to be(loaded[4])
    end

    it 'loads randomly built plain values with shared references' do
      rng = Random.new(4_242)
      pool = []
      leaf = lambda do
        case rng.rand(9)
        when 0 then nil
        when 1 then rng.rand < 0.5
        when 2 then rng.rand(-(2**70)..(2**70)) >> rng.rand(70)
        when 3 then rng.rand * 1000
        when 4 then ['ascii', LnetSpec::E_ACUTE, 'bin'.b, 'cp'.encode('Windows-1252'), 'sj'.encode('Shift_JIS')].sample(random: rng).dup
        when 5 then [:a, :b, LnetSpec::E_ACUTE.to_sym, :plain].sample(random: rng)
        else pool.empty? ? 'x' : pool.sample(random: rng) # repeat an earlier object -> '@' link
        end
      end
      build = lambda do |depth|
        value = case depth > 3 ? 0 : rng.rand(3)
                when 0 then leaf.call
                when 1 then Array.new(rng.rand(4)) { build.call(depth + 1) }
                else (rng.rand < 0.2 ? Hash.new(leaf.call) : {}).tap { |h| rng.rand(4).times { h[leaf.call] = build.call(depth + 1) } }
                end
        pool << value unless value.is_a?(Symbol) || value.nil? || value == true || value == false || value.is_a?(Integer)
        value
      end
      2_000.times do
        pool.clear
        value = build.call(0)
        blob = Marshal.dump(value)
        loaded = lnet.safe_unmarshal(blob)
        expect(loaded).to eq(value)
        # Ruby copies string hash keys on insert, so compare identity (links)
        # against a plain Marshal.load of the same bytes, not the original
        expect(Marshal.dump(loaded)).to eq(Marshal.dump(Marshal.load(blob)))
      end
    end

    it 'refuses unknown encodings and other string instance variables' do
      [
        "\x04\x08I\"\x06x\x06:\x0Dencoding\"\x0CNoSuchEnc".b,
        "\x04\x08I\"\x06x\x06:\x06Ei\x06".b,
        Marshal.dump('x'.dup.tap { |s| s.instance_variable_set(:@x, 1) }),
        Marshal.dump(LnetSpec::E_ACUTE.dup.tap { |s| s.instance_variable_set(:@x, 'y') })
      ].each do |blob|
        expect { lnet.safe_unmarshal(blob) }.to raise_error(ArgumentError)
      end
    end

    it 'refuses self-referencing arrays and hashes' do
      arr = []
      arr << [arr]
      hash = {}
      hash['me'] = hash
      by_key = {}
      by_key[[by_key]] = 1
      by_default = Hash.new
      by_default.default = by_default
      [arr, hash, by_key, by_default, [1, { 'a' => [hash] }]].each do |cyclic|
        expect { lnet.safe_unmarshal(Marshal.dump(cyclic)) }.to raise_error(ArgumentError, /circular/)
      end
    end

    describe 'refuses anything that is not a plain value' do
      [
        ['an object with marshal_load', -> { LnetSpec::Gadget.new }],
        ['a hook object nested in a hash value', -> { { 'k' => [1, { 'deep' => LnetSpec::Gadget.new }] } }],
        ['a hook object as a hash default', -> { Hash.new(LnetSpec::Gadget.new) }],
        ['a hook object as a string ivar value', -> { 'x'.dup.tap { |s| s.instance_variable_set(:@e, LnetSpec::Gadget.new) } }],
        ['an ordinary object', -> { OpenStruct.new(a: 1) }],
        ['a _dump/_load object', -> { Time.at(0) }],
        ['a Struct', -> { LnetSpec::Pair.new(1) }],
        ['a Class reference', -> { String }],
        ['a Module reference', -> { Kernel }],
        ['a Hash subclass', -> { Class.new(Hash).tap { |c| LnetSpec.const_set(:SubHash, c) }.new }],
        ['an extended object', -> { 'x'.dup.extend(LnetSpec::Mixin) }],
        ['a Regexp', -> { /x/ }],
        ['a Range', -> { (1..2) }],
        ['a Set', -> { Set[1] }],
        ['an Array with ivars', -> { [1].tap { |a| a.instance_variable_set(:@x, 1) } }]
      ].each do |label, build|
        it "refuses #{label} without running its load hook" do
          blob = Marshal.dump(build.call)
          LnetSpec::Gadget.loaded = 0
          expect { lnet.safe_unmarshal(blob) }.to raise_error(ArgumentError)
          expect(LnetSpec::Gadget.loaded).to eq(0)
        end
      end
    end

    it 'raises ArgumentError for a truncation at every byte' do
      blob = Marshal.dump(LnetSpec::REAL_PAYLOADS['server stats'])
      (0...blob.bytesize).each do |len|
        expect { lnet.safe_unmarshal(blob.byteslice(0, len)) }.to raise_error(ArgumentError), "length #{len}"
      end
    end

    it 'rejects a wrong version header and trailing bytes' do
      expect { lnet.safe_unmarshal("\x04\x07[\x00".b) }.to raise_error(ArgumentError)
      expect { lnet.safe_unmarshal(Marshal.dump(1) + 'x') }.to raise_error(ArgumentError)
    end

    it 'rejects deep nesting with ArgumentError, not SystemStackError' do
      blob = "\x04\x08".b + ("[\x06".b * 100_000) + '0'
      expect { lnet.safe_unmarshal(blob) }.to raise_error(ArgumentError, /too deep/)
    end

    it 'rejects lengths larger than the payload before allocating anything' do
      huge = LnetSpec.bytes(4, 0xff, 0xff, 0xff, 0x3f) # 2**30 - 1
      ["\x04\x08[".b + huge, "\x04\x08{".b + huge, "\x04\x08\"".b + huge, "\x04\x08l+".b + huge,
       "\x04\x08[".b + LnetSpec.bytes(0xfa)].each do |blob|
        expect { lnet.safe_unmarshal(blob) }.to raise_error(ArgumentError)
      end
    end

    # Differential check against Ruby's own parser: whatever the validator
    # lets through must come back from Marshal.load as nothing but plain
    # values, and nothing it rejects may escape as a non-StandardError.
    it 'never lets a mutated payload load a non-plain object' do
      rng = Random.new(20_261_025)
      seeds = LnetSpec::REAL_PAYLOADS.values.map { |v| Marshal.dump(v) } +
              [Marshal.dump([LnetSpec::Gadget.new, OpenStruct.new(a: 1), Time.at(0), /x/, LnetSpec::E_ACUTE, LnetSpec::E_ACUTE.to_sym, 2**70])]
      interesting = 'oUuSCecm/IdMl"[{}:;@if0TF'.bytes + [0, 1, 4, 5, 0xfa, 0xff]
      accepted = 0
      LnetSpec::Gadget.loaded = 0
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
        expect(LnetSpec.plain?(result)).to be(true), "accepted #{blob.inspect} -> #{result.inspect}"
      end
      expect(LnetSpec::Gadget.loaded).to eq(0)
      expect(accepted).to be > 100 # the mutations didn't just break every blob
    end
  end

  describe '<data> from the server' do
    it 'never runs a load hook from an unsolicited payload, and says it ignored it' do
      LnetSpec::Gadget.loaded = 0
      out = feed(data_element({ 'k' => LnetSpec::Gadget.new }))
      expect(LnetSpec::Gadget.loaded).to eq(0)
      expect(out.size).to eq(1)
      expect(out.first[0]).to eq(:echo)
      expect(out.first[1]).to start_with('ignored info data from Bob that contained something other than plain values')
    end

    it 'hands a plain reply to the waiting request' do
      waiter = { 'type' => 'info', 'name' => 'Bob', 'data' => :waiting }
      lnet.class_variable_get(:@@waiting).push(waiter)
      feed(data_element(LnetSpec::REAL_PAYLOADS['info']))
      expect(waiter['data']).to eq(LnetSpec::REAL_PAYLOADS['info'])
    ensure
      lnet.class_variable_get(:@@waiting).delete(waiter)
    end

    it 'fails the waiting request at once when the reply is refused' do
      waiter = { 'type' => 'info', 'name' => 'Bob', 'data' => :waiting }
      other = { 'type' => 'skills', 'name' => 'Bob', 'data' => :waiting }
      lnet.class_variable_get(:@@waiting).push(waiter, other)
      out = feed(data_element([LnetSpec::Gadget.new]))
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
      feed(data_element(LnetSpec::Gadget.new))
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
      $_CLIENT_ = LnetSpec::FakeClient.new
      $_SERVERBUFFER_ = []
      lnet.options = { 'ignore' => [], 'permission' => {}, 'timestamps' => false }
      lnet.alias = {}
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

      it 'escapes markup in the sender name' do
        out = feed(%(<message type="channel" from="Bob&lt;/preset&gt;&lt;popStream/&gt;&lt;prompt time=&quot;1&quot;&gt;&amp;gt;&lt;/prompt&gt;" channel="General">hi</message>))
        xml_outputs(out).each do |xml|
          doc = expect_one_thought_element(xml)
          expect(doc.root.text).to include('Bob</preset><popStream/><prompt time="1">&gt;</prompt>')
        end
        expect(out.last).to eq([:downstream, %([General]-Bob</preset><popStream/><prompt time="1">&gt;</prompt>: "hi")])
      end

      it 'escapes markup in the channel name and in a local alias' do
        lnet.alias['GSIV:Bob'] = 'Bob & <b>'
        out = feed(%(<message type="channel" from="GSIV:Bob" channel="Gen&lt;pushBold/&gt;">hi</message>))
        xml_outputs(out).each do |xml|
          expect(expect_one_thought_element(xml).root.text).to include('[Gen<pushBold/>]-Bob & <b>: "hi"')
        end
      end

      it 'escapes the sender inside a preset and in the familiar window' do
        lnet.options['preset'] = 'thought'
        out = feed(%(<message type="private" from="&lt;x/&gt;">hi</message>))
        expect(out.first[1]).to eq(%(<pushStream id="thoughts"/><preset id='thought'>[Private]-&lt;x/&gt;:</preset> "hi"\n<popStream/>\n))
        lnet.options['fam_window'] = true
        out = feed(%(<message type="private" from="&lt;x/&gt;">hi</message>))
        expect(out.first[1]).to eq(%(<pushStream id="familiar" ifClosedStyle="watching"/>[Private]-&lt;x/&gt;: "hi"\n<popStream/>\n))
      end

      it 'folds line breaks so a message cannot print its own line' do
        out = feed(%(<message type="private" from="Bob">hi&#13;&#10;You feel fully rested.&#10;x</message>))
        expect(out.last).to eq([:downstream, %([Private]-Bob: "hi You feel fully rested. x")])
        xml_outputs(out).each { |xml| expect(xml.count("\n")).to eq(2) }
      end

      it 'keeps line breaks in server messages' do
        out = feed(%(<message type="server">line one&#10;line two</message>))
        expect(out.last).to eq([:downstream, %([server]: "line one\nline two")])
      end
    end

    context 'on Wizard or Avalon' do
      before { $frontend = 'wizard' }

      it 'sends each line to scripts once' do
        out = feed(%(<message type="private" from="Bob">hi</message>))
        expect(out.count { |kind, _| kind == :downstream }).to eq(1)
        expect(out.first).to eq([:client, %(You hear the faint thoughts of [Private]-Bob echo in your mind:\r\n"hi"\r\n)])
      end

      # older REXML versions pass control characters through, so this calls
      # echo_thought directly rather than relying on the parser to drop them
      it 'strips control codes from the sender, channel and message' do
        LnetSpec::OUTPUT.clear
        lnet.echo_thought("Bob\x1CGSo", "a\x1CGSe\x1B[2Jb\x00", "Gen\x07")
        client = output.find { |kind, _| kind == :client }[1]
        expect(client).to eq(%(You hear the faint thoughts of [Gen]-BobGSo echo in your mind:\r\n"aGSe[2Jb"\r\n))
        lnet.options['fam_window'] = true
        LnetSpec::OUTPUT.clear
        lnet.echo_thought("Bob\x1CGSo", "a\x1Cb", 'Private')
        expect(output.first[1]).to eq(%(\034GSe\r\n[Private]-BobGSo: "ab"\r\n\034GSf\r\n))
      end
    end
  end
end
