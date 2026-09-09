# frozen_string_literal: true

require_relative '../support/bigshot_quick_native_cmd_support'

RSpec.describe 'Bigshot Quick execution of the existing cmd engine' do
  let(:owner) { BigshotQuickNativeCmdSpec::Owner.new }
  let(:engine) { BigshotQuickNativeCmdSpec::Engine.new(owner) }
  let(:npc) { Struct.new(:id, :name, :noun).new('123', 'giant rat', 'rat') }
  let(:spell) { BigshotQuickNativeCmdSpec::NativeSpell.new(903, owner) }
  let(:identity) { { session: 'login', room_id: 100, room_epoch: 1, target_id: '123' } }
  let(:observed) { identity.merge(owner: true, connected: true, authorized: true, target_valid: true, safe: true, control: :running) }
  let(:limit) { 10 }
  let(:guard) do
    BigshotQuickNativeCmdSpec::QuickGuard.new(snapshot: -> { observed }, identity: identity,
                                              max_sends: limit, max_seconds: 20, clock: -> { 100.0 })
  end

  before do
    BigshotQuickNativeCmdSpec::Script.current = owner
    BigshotQuickNativeCmdSpec::Spell.entries = {
      903  => spell,
      1201 => BigshotQuickNativeCmdSpec::NativeSpell.new(1201, owner, known: false),
      597  => BigshotQuickNativeCmdSpec::NativeSpell.new(597, owner)
    }
    %i[debug_msg check_for_deaders_prone escape_rooms waitrt? waitcastrt? change_stance].each do |method|
      allow(engine).to receive(method)
    end
    allow(engine).to receive(:dead_or_gone?).and_return(false)
    allow(engine).to receive(:still_targetable?).with('123').and_return(true)
    allow(engine).to receive(:valid_target?).with(npc).and_return(true)
    allow(engine).to receive(:standing?).and_return(true)
    allow(engine).to receive(:checkprep).and_return('None')
    @saved_ambusher = $ambusher_here
    $ambusher_here = nil
  end

  after do
    BigshotQuickNativeCmdSpec::Script.current = nil
    BigshotQuickNativeCmdSpec::Spell.entries = nil
    $ambusher_here = @saved_ambusher
  end

  def execute(command)
    engine.quick_execute(command, npc, guard: guard, owner: owner, prefix: '>')
  end

  it 'substitutes the exact NPC ID through native cmd and bs_put without changing the saved command' do
    command = 'attack target'
    expect(execute(command)).to eq(outcome: :sent, sends: 1)
    expect(owner.wires).to eq(['>attack #123'])
    expect(command).to eq('attack target')
    expect(engine.instance_variable_get(:@COMMANDS_REGISTRY)['123']).to have_key(command)
  end

  it 'uses native amount modifiers to skip a command without sending' do
    expect(execute('attack target(m50)')).to eq(outcome: :skipped, sends: 0)
    expect(owner.wires).to be_empty
    expect(engine.instance_variable_get(:@COMMANDS_REGISTRY)).to be_empty
  end

  it 'uses the native once registry to skip later copies of a command in an array' do
    expect(execute(['attack target(once)', 'attack target(once)'])[:sends]).to eq(1)
    expect(owner.wires).to eq(['>attack #123'])
  end

  it 'reaches production cmd_spell and cast_spell on the original engine and canonical Spell receiver' do
    expect(engine).to receive(:cmd_spell).with(incant: nil, id: 903, extra: '', target: npc).and_call_original
    expect(engine).to receive(:cast_spell).with(spell_id: 903, target: '#123', extra: '').and_call_original
    expect(execute('903')[:sends]).to eq(2)
    expect(spell.calls).to eq([[spell, ['#123', '']]])
    expect(owner.wires).to eq(['>prepare 903', '>cast #123'])
  end

  it 'stops the remaining native array commands when control is held after a send' do
    owner.on_send = ->(_wire) { observed[:control] = :held }
    expect { execute(['attack target', 'attack target']) }.to raise_error(BigshotQuickNativeCmdSpec::QuickGuard::Interrupted, /held/)
    expect(owner.wires).to eq(['>attack #123'])
    expect(owner.execution_guard_active?).to be(false)
  end

  context 'production single-target UAC' do
    let(:npc) { Struct.new(:id, :name, :noun, :type).new('123', 'giant rat', 'rat', 'aggressive npc') }

    before do
      @saved_uac = [$bigshot_aim, $bigshot_unarmed_tier, $bigshot_unarmed_followup,
                    $bigshot_unarmed_followup_attack, $bigshot_smite_list, $mstrike_taken]
      $bigshot_aim, $bigshot_unarmed_tier, $bigshot_unarmed_followup = 0, 1, false
      $bigshot_unarmed_followup_attack, $bigshot_smite_list, $mstrike_taken = '', [], false
      engine.instance_variable_set(:@TIER3, 'punch')
      engine.instance_variable_set(:@AIM, [])
      allow(engine).to receive(:get).and_return('Roundtime: 3 sec.')
    end

    after do
      $bigshot_aim, $bigshot_unarmed_tier, $bigshot_unarmed_followup,
        $bigshot_unarmed_followup_attack, $bigshot_smite_list, $mstrike_taken = @saved_uac
    end

    [false, true].each do |disable_mstrike|
      it "keeps Quick unarmed targeted when the profile do-not-mstrike flag is #{disable_mstrike}" do
        engine.instance_variable_set(:@UAC_MSTRIKE, disable_mstrike)
        expect(engine).not_to receive(:cmd_mstrike)
        expect(engine).to receive(:cmd_unarmed).with('jab', npc, '', true).and_call_original
        expect(execute('unarmed jab')).to eq(outcome: :sent, sends: 1)
        expect(owner.wires).to eq(['>jab #123'])
      end
    end

    it 'keeps native Quick tier-three targeting without allowing a nested room sweep' do
      engine.instance_variable_set(:@UAC_MSTRIKE, false)
      execute('unarmed jab')
      $bigshot_unarmed_tier = 3
      expect(engine).not_to receive(:cmd_mstrike)
      expect(execute('unarmed jab')).to eq(outcome: :sent, sends: 2)
      expect(owner.wires).to eq(['>jab #123', '>punch #123'])
    end

    it 'retains native followup and aim state across routines on the same guarded target' do
      engine.instance_variable_set(:@AIM, %w[head chest])
      allow(engine).to receive(:get).and_call_original
      owner.on_send = lambda do |_wire|
        next unless owner.wires.length == 1

        owner.downstream_buffer.replace([
                                          'You have excellent positioning', 'Strike leaves foe vulnerable to a followup kick attack!',
                                          'You fail to find an opening for your strike.', 'Sorry,'
                                        ])
      end
      expect(engine).to receive(:reset_variables).with(false).once.and_call_original
      execute('unarmed jab')
      expect([$bigshot_unarmed_tier, $bigshot_unarmed_followup, $bigshot_aim]).to eq([3, true, 1])
      next_guard = BigshotQuickNativeCmdSpec::QuickGuard.new(
        snapshot: -> { observed }, identity: identity, max_sends: 10, max_seconds: 20, clock: -> { 100.0 }
      )
      engine.quick_execute('unarmed jab', npc, guard: next_guard, owner: owner, prefix: '>')
      expect(owner.wires).to eq(['>jab #123 head', '>kick #123 chest'])
    end

    %i[target_id room_id room_epoch session].each do |changed_key|
      it "clears stale UAC tier, followup and aim when guarded #{changed_key} changes" do
        engine.instance_variable_set(:@AIM, %w[head chest])
        execute('unarmed jab')
        $bigshot_unarmed_tier, $bigshot_unarmed_followup = 3, true
        $bigshot_unarmed_followup_attack, $bigshot_aim = 'kick', 1
        next_identity = identity.merge(changed_key => "#{identity[changed_key]}9")
        npc.id = next_identity[:target_id]
        allow(engine).to receive(:still_targetable?).with(npc.id).and_return(true)
        observed.merge!(next_identity)
        next_guard = BigshotQuickNativeCmdSpec::QuickGuard.new(
          snapshot: -> { observed }, identity: next_identity, max_sends: 10, max_seconds: 20, clock: -> { 100.0 }
        )
        expect(engine).to receive(:reset_variables).with(false).once.and_call_original
        engine.quick_execute('unarmed jab', npc, guard: next_guard, owner: owner, prefix: '>')
        expect(owner.wires.last).to eq(">jab ##{npc.id} head")
        expect([$bigshot_unarmed_tier, $bigshot_unarmed_followup, $bigshot_unarmed_followup_attack]).to eq([1, false, ''])
      end
    end

    it 'clears state inherited from legacy combat on the first Quick target' do
      $bigshot_unarmed_tier, $bigshot_unarmed_followup = 3, true
      $bigshot_unarmed_followup_attack, $bigshot_aim = 'kick', 1
      engine.instance_variable_set(:@AIM, %w[head chest])
      execute('unarmed jab')
      expect(owner.wires).to eq(['>jab #123 head'])
    end

    it 'preserves legacy automatic mstrike when the do-not-mstrike flag is false' do
      engine.instance_variable_set(:@UAC_MSTRIKE, false)
      allow(engine).to receive(:sleep)
      expect(engine).to receive(:cmd_mstrike).with('mstrike punch', npc) { $mstrike_taken = true }
      engine.cmd_unarmed('jab', npc, '', true)
      expect(owner.wires).to be_empty
    end

    it 'preserves legacy single-target UAC when the do-not-mstrike flag is true' do
      engine.instance_variable_set(:@UAC_MSTRIKE, true)
      expect(engine).not_to receive(:cmd_mstrike)
      engine.cmd_unarmed('jab', npc, '', true)
      expect(owner.wires).to eq(['>jab #123'])
    end
  end

  context 'with a two-send budget' do
    let(:limit) { 2 }

    it 'counts the existing bs_put retry path and prevents a third wire write' do
      owner.response = '...wait 1 seconds.'
      expect { execute('attack target') }.to raise_error(BigshotQuickNativeCmdSpec::QuickGuard::Interrupted, /command_limit/)
      expect(owner.wires).to eq(['>attack #123', '>attack #123'])
      expect(guard.sends).to eq(2)
    end

    it 'bounds native cast_spell hindrance retries including sends from the Spell receiver' do
      spell.result = '[Spell Hindrance for test]'
      expect { execute('903') }.to raise_error(BigshotQuickNativeCmdSpec::QuickGuard::Interrupted, /command_limit/)
      expect(owner.wires).to eq(['>prepare 903', '>cast #123'])
      expect(spell.calls.length).to eq(2)
      expect(owner.execution_guard_active?).to be(false)
    end

    it 'bounds a native array before its third command sends' do
      expect { execute(Array.new(3, 'attack target')) }.to raise_error(BigshotQuickNativeCmdSpec::QuickGuard::Interrupted, /command_limit/)
      expect(owner.wires).to eq(['>attack #123', '>attack #123'])
    end
  end

  context 'through the production run and controller' do
    let(:world) { observed.merge(targets: [{ id: '123', name: 'giant rat', noun: 'rat', hostile: true }], members: []) }
    let(:run) do
      policy = BigshotQuickNativeCmdSpec::EncounterPolicy.new(
        { 'mode' => 'watch', 'max_actions' => 10, 'max_seconds' => 30 },
        targets: { 'giant rat' => 'a' }, routines: { 'a' => ['903'] }
      )
      BigshotQuickNativeCmdSpec::QuickRun.new(engine: engine, policy: policy, owner: owner,
                                              snapshot: -> { world }, resolve_target: ->(_) { npc },
                                              validate: ->(command) { command == '903' }, prefix: '>', clock: -> { 100.0 })
    end

    it 'unwinds a real spell route on queued hold, accounts preparation, then resumes a fresh scope' do
      session = run
      owner.on_send = ->(_) { session.request('hold') }
      expect(session.tick).to include(state: :held, actions: 1)
      expect(owner.wires).to eq(['>prepare 903'])
      expect(owner.execution_guard_active?).to be(false)
      owner.on_send = nil
      session.request('resume')
      expect(session.tick).to include(state: :running, actions: 3)
      expect(owner.wires).to eq(['>prepare 903', '>prepare 903', '>cast #123'])
    end

    it 'stops between real commands when the session changes rather than rebinding the character' do
      session = run
      expect(session.tick[:actions]).to eq(2)
      world[:session] = 'replacement login'
      expect(session.tick).to include(state: :stopped, reason: 'session_changed')
      expect(owner.wires).to eq(['>prepare 903', '>cast #123'])
    end
  end
end
