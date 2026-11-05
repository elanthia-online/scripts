# frozen_string_literal: true

require_relative 'support/harness'

RSpec.describe 'lnet.lic' do
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

      # the parser's repair step drops control characters, so this calls
      # echo_thought directly to cover a caller that hands them over
      it 'strips control codes from the sender, channel and message' do
        out = LnetSpec.capture { lnet.echo_thought("Bob\x1CGSo", "a\x1CGSe\x1B[2Jb\x00", "Gen\x07") }
        client = out.find { |kind, _| kind == :client }[1]
        expect(client).to eq(%(You hear the faint thoughts of [Gen]-BobGSo echo in your mind:\r\n"aGSe[2Jb"\r\n))
        lnet.options['fam_window'] = true
        out = LnetSpec.capture { lnet.echo_thought("Bob\x1CGSo", "a\x1Cb", 'Private') }
        expect(out.first[1]).to eq(%(\034GSe\r\n[Private]-BobGSo: "ab"\r\n\034GSf\r\n))
      end
    end
  end
end
