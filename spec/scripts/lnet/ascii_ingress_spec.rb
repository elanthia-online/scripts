# frozen_string_literal: true

require_relative 'support/harness'

# Everything another LNet client sends reaches lnet, the game client and other
# scripts as plain ASCII in UTF-8, whatever encoding or characters the sender
# picked. Ruby 3.3.13, 3.4.12 and 4.0.9 and earlier can overflow a heap
# buffer when changing the case of an ISO-8859-x or Windows-125x string
# holding a sharp s (GHSA-34m4-m9fh-gqp5), and misread memory matching
# case-insensitively text whose folds change length (GHSA-wpqw-5qxg-m68r,
# GHSA-pvgc-g7gj-pv6h); none of those inputs can get past LNet.ascii.
module LnetSpec
  SHARP_S = "\xDF".b.freeze
  # the encodings whose sharp s case mapping overflowed (ruby c48b962434)
  SHARP_S_ENCODINGS = %w[ISO-8859-1 ISO-8859-2 ISO-8859-3 ISO-8859-4 ISO-8859-9 ISO-8859-10 ISO-8859-13 ISO-8859-14
                         ISO-8859-15 ISO-8859-16 Windows-1250 Windows-1252 Windows-1254 Windows-1257].freeze

  # @return [Boolean] whether every string and symbol in value is ASCII, and
  #   every string UTF-8
  def self.ascii_tree?(value)
    case value
    when String then value.encoding == Encoding::UTF_8 && value.ascii_only?
    when Symbol then value.to_s.ascii_only?
    when Array then value.all? { |item| ascii_tree?(item) }
    when Hash then ascii_tree?(value.default) && value.all? { |key, item| ascii_tree?(key) && ascii_tree?(item) }
    else true
    end
  end
end

RSpec.describe 'lnet.lic ASCII-only input' do
  describe 'LNet.ascii' do
    it 'returns ASCII text unchanged, as a new UTF-8 string, whatever it was tagged' do
      %w[US-ASCII UTF-8 ASCII-8BIT Windows-1252 ISO-8859-1 Shift_JIS].each do |name|
        text = 'plain text'.encode(name).freeze
        out = lnet.ascii(text)
        expect(out).to eq('plain text')
        expect(out.encoding).to eq(Encoding::UTF_8)
        expect(out).not_to be_frozen
        expect(out).not_to equal(text)
      end
    end

    it 'turns each non-ASCII character of a valid string into one ?' do
      expect(lnet.ascii("caf#{LnetSpec::E_ACUTE}")).to eq('caf?')
      expect(lnet.ascii("Stra#{LnetSpec::SHARP_S}e".dup.force_encoding('ISO-8859-1'))).to eq('Stra?e')
      expect(lnet.ascii([0x3042, 0x41].pack('U*').encode('Shift_JIS'))).to eq('?A')
      expect(lnet.ascii([0x1E98].pack('U'))).to eq('?')
    end

    it 'turns each non-ASCII byte of an invalid or ASCII-incompatible string into ?, keeping the rest ASCII' do
      expect(lnet.ascii("ok\xFF\xFE".dup.force_encoding('UTF-8'))).to eq('ok??')
      wide = lnet.ascii("w#{[0x1E98].pack('U')}".encode('UTF-16LE'))
      expect(wide.encoding).to eq(Encoding::UTF_8)
      expect(wide).to be_ascii_only
      expect(lnet.ascii("ab\x92\xA4".b.force_encoding('Emacs-Mule'))).to be_ascii_only
      expect(lnet.ascii("\xFF\xFE".b.force_encoding('UTF-16'))).to eq('??')
    end

    it 'never modifies its argument' do
      text = "caf#{LnetSpec::E_ACUTE}"
      lnet.ascii(text)
      expect(text).to eq("caf#{LnetSpec::E_ACUTE}")
      expect(text.encoding).to eq(Encoding::UTF_8)
    end

    it 'gives ASCII UTF-8 for random bytes in every encoding Ruby knows' do
      rng = Random.new(1_927)
      Encoding.list.each do |encoding|
        20.times do
          raw = Array.new(rng.rand(0..24)) { rng.rand(256) }.pack('C*').force_encoding(encoding)
          out = lnet.ascii(raw)
          expect(out.encoding).to eq(Encoding::UTF_8)
          expect(out).to be_ascii_only, "#{encoding}: #{raw.dump} gave #{out.dump}"
        end
      end
    end
  end

  describe 'XML from the server' do
    let(:log) { LnetSpec::EventLog.new }

    def events(xml)
      lnet::StreamParser.new(log).feed(xml)
      log.events
    end

    def strings(events)
      events.flat_map { |event| event.drop(1).flat_map { |part| part.is_a?(Hash) ? part.to_a.flatten : [part] } }
    end

    it 'reduces characters written as references, which REXML decodes after the bytes are checked' do
      out = events(%(<message type="channel" from="Stra&#223;e" channel="&#x1E98;">x &#223;&#x130; y</message>))
      expect(out).to eq([[:start, 'message', { 'type' => 'channel', 'from' => 'Stra?e', 'channel' => '?' }],
                         [:text, 'x ?? y'], [:end, 'message']])
    end

    it 'reduces raw non-ASCII and invalid bytes in values and text' do
      xml = %(<message type="channel" from="caf#{LnetSpec::E_ACUTE}" channel="X">a\xDF\xFFb</message>).b
      expect(events(xml)).to eq([[:start, 'message', { 'type' => 'channel', 'from' => 'caf?', 'channel' => 'X' }],
                                 [:text, 'a??b'], [:end, 'message']])
    end

    it 'reduces non-ASCII element and attribute names' do
      out = events(%(<m#{LnetSpec::E_ACUTE} a#{LnetSpec::E_ACUTE}="1">t</m#{LnetSpec::E_ACUTE}>))
      expect(out).to eq([[:start, 'm?', { 'a?' => '1' }], [:text, 't'], [:end, 'm?']])
    end

    it 'reduces CDATA' do
      expect(events(%(<message type="x"><![CDATA[#{LnetSpec::E_ACUTE}<b>]]></message>))).to include([:text, '?<b>'])
    end

    it 'hands on nothing but ASCII UTF-8 for random bytes and references' do
      rng = Random.new(2_026)
      junk = lambda do
        Array.new(rng.rand(0..12)) do
          case rng.rand(3)
          when 0 then [rng.rand(0x80..0xFF)].pack('C')
          when 1 then "&##{[rng.rand(0x80..0xD7FF), rng.rand(0xE000..0x10FFFF)].sample(random: rng)};"
          else ('a'..'z').to_a.sample(random: rng)
          end
        end.join.b
      end
      300.times do
        log.events.clear
        xml = %(<message type="channel" from="#{junk.call}" channel="X">#{junk.call}</message>).b
        out = events(xml)
        expect(out).not_to be_empty
        strings(out).each do |text|
          expect(text.encoding).to eq(Encoding::UTF_8)
          expect(text).to be_ascii_only, "#{xml.dump} gave #{text.dump}"
        end
      end
    end

    it 'shows another player chat in ASCII' do
      out = feed(%(<message type="channel" from="GSIV:Bob" channel="General">Stra&#223;e caf#{LnetSpec::E_ACUTE}</message>))
      shown = out.map { |_kind, text| text.to_s }.join
      expect(shown).to include('Stra?e caf?')
      expect(shown).to be_ascii_only
    end
  end

  describe '<data> payloads' do
    def decode(obj) = lnet::SafeMarshal.decode(lnet::SafeMarshal.encode(obj))

    LnetSpec::SHARP_S_ENCODINGS.each do |name|
      it "reduces a #{name} string holding a sharp s, so it never reaches case conversion" do
        out = decode({ 'description' => "Stra#{LnetSpec::SHARP_S}e".dup.force_encoding(name) })
        expect(out).to eq({ 'description' => 'Stra?e' })
        expect(out['description'].encoding).to eq(Encoding::UTF_8)
        expect(out['description'].upcase).to eq('STRA?E')
      end
    end

    it 'keeps ASCII text whatever encoding it was tagged, now as UTF-8' do
      out = decode(['cp'.encode('Windows-1252'), 'bin'.b, 'sj'.encode('Shift_JIS'), 'us'.encode('US-ASCII')])
      expect(out).to eq(%w[cp bin sj us])
      expect(out.map(&:encoding).uniq).to eq([Encoding::UTF_8])
    end

    it 'reduces symbols, hash keys and hash defaults' do
      e = LnetSpec::E_ACUTE
      out = decode([:"sym#{e}", Hash.new("d#{e}").merge("k#{e}" => "v#{e}")])
      expect(out[0]).to eq(:sym?)
      expect(out[1]).to eq({ 'k?' => 'v?' })
      expect(out[1].default).to eq('d?')
    end

    it 'reduces wide and odd encodings to ASCII' do
      wide = "w#{[0x1E98].pack('U')}"
      out = decode([wide.encode('UTF-16LE'), wide.encode('UTF-32BE'), "ab\x92\xA4".b.force_encoding('Emacs-Mule')])
      expect(LnetSpec.ascii_tree?(out)).to be(true)
    end

    it 'leaves numbers, nil and booleans alone' do
      value = [nil, true, false, 1, -(2**70), 1.5, { 1 => [2.5] }]
      expect(decode(value)).to eq(value)
    end

    it 'keeps safe_unmarshal, which only checks a payload, returning it as sent' do
      text = "Stra#{LnetSpec::SHARP_S}e".dup.force_encoding('ISO-8859-1')
      expect(lnet.safe_unmarshal(Marshal.dump(text)).encoding).to eq(Encoding::ISO_8859_1)
    end

    it 'gives ASCII for random payloads in random encodings' do
      rng = Random.new(77)
      encodings = Encoding.list.reject(&:dummy?)
      leaf = lambda do
        raw = Array.new(rng.rand(0..10)) { rng.rand(256) }.pack('C*')
        case rng.rand(4)
        when 0 then raw.force_encoding(encodings.sample(random: rng))
        when 1 then raw.force_encoding('ISO-8859-1').to_sym
        when 2 then rng.rand(-1000..1000)
        else "a#{LnetSpec::E_ACUTE}".encode(%w[UTF-8 UTF-16LE ISO-8859-1].sample(random: rng))
        end
      end
      build = ->(depth) { depth > 2 || rng.rand(3).zero? ? leaf.call : Array.new(rng.rand(4)) { rng.rand(2).zero? ? build.call(depth + 1) : { leaf.call => build.call(depth + 1) } } }
      200.times do
        value = build.call(0)
        blob = begin
          Marshal.dump(value)
        rescue StandardError
          next
        end
        out = begin
          lnet::SafeMarshal.decode([blob].pack('m'))
        rescue ArgumentError
          next # a symbol in a broken encoding, refused as before
        end
        expect(LnetSpec.ascii_tree?(out)).to be(true), "#{value.inspect} gave #{out.inspect}"
      end
    end

    it 'shows a reply in ASCII when another player sends ISO-8859-1' do
      bounty = "Find the Stra#{LnetSpec::SHARP_S}e.".dup.force_encoding('ISO-8859-1')
      out = feed(data_element(bounty, type: 'bounty'))
      expect(out.map { |_kind, text| text.to_s }.join).to include('Find the Stra?e.')
    end
  end

  describe ';locate room matching' do
    # what find_room did up to 1.26, kept to show 1.27 picks the same room
    def legacy_find_room(data)
      title = data['title'].to_s
      description = data['description'].to_s.strip
      exits = data['exits'].to_s
      rooms = LnetSpec::Game.map_rooms
      room = rooms.find { |r| r.title.include?(title) && r.desc.include?(description) && r.paths.include?(exits) }
      return room if room

      pattern = Regexp.new(Regexp.escape(description.sub(/\.+\z/, '')).gsub(/\\\.(?:\\\.\\\.)?/, '|'))
      rooms.find { |r| r.title.include?(title) && r.paths.include?(exits) && r.desc.any? { |desc| desc =~ pattern } }
    end

    it 'finds the same room as the old Regexp for random descriptions full of regexp syntax' do
      rng = Random.new(31_337)
      alphabet = ['a', 'b', ' ', '.', '..', '...', '\\', '|', '(', ')', '[', ']', '{', '}', '*', '+', '?', '^', '$',
                  '#', '-', "\t", '&&', '(?i)', '\\1', 'x{2}', 'sq']
      text = -> { Array.new(rng.rand(0..8)) { alphabet.sample(random: rng) }.join }
      2_000.times do
        LnetSpec::Game.map_rooms = Array.new(rng.rand(1..5)) do |i|
          LnetSpec::MapRoom.new(i + 1, [%w[[A] [B]].sample(random: rng)], Array.new(rng.rand(0..2)) { text.call }, ['out'])
        end
        data = { 'title' => %w[[A] [B]].sample(random: rng), 'description' => text.call, 'exits' => 'out' }
        expected = legacy_find_room(data)&.id
        expect(lnet::Display.find_room(data)&.id).to eq(expected), "#{data.inspect} in #{LnetSpec::Game.map_rooms.inspect}"
      end
    end

    it 'builds no Regexp from the description' do
      LnetSpec::Game.map_rooms = [LnetSpec::MapRoom.new(7, ['[Square]'], ['A square. Pigeons (many) everywhere.'], ['out'])]
      allow(Regexp).to receive(:new).and_call_original
      data = { 'title' => '[Square]', 'description' => 'Pigeons (many) everywhere...', 'exits' => 'out' }
      expect(lnet::Display.find_room(data)&.id).to eq(7)
      expect(Regexp).not_to have_received(:new).with(a_string_including('Pigeons'))
    end

    it 'still matches any room by title and exits for an empty description' do
      LnetSpec::Game.map_rooms = [LnetSpec::MapRoom.new(3, ['[Square]'], ['Anything.'], ['out'])]
      expect(lnet::Display.find_room({ 'title' => '[Square]', 'description' => '...', 'exits' => 'out' })&.id).to eq(3)
    end
  end
end
