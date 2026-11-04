# frozen_string_literal: true

require_relative 'support/harness'

RSpec.describe 'lnet.lic' do
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

  describe 'payloads that would expand' do
    def doubled(levels)
      value = ['x']
      levels.times { value = [value, value] } # each level links to the one before
      value
    end

    it 'refuses shared links that would expand a tiny payload into a huge tree, quickly' do
      blob = Marshal.dump([doubled(30), 1]) # 2**30 leaves through shared links
      expect(blob.bytesize).to be < 200
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { lnet.safe_unmarshal(blob) }.to raise_error(ArgumentError, /expands too far/)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    end

    it 'still loads a little sharing' do
      expect(lnet.safe_unmarshal(Marshal.dump(doubled(5)))).to eq(doubled(5))
    end

    it 'refuses a number longer than 256 bits' do
      expect(lnet.safe_unmarshal(Marshal.dump(2**255))).to eq(2**255)
      expect { lnet.safe_unmarshal(Marshal.dump(2**300)) }.to raise_error(ArgumentError, /bignum too long/)
    end

    it 'raises ArgumentError for a symbol in a bad encoding' do
      expect { lnet.safe_unmarshal("\x04\bI:\x06\xFF\x06:\x06ET".b) }.to raise_error(ArgumentError)
    end
  end

  describe 'LNet::SafeMarshal.encode and .decode' do
    LnetSpec::REAL_PAYLOADS.each do |type, payload|
      it "round-trips the #{type} payload through the text of a <data> element" do
        text = lnet::SafeMarshal.encode(payload)
        expect(text).not_to end_with("\n")
        expect(lnet::SafeMarshal.decode(text)).to eq(payload)
      end
    end

    it 'decodes text wrapped across lines, as base64 arrives in a <data> element' do
      text = [Marshal.dump(LnetSpec::REAL_PAYLOADS['locate'])].pack('m')
      expect(text.count("\n")).to be > 1
      expect(lnet::SafeMarshal.decode(text)).to eq(LnetSpec::REAL_PAYLOADS['locate'])
    end

    [['empty text', ''], ['nil', nil], ['text that is not base64', '!!!***'], ['base64 of junk', ['junk'].pack('m')]].each do |label, text|
      it "raises ArgumentError, not anything else, for #{label}" do
        expect { lnet::SafeMarshal.decode(text) }.to raise_error(ArgumentError)
      end
    end

    it 'refuses a hook object without running its load hook' do
      LnetSpec::Gadget.loaded = 0
      expect { lnet::SafeMarshal.decode(lnet::SafeMarshal.encode(LnetSpec::Gadget.new)) }.to raise_error(ArgumentError)
      expect(LnetSpec::Gadget.loaded).to eq(0)
    end
  end
end
