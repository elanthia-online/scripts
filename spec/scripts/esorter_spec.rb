# Spec for esorter.lic's downstream hook: the original look text must be
# hidden whether or not Lich's inventory_boxes_off hook already stripped the
# container XML in front of it (it runs first, so esorter sees the bare line),
# and the sorted list must land in front of the prompt that ends the look.

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
  text = %q{In the <a exist="692447856" noun="backpack">deerskin backpack</a> you see a <a exist="692447858" noun="ale">flagon of Dacra's Dream ale</a>.}
  prompt = %(<prompt time="1791304487">&gt;</prompt>\r\n)

  before do
    described_class.instance_variable_set(:@pending, nil)
    allow(described_class).to receive(:sorted_text) { |label, id, _original| "SORTED #{id} #{label}\r\n" }
  end

  it 'keeps only the container XML, then puts the sorted list before the prompt' do
    expect(described_class.hook("#{xml}#{text}\r\n")).to eq(xml)
    expect(described_class.hook(prompt)).to eq(%(SORTED 692447856 In the <a exist="692447856" noun="backpack">deerskin backpack</a>\r\n#{prompt}))
  end

  it 'squelches the bare line left after Lich strips the container XML' do
    expect(described_class.hook("#{text}\r\n")).to be_nil
    expect(described_class.hook(prompt)).to start_with('SORTED 692447856')
  end

  it 'handles the look and prompt arriving in one line' do
    expect(described_class.hook("#{text}\r\n#{prompt}")).to start_with('SORTED 692447856').and end_with(prompt)
  end

  it 'handles room containers, which have negative ids' do
    bench = %(<container id='-49715' title='Benches' target='#-49715' location='right'/><clearContainer id="-49715"/><inv id='-49715'>On the <a exist="-49715" noun="benches">benches</a>:</inv>)
    expect(described_class.hook(%(#{bench}On the <a exist="-49715" noun="benches">wide stone benches</a> you see <a exist="688512006" noun="clove">some sovyn clove</a>.\r\n))).to eq(bench)
    expect(described_class.hook(prompt)).to start_with('SORTED -49715 On the')
  end

  it 'passes through unrelated lines, mixed In/On lines and prompts with nothing pending' do
    mixed = "On the <a exist=\"1\" noun=\"table\">table</a> In the corner you see a thing.\r\n"
    [mixed, "You see nothing.\r\n", prompt].each { |line| expect(described_class.hook(line)).to eq(line) }
  end

  it 'recovers the original text by stripping the container XML' do
    expect("#{xml}#{text}".gsub(described_class::CONTAINER_XML, '')).to eq(text)
  end
end
