# Spec for esorter.lic's downstream squelch: the original look text must be
# hidden whether or not Lich's inventory_boxes_off hook already stripped the
# container XML in front of it (it runs first, so esorter sees the bare line).

require_relative '../spec_helper'

module ESorterSpec
  SOURCE_PATH = find_lic_source('esorter.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")
  MODULE_SRC = extract_from_source(SOURCE, /^module ESorter\n.*?^end\n/m, label: 'module ESorter', source_path: SOURCE_PATH)
end

Object.send(:remove_const, :ESorter) if defined?(ESorter)
Object.class_eval(ESorterSpec::MODULE_SRC)

RSpec.describe ESorter do
  xml = %q{<exposeContainer id='stow'/><container id='stow' title="My Backpack" target='#692447856' location='right' save='' resident='true'/><clearContainer id="stow"/><inv id='stow'>In the <a exist="692447856" noun="backpack">backpack</a>:</inv><inv id='stow'> a <a exist="692447858" noun="ale">flagon of Dacra's Dream ale</a></inv>}
  text = %q{In the <a exist="692447856" noun="backpack">deerskin backpack</a> you see a <a exist="692447858" noun="ale">flagon of Dacra's Dream ale</a> and a <a exist="692447857" noun="Lace">sprig of Imaera's Lace</a>.}

  describe '.squelch' do
    it 'keeps only the container XML when the game sent it' do
      expect(described_class.squelch("#{xml}#{text}\r\n")).to eq(xml)
    end

    it 'squelches the bare line left after Lich strips the container XML' do
      expect(described_class.squelch("#{text}\r\n")).to be_nil
    end

    it 'passes through unrelated lines and mixed In/On lines' do
      expect(described_class.squelch("You see nothing.\r\n")).to eq("You see nothing.\r\n")
      mixed = "On the <a exist=\"1\" noun=\"table\">table</a> In the corner you see a thing.\r\n"
      expect(described_class.squelch(mixed)).to eq(mixed)
    end
  end

  describe 'LOOK_LINE' do
    it 'captures the container name for the sorted header' do
      expect(described_class::LOOK_LINE.match("#{xml}#{text}")[:container]).to eq('In the <a exist="692447856" noun="backpack">deerskin backpack</a>')
    end

    it 'recovers the original text by stripping the container XML' do
      expect("#{xml}#{text}".gsub(described_class::CONTAINER_XML, '')).to eq(text)
    end
  end
end
