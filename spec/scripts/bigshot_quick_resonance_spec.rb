# frozen_string_literal: true

require_relative '../support/bigshot_quick_native_cmd_support'

module BigshotQuickResonanceSpec
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  class Admission; end
  Admission.class_eval(source[/^    def self.command_supported!\(command\)\n.*?^    end$/m])
  class Engine < BigshotQuickNativeCmdSpec::Engine; end
  Engine.class_eval(source[/^  def cmd_resonance_bolt\(ids, npc\)\n.*?^  end$/m])
end

RSpec.describe 'Quick admission and native resonance rotation' do
  let(:namespace) { BigshotQuickNativeCmdSpec }
  let(:owner) { namespace::Owner.new }
  let(:engine) { BigshotQuickResonanceSpec::Engine.new(owner) }
  let(:npc) { Struct.new(:id, :name, :noun).new('123', 'ogre', 'ogre') }
  let(:xml) { Struct.new(:current_target_id).new('777') }
  let(:spells) { [901, 903].to_h { |id| [id, namespace::NativeSpell.new(id, owner)] } }
  let(:identity) { { session: 'login', room_id: 42, room_epoch: 1, target_id: '123' } }
  let(:observed) { identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running) }
  let(:limit) { 10 }

  before do
    namespace::Script.current = owner
    namespace::Spell.entries = spells.merge(
      1201 => namespace::NativeSpell.new(1201, owner, known: false), 597 => namespace::NativeSpell.new(597, owner)
    )
    namespace::Spell.class_variable_set(:@@after_stance, 'original stance')
    stub_const('BigshotQuickNativeCmdSpec::XMLData', xml)
    allow(namespace::Char).to receive(:stance).and_return('guarded')
    spells.each do |id, spell|
      allow(spell).to receive(:name).and_return("Fixture #{id}")
      allow(spell).to receive(:stance).and_return(false)
      allow(spell).to receive(:force_incant) { owner.emit(">incant #{id}"); spell.result }
    end
    %i[debug_msg check_for_deaders_prone escape_rooms waitrt? waitcastrt? change_stance].each { |name| allow(engine).to receive(name) }
    allow(engine).to receive(:dead_or_gone?).and_return(false)
    allow(engine).to receive(:still_targetable?).with('123').and_return(true)
    allow(engine).to receive(:valid_target?).with(npc).and_return(true)
    allow(engine).to receive(:standing?).and_return(true)
    allow(engine).to receive(:checkprep).and_return('None')
    engine.instance_variable_set(:@last, 901)
    owner.on_send = ->(wire) { xml.current_target_id = wire.delete_prefix('>target #') if wire.start_with?('>target #') }
  end

  after do
    expect(owner.execution_guard_active?).to be(false)
    expect(namespace::Spell.class_variable_get(:@@after_stance)).to eq('original stance')
    namespace::Script.current = nil
    namespace::Spell.entries = nil
  end

  def execute(command = 'resonance 901 903')
    BigshotQuickResonanceSpec::Admission.command_supported!(command)
    guard = namespace::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                                      max_sends: limit, max_seconds: 20, clock: -> { 100.0 })
    engine.quick_execute(command, npc, guard: guard, owner: owner, prefix: '>')
  end

  it 'retains existing native spell selection and rotation through guarded incant on the exact target' do
    expect(engine).to receive(:cmd_resonance_bolt).with('901 901 903', npc).and_call_original
    expect(engine).to receive(:cmd_spell).with(incant: true, id: 903, target: npc).and_call_original
    expect(execute('resonance 901 901 903')).to eq(outcome: :sent, sends: 2)
    expect(engine.instance_variable_get(:@last)).to eq(903)
    expect(engine).to receive(:cmd_resonance_bolt).with('901 903', npc).and_call_original
    expect(engine).to receive(:cmd_spell).with(incant: true, id: 901, target: npc).and_call_original
    expect(execute).to eq(outcome: :sent, sends: 1)
    expect(engine.instance_variable_get(:@last)).to eq(901)
    expect(owner.wires).to eq(['>target #123', '>incant 903', '>incant 901'])
  end

  it 'retains native once modifiers without casting a second time' do
    expect(execute('resonance 901 903(once)')[:sends]).to eq(2)
    expect(execute('resonance 901 903(once)')).to eq(outcome: :skipped, sends: 0)
    expect(owner.wires).to eq(['>target #123', '>incant 903'])
  end

  it 'rejects every travel candidate before random selection or any socket send' do
    %w[130 00130 930 1020 9720 9825].each do |id|
      expect { execute("resonance 901 #{id}") }.to raise_error(ArgumentError, /Travel spells/)
      expect { execute("force resonance 901 #{id} until 2 (m50)") }.to raise_error(ArgumentError, /Travel spells/)
    end
    expect(owner.wires).to be_empty
  end

  it 'accepts the native space-separated syntax and rejects malformed or implicit extensions' do
    ['resonance 901 903', 'RESONANCE 901 903(m50)', 'force resonance 901 903 until 2', '506 resonance 901 903'].each do |command|
      expect(BigshotQuickResonanceSpec::Admission.command_supported!(command)).to be(true)
    end
    ['resonance', 'resonance901 903', 'resonance 901,903', 'resonance 901 open', 'resonance 901 target',
     'resonance 901 Fred', 'resonance 901 -903', 'resonance 901 903.5'].each do |command|
      expect { execute(command) }.to raise_error(ArgumentError, /space-separated/)
    end
    expect(owner.wires).to be_empty
  end

  it 'interrupts hindrance retries when the selected target changes without rotating the spell state' do
    spells[903].result = '[Spell Hindrance for fixture]'
    select = owner.on_send
    owner.on_send = lambda do |wire|
      select.call(wire)
      xml.current_target_id = '999' if wire == '>incant 903'
    end
    expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /incant_selector_changed/)
    expect(engine.instance_variable_get(:@last)).to eq(901)
    expect(owner.wires).to eq(['>target #123', '>incant 903'])
  end

  context 'with a two-send budget' do
    let(:limit) { 2 }

    it 'counts selector setup and the initial cast before denying a native hindrance retry' do
      spells[903].result = '[Spell Hindrance for fixture]'
      expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /command_limit/)
      expect(owner.wires).to eq(['>target #123', '>incant 903'])
      expect(engine.instance_variable_get(:@last)).to eq(901)
    end
  end
end
