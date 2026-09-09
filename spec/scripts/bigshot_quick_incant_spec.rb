# frozen_string_literal: true

# Reuse the existing actual-cmd/native-scope contract fixture. The optional
# companion integration in this fixture still uses the real Script guard.
require_relative '../support/bigshot_quick_native_cmd_support'

RSpec.describe 'Quick selector-bound production incant path' do
  let(:namespace) { BigshotQuickNativeCmdSpec }
  let(:owner) { namespace::Owner.new }
  let(:engine) { namespace::Engine.new(owner) }
  let(:npc) { Struct.new(:id, :name, :noun).new('123', 'giant rat', 'rat') }
  let(:spell_id) { 903 }
  let(:spell) { namespace::NativeSpell.new(spell_id, owner) }
  let(:xml) { Struct.new(:current_target_id).new('777') }
  let(:identity) { { session: 'login', room_id: 100, room_epoch: 1, target_id: '123' } }
  let(:observed) { identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running) }
  let(:clock) { [100.0] }
  let(:limit) { 10 }
  let(:guard) do
    namespace::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                              max_sends: limit, max_seconds: 20, clock: -> { clock[0] })
  end

  before do
    namespace::Script.current = owner
    namespace::Spell.entries = {
      spell_id => spell,
      1201     => namespace::NativeSpell.new(1201, owner, known: false),
      597      => namespace::NativeSpell.new(597, owner)
    }
    namespace::Spell.class_variable_set(:@@after_stance, 'original stance')
    stub_const('BigshotQuickNativeCmdSpec::XMLData', xml)
    allow(namespace::Char).to receive(:stance).and_return('guarded')
    allow(spell).to receive(:name).and_return('Fixture spell')
    allow(spell).to receive(:stance).and_return(false)
    allow(spell).to receive(:force_incant) do |_extra|
      owner.emit(">incant #{spell_id}")
      spell.result
    end
    %i[debug_msg check_for_deaders_prone escape_rooms waitrt? waitcastrt? change_stance].each do |method|
      allow(engine).to receive(method)
    end
    allow(engine).to receive(:dead_or_gone?).and_return(false)
    allow(engine).to receive(:still_targetable?).with('123').and_return(true)
    allow(engine).to receive(:valid_target?).with(npc).and_return(true)
    allow(engine).to receive(:standing?).and_return(true)
    allow(engine).to receive(:checkprep).and_return('None')
    owner.on_send = lambda do |wire|
      xml.current_target_id = wire.delete_prefix('>target #') if wire.start_with?('>target #')
      xml.current_target_id = nil if wire == '>target clear'
    end
  end

  after do
    expect(namespace::Spell.class_variable_get(:@@after_stance)).to eq('original stance')
    expect(engine.instance_variable_get(:@quick_incant_selector)).to be_nil
    expect(owner.execution_guard_active?).to be(false)
    namespace::Script.current = nil
    namespace::Spell.entries = nil
  end

  def execute
    engine.quick_execute("incant #{spell_id}", npc, guard: guard, owner: owner, prefix: '>')
  end

  it 'selects and confirms the exact target before entering the existing incant helper' do
    expect(engine).to receive(:cast_spell).with(spell_id: 903, extra: '', force: true).and_call_original
    expect(execute).to eq(outcome: :sent, sends: 2)
    expect(owner.wires).to eq(['>target #123', '>incant 903'])
  end

  it 'does not spend another target command when the selector is already exact' do
    xml.current_target_id = '123'
    expect(execute[:sends]).to eq(1)
    expect(owner.wires).to eq(['>incant 903'])
  end

  it 'cannot send a hindrance retry after the selector changes to another creature' do
    spell.result = '[Spell Hindrance for fixture]'
    select = owner.on_send
    owner.on_send = lambda do |wire|
      select.call(wire)
      xml.current_target_id = '999' if wire == '>incant 903'
    end
    expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /incant_selector_changed/)
    expect(owner.wires).to eq(['>target #123', '>incant 903'])
  end

  it 'rechecks the selector after the fresh execution snapshot before transport' do
    change_during_snapshot = false
    allow(guard).to receive(:checkpoint!).and_wrap_original do |original|
      result = original.call
      xml.current_target_id = '999' if change_during_snapshot
      result
    end
    allow(spell).to receive(:force_incant) do
      change_during_snapshot = true
      owner.emit('>incant 903')
    end
    expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /incant_selector_changed/)
    expect(owner.wires).to eq(['>target #123'])
  end

  it 'counts support preparation and target selection against the same command budget' do
    allow(spell).to receive(:force_incant) do
      owner.emit('>prepare 903')
      owner.emit('>incant 903')
    end
    bounded = namespace::QuickGuard.new(
      snapshot: -> { observed }, identity: identity,
      max_sends: 2, max_seconds: 20, clock: -> { clock[0] }
    )
    expect do
      engine.quick_execute('incant 903', npc, guard: bounded, owner: owner, prefix: '>')
    end.to raise_error(namespace::QuickGuard::Interrupted, /command_limit/)
    expect(owner.wires).to eq(['>target #123', '>prepare 903'])
  end

  it 'does not cast when native XML never confirms the selection' do
    owner.on_send = nil
    allow(engine).to receive(:sleep) do
      clock[0] = 121.0
      guard.checkpoint!
    end
    expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /time_limit/)
    expect(owner.wires).to eq(['>target #123'])
    expect(spell).not_to have_received(:force_incant)
  end

  it 'does not send restoration commands after a hold interrupts casting' do
    select = owner.on_send
    owner.on_send = lambda do |wire|
      select.call(wire)
      observed[:control] = :held if wire == '>incant 903'
    end
    expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /held/)
    expect(owner.wires).to eq(['>target #123', '>incant 903'])
  end

  context 'existing self-cast spell' do
    let(:spell_id) { 401 }

    it 'explicitly clears and verifies the selector, then restores the selected target on normal completion' do
      expect(execute).to eq(outcome: :sent, sends: 3)
      expect(owner.wires).to eq(['>target clear', '>incant 401', '>target #123'])
    end

    it 'does not retry or restore game state if a new selector appears during self-cast' do
      spell.result = '[Spell Hindrance for fixture]'
      select = owner.on_send
      owner.on_send = lambda do |wire|
        select.call(wire)
        xml.current_target_id = '999' if wire == '>incant 401'
      end
      expect { execute }.to raise_error(namespace::QuickGuard::Interrupted, /incant_selector_changed/)
      expect(owner.wires).to eq(['>target clear', '>incant 401'])
    end
  end
end
