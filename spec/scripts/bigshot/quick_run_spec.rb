# frozen_string_literal: true

require_relative '../../support/bigshot_quick_run_harness'

RSpec.describe BigshotQuickRunSpec::QuickRun do
  let(:settings) { { 'mode' => 'watch', 'max_actions' => 10, 'max_seconds' => 30 } }
  let(:target) { { id: '123', name: 'giant rat', noun: 'rat', hostile: true } }
  let(:snapshot) do
    { session: 'login', room_id: 100, room_epoch: 1, targets: [target], members: ['Friend'],
      safe: true, owner: true, connected: true }
  end
  let(:reads) { [] }
  let(:native_target) { Object.new }
  let(:clock) { [100.0] }
  let(:engine) { BigshotQuickRunSpec::Engine.new }
  let(:owner) { BigshotQuickRunSpec::Owner.new }
  let(:policy) { BigshotQuickRunSpec::EncounterPolicy.new(settings, targets: { 'giant rat' => 'a' }, routines: { 'a' => ['unarmed jab'] }) }
  let(:retreat_calls) { [] }
  let(:loot) { nil }
  let(:execution_window) { nil }
  let(:retreat) { -> { retreat_calls << owner.execution_guard_active?; :retreated } }
  let(:run) do
    described_class.new(engine: engine, policy: policy, owner: owner, snapshot: -> { reads << true; snapshot },
                        resolve_target: ->(id) { native_target if snapshot[:targets].any? { |npc| npc[:id] == id } },
                        validate: ->(command) { command == 'unarmed jab' }, prefix: '>', retreat: retreat, loot: loot,
                        trial: settings['mode'] == 'trial' ? { target_id: '123', actions: ['unarmed jab'] } : nil,
                        clock: -> { clock.first }, execution_window: execution_window)
  end

  it 'dispatches existing profile syntax through the original engine and native target resolver' do
    expect(run.tick).to include(state: :running, actions: 1)
    expect(engine.calls.first).to include(command: 'unarmed jab', target: native_target, prefix: '>')
  end

  context 'with a supervised startup window' do
    let(:execution_window) { { work_deadline: 120.0, cleanup_deadline: 130.0 } }

    before do
      timer = clock
      owner.define_singleton_method(:stopping?) { false }
      owner.define_singleton_method(:execution_sleep) { |seconds| timer[0] += seconds }
    end

    it 'waits without work until one activation and cannot renew its deadlines' do
      instance = run
      timer = clock
      owner.define_singleton_method(:execution_sleep) do |seconds|
        timer[0] += seconds
        instance.activate_supervised(valid: -> { true })
      end
      expect(run.await_supervisor!).to be(true)
      expect(engine.calls).to be_empty
      expect(run.activate_supervised(valid: -> { true })).to be(false)
      expect(run.bind_execution_window(work_deadline: 130.0, cleanup_deadline: 140.0)).to be(false)
      expect(run.tick[:actions]).to eq(1)
    end

    it 'times out abandoned startup without commands' do
      expect { run.await_supervisor! }.to raise_error(ArgumentError, /startup expired/)
      expect(engine.calls).to be_empty
    end

    it 'refuses startup when the room changes during binding' do
      observed = snapshot
      owner.define_singleton_method(:execution_sleep) { |_| observed[:room_epoch] += 1 }
      expect { run.await_supervisor! }.to raise_error(ArgumentError, /room/)
      expect(engine.calls).to be_empty
    end

    it 'refuses startup when the exact owner is stopping' do
      owner.define_singleton_method(:stopping?) { true }
      expect { run.await_supervisor! }.to raise_error(ArgumentError, /owner/)
      expect(engine.calls).to be_empty
    end

    it 'refuses activation and work once the fixed launch work deadline expires' do
      instance = run
      clock[0] = 120.0
      expect(instance.activate_supervised(valid: -> { true })).to be(false)
      expect { instance.await_supervisor! }.to raise_error(ArgumentError, /expired/)
      expect(engine.calls).to be_empty
    end

    it 'refuses startup when the session changes while waiting for the supervisor' do
      observed = snapshot
      owner.define_singleton_method(:execution_sleep) { |_| observed[:session] = 'replacement' }
      expect { run.await_supervisor! }.to raise_error(ArgumentError, /session/)
      expect(engine.calls).to be_empty
    end

    it 'refuses commands after the activated cached authority is revoked' do
      allowed = true
      expect(run.activate_supervised(valid: -> { allowed })).to be(true)
      run.await_supervisor!
      allowed = false
      run.tick
      expect(engine.calls).to be_empty
    end
  end

  it 'returns immutable cached status without game reads from another thread' do
    run.tick
    count = reads.length
    status = Thread.new { run.request('status') }.value
    expect(reads.length).to eq(count)
    expect(status[:status]).to be_frozen
    expect(status[:status][:observations]).to be_frozen
    expect { status[:status][:observations].clear }.to raise_error(FrozenError)
  end

  it 'admits no new combat after the supervisor work cutoff' do
    run.bind_execution_window(work_deadline: 105.0, cleanup_deadline: 115.0)
    clock[0] = 105.0
    expect(run.tick).to include(state: :stopped, reason: 'operation_work_deadline', sends: 0)
    expect(engine.calls).to be_empty
  end

  it 'blocks the next send inside an already admitted combat routine at the work cutoff' do
    run.bind_execution_window(work_deadline: 105.0, cleanup_deadline: 115.0)
    engine.routine = lambda do |guard|
      guard.transmit('attack #123') {}
      clock[0] = 105.0
      guard.transmit('attack #123') { raise 'late attack must be denied' }
    end
    expect(run.tick).to include(reason: 'operation_work_deadline', sends: 1)
    expect(run.tick).to include(state: :stopped, reason: 'operation_work_deadline', sends: 1)
  end

  it 'bounds the control mailbox and refuses unknown controls' do
    32.times { expect(run.request('hold')[:accepted]).to be(true) }
    expect(run.request('resume')).to include(accepted: false, reason: 'control_queue_full')
    expect(run.request('invented')).to include(accepted: false, reason: 'unknown_control')
    expect(reads).to be_empty
  end

  context 'with human permission for an unfamiliar hostile' do
    let(:settings) { super().merge('unknown' => 'manual', 'fallback_commands' => 'unarmed jab') }
    let(:policy) { BigshotQuickRunSpec::EncounterPolicy.new(settings, fallback: ['unarmed jab']) }

    it 'grants a current target permission only when the owner drains the selection' do
      run.tick
      expect(engine.calls).to be_empty
      count = reads.length
      reply = Thread.new { run.request_engagement('123') }.value
      expect(reply[:accepted]).to be(true)
      expect(reads.length).to eq(count)
      expect(engine.calls).to be_empty
      expect(run.tick[:actions]).to eq(1)
    end

    it 'rejects uninitialized scenes, invalid IDs and closed runs' do
      expect(run.request_engagement('123')[:reason]).to eq('room_unverified')
      run.tick
      expect(run.request_engagement('0')[:reason]).to eq('invalid_target_id')
      run.close
      expect(run.request_engagement('123')[:reason]).to eq('run_closed')
    end

    it 'does not transfer queued permission across movement even if an ID is reused' do
      run.tick
      run.request_engagement('123')
      snapshot[:room_epoch] += 1
      expect(run.tick[:control_error]).to eq('engagement_stale_or_ineligible')
      expect(engine.calls).to be_empty
    end

    it 'rechecks the receipt scene in the controller final selection observation' do
      run.tick
      run.request_engagement('123')
      count = 0
      allow(reads).to receive(:<<).and_wrap_original do |original, *args|
        count += 1
        snapshot[:room_epoch] += 1 if count == 2
        original.call(*args)
      end
      expect(run.tick[:control_error]).to eq('engagement_stale_or_ineligible')
      expect(engine.calls).to be_empty
    end

    it 'expires queued selections and refuses newly dead or nonhostile targets' do
      run.tick
      run.request_engagement('123')
      clock[0] += 4
      run.tick
      expect(engine.calls).to be_empty
      run.request_engagement('123')
      target[:hostile] = false
      expect(run.tick[:control_error]).to eq('engagement_stale_or_ineligible')
      expect(engine.calls).to be_empty
    end

    it 'does not bypass explicit exclusions' do
      settings['excluded_creatures'] = 'giant rat'
      run.tick
      run.request_engagement('123')
      run.tick
      expect(engine.calls).to be_empty
    end

    it 'does not override the unknown-ignore policy' do
      settings['unknown'] = 'ignore'
      run.tick
      run.request_engagement('123')
      run.tick
      expect(engine.calls).to be_empty
    end

    it 'checks ownership and connection when applying a queued selection' do
      run.tick
      run.request_engagement('123')
      snapshot[:owner] = false
      expect(run.tick[:control_error]).to eq('engagement_stale_or_ineligible')
      expect(engine.calls).to be_empty
    end

    it 'respects hold, clears permission on resume and shares the bounded mailbox' do
      run.tick
      run.request_engagement('123')
      run.request('hold')
      run.tick
      expect(run.request_engagement('123')[:reason]).to eq('engagement_unavailable')
      run.request('resume')
      run.tick
      expect(engine.calls).to be_empty
      32.times { expect(run.request_engagement('123')[:accepted]).to be(true) }
      expect(run.request_engagement('123')[:reason]).to eq('control_queue_full')
    end
  end

  it 'does not allow manual selection to retarget a bounded trial' do
    settings['mode'] = 'trial'
    expect(run.request_engagement('999')[:reason]).to eq('engagement_unavailable')
  end

  it 'keeps controller operations on their constructing thread' do
    instance = run
    result = Thread.new { instance.tick rescue $! }.value
    expect(result).to be_a(ThreadError)
    expect(reads).to be_empty
  end

  it 'accounts every send before a queued hold interrupts a helper wait' do
    instance = run
    engine.routine = lambda do |guard|
      3.times { guard.transmit('support') { engine.sends << 'support' } }
      Thread.new { instance.request('hold') }.join
      guard.checkpoint!
      guard.transmit('must not send') { engine.sends << 'must not send' }
    end
    expect(instance.tick).to include(state: :held, reason: 'held', actions: 3)
    expect(engine.sends).to eq(%w[support support support])
  end

  it 'preserves a stop received during dispatch after accounting actual sends' do
    instance = run
    engine.routine = lambda do |guard|
      2.times { guard.transmit('support') { engine.sends << 'support' } }
      instance.request('stop')
      guard.checkpoint!
    end
    expect(instance.tick).to include(state: :stopped, reason: 'manual_stop', actions: 2)
    instance.tick
    expect(engine.calls.length).to eq(1)
  end

  it 'defers retreat until the native execution scope has unwound' do
    instance = run
    engine.routine = lambda do |guard|
      guard.transmit('attack #123') { engine.sends << 'attack #123' }
      instance.request('retreat')
      expect(owner.execution_guard_active?).to be(true)
      guard.checkpoint!
    end
    expect(instance.tick).to include(state: :stopped, reason: 'retreated', actions: 1, retreat_pending: false)
    expect(retreat_calls).to eq([false])
  end

  it 'leaves resume queued until cancellation unwinds and obtains a fresh guard next tick' do
    instance = run
    engine.routine = lambda do |guard|
      guard.transmit('support') { engine.sends << 'support' }
      instance.request('hold')
      instance.request('resume')
      guard.checkpoint!
    end
    expect(instance.tick[:state]).to eq(:held)
    first_guard = engine.calls.first[:guard]
    engine.routine = ->(guard) { guard.transmit('support') { engine.sends << 'support' } }
    expect(instance.tick[:state]).to eq(:running)
    expect(engine.calls.last[:guard]).not_to equal(first_guard)
    expect { first_guard.checkpoint! }.to raise_error(BigshotQuickRunSpec::QuickGuard::Interrupted)
  end

  it 'rechecks assist member permission during a helper and requires fresh engagement after resume' do
    settings.merge!('mode' => 'assist', 'trigger' => 'leader', 'leader' => 'Friend', 'targeting' => 'assist-only')
    instance = run
    instance.observe_engagement(member: 'Friend', target_id: '123', room_id: 100, room_epoch: 1, at: 100.0)
    engine.routine = lambda do |guard|
      guard.transmit('support') { engine.sends << 'support' }
      snapshot[:members] = []
      guard.checkpoint!
    end
    expect(instance.tick).to include(state: :held, reason: 'permission_revoked')
    snapshot[:members] = ['Friend']
    instance.request('resume')
    instance.tick
    expect(engine.calls.length).to eq(1)
  end

  it 'allows watch to reevaluate a dead target without holding permanently' do
    engine.routine = lambda do |guard|
      guard.transmit('attack #123') { engine.sends << 'attack #123' }
      snapshot[:targets] = []
      guard.checkpoint!
    end
    expect(run.tick).to include(state: :running, actions: 1)
    expect(run.tick[:state]).to eq(:running)
  end

  it 'stops a trial whose explicit target disappears during its routine' do
    settings['mode'] = 'trial'
    engine.routine = lambda do |guard|
      guard.transmit('attack #123') { engine.sends << 'attack #123' }
      snapshot[:targets] = []
      guard.checkpoint!
    end
    expect(run.tick).to include(state: :stopped, reason: 'target_unavailable', actions: 1)
  end

  it 'accounts sends even when the engine raises an unrelated error' do
    engine.routine = lambda do |guard|
      3.times { guard.transmit('support') { engine.sends << 'support' } }
      raise 'unconfirmed helper failure'
    end
    expect(run.tick).to include(state: :held, reason: 'execution_error', actions: 3)
  end

  it 'does not report an empty room clear when disconnected or ownership is missing' do
    settings['mode'] = 'clear'
    snapshot[:targets] = []
    snapshot[:connected] = false
    expect(run.tick).to include(state: :held, reason: 'disconnected')
    snapshot[:connected] = true
    snapshot.delete(:owner)
    expect(run.tick).to include(state: :held, reason: 'owner_lost')
    expect(engine.calls).to be_empty
  end

  it 'does not execute a queued retreat after losing ownership' do
    run.request('retreat')
    snapshot[:owner] = false
    expect(run.tick).to include(state: :held, reason: 'owner_lost', retreat_pending: false)
    expect(retreat_calls).to be_empty
  end

  it 'honors a stop queued behind retreat before entering the movement callback' do
    instance = run
    engine.routine = lambda do |guard|
      guard.transmit('support') { engine.sends << 'support' }
      instance.request('retreat')
      instance.request('stop')
      guard.checkpoint!
    end
    expect(instance.tick).to include(state: :stopped, reason: 'manual_stop', actions: 1)
    expect(retreat_calls).to be_empty
  end

  it 'pins session identity across routines and cannot resume into another session' do
    run.tick
    snapshot[:session] = 'another-login'
    expect(run.tick).to include(state: :stopped, reason: 'session_changed')
    run.request('resume')
    snapshot[:session] = 'login'
    expect(run.tick).to include(state: :stopped, reason: 'session_changed')
    expect(engine.calls.length).to eq(1)
  end

  it 'rejects a queued retreat after a between-routine session change' do
    run.tick
    run.request('retreat')
    snapshot[:session] = 'another-login'
    expect(run.tick).to include(state: :stopped, reason: 'session_changed', retreat_pending: false)
    expect(retreat_calls).to be_empty
  end

  it 'closes by clearing controls and pending movement while preserving cached status reads' do
    run.request('retreat')
    expect(run.close).to include(state: :stopped, reason: 'manual_stop', retreat_pending: false)
    expect(run.request('resume')).to include(accepted: false, reason: 'run_closed')
    expect(run.request('status')[:accepted]).to be(true)
    run.tick
    expect(retreat_calls).to be_empty
    expect(reads).to be_empty
  end

  it 'revalidates queued controls on the owner thread after their approval expires' do
    valid = true
    calls = []
    instance = run
    predicate = -> { calls << Thread.current; valid }
    expect(Thread.new { instance.request('stop', valid: predicate) }.value[:accepted]).to be(true)
    expect(calls).to be_empty
    valid = false
    expect(instance.tick).to include(state: :running, control_error: 'control_expired_or_revoked')
    expect(calls).to eq([Thread.current])
    expect(engine.calls.length).to eq(1)
  end

  it 'drops failed predicates and does not hold the mailbox mutex during validation' do
    instance = run
    instance.request('stop', valid: -> { raise 'revoked' })
    expect(instance.tick).to include(state: :running, control_error: 'control_expired_or_revoked')
    instance.request('hold', valid: -> { Thread.new { instance.status }.join(1) != nil })
    expect(instance.tick[:state]).to eq(:held)
    expect(instance.status).not_to have_key(:control_error)
  end

  it 'accepts only Proc predicates and literal true authorization' do
    expect(run.request('stop', valid: true)).to include(accepted: false, reason: 'invalid_control_predicate')
    run.request('stop', valid: -> { :truthy })
    expect(run.tick).to include(state: :running, control_error: 'control_expired_or_revoked')
  end

  it 'rechecks retreat approval after native unwinding before actual movement' do
    instance = run
    approved = true
    engine.routine = lambda do |guard|
      begin
        instance.request('retreat', valid: -> { approved })
        guard.checkpoint!
      ensure
        approved = false
      end
    end
    expect(instance.tick).to include(state: :held, reason: 'retreat_unconfirmed', control_error: 'control_expired_or_revoked')
    expect(retreat_calls).to be_empty
  end

  it 'preserves terminal session loss detected by the retreat adapter' do
    instance = run
    instance.tick
    instance.instance_variable_set(:@retreat, lambda {
      snapshot[:session] = 'replacement-login'
      instance.__send__(:run_snapshot)
      :unconfirmed
    })
    instance.request('retreat')
    expect(instance.tick).to include(state: :stopped, reason: 'session_changed')
  end

  context 'with room cleanup enabled' do
    let(:settings) { { 'mode' => 'clear', 'max_actions' => 10, 'max_seconds' => 30, 'loot' => 'room', 'loot_max_actions' => 10 } }
    let(:loot) { BigshotQuickRunSpec::QuickLoot.new(settings, character: 'Tester', clock: -> { clock.first }) }

    before do
      snapshot[:targets] = []
      snapshot[:corpses] = [{ id: '123' }]
      snapshot[:loot_ids] = ['456']
    end

    it 'stops between corpses before drawing a second tool near the outer deadline' do
      instance = run
      expect(instance.bind_execution_window(work_deadline: 105.0, cleanup_deadline: 115.0)).to be(true)
      expect(instance.tick).to include(state: :running, loot_sends: 1)
      clock[0] = 105.0
      expect(instance.tick).to include(state: :stopped, reason: 'operation_work_deadline', loot_sends: 1)
      expect(engine.sends).to eq(['loot #123'])
    end

    it 'reserves cleanup while the same hard deadline still bounds equipment recovery' do
      instance = run
      instance.bind_execution_window(work_deadline: 105.0, cleanup_deadline: 115.0)
      engine.on_loot = true
      engine.routine = lambda do |guard|
        guard.transmit('get #789') {}
        clock[0] = 105.0
        guard.transmit('skin #123') { raise 'work must not continue' }
      end
      expect(engine).to receive(:quick_loot_restore) do |guard:, **|
        guard.transmit('put #789 in #987') {}
        clock[0] = 115.0
        guard.transmit('stand') { raise 'cleanup must not exceed its deadline' }
      end
      expect(instance.tick).to include(state: :stopped, reason: 'operation_work_deadline',
                                       loot_recovery: { outcome: :unconfirmed, sends: 1 })
    end

    it 'never extends or replaces an already bound execution window' do
      instance = run
      expect(instance.bind_execution_window(work_deadline: 105.0, cleanup_deadline: 115.0)).to be(true)
      expect(instance.bind_execution_window(work_deadline: 150.0, cleanup_deadline: 160.0)).to be(false)
      clock[0] = 105.0
      expect(instance.tick).to include(state: :stopped, reason: 'operation_work_deadline')
    end

    it 'does not let the cleanup reserve override an explicit stop' do
      instance = run
      instance.bind_execution_window(work_deadline: 105.0, cleanup_deadline: 115.0)
      engine.on_loot = true
      engine.routine = lambda do |guard|
        clock[0] = 105.0
        instance.request('stop')
        guard.checkpoint!
      end
      expect(engine).not_to receive(:quick_loot_restore)
      expect(instance.tick).to include(state: :stopped, reason: 'manual_stop')
    end

    it 'rejects malformed, expired and oversized cleanup windows' do
      [{ work_deadline: Float::NAN, cleanup_deadline: 110 },
       { work_deadline: 110, cleanup_deadline: Float::INFINITY },
       { work_deadline: 105, cleanup_deadline: 104 },
       { work_deadline: 80, cleanup_deadline: 90 },
       { work_deadline: 105, cleanup_deadline: 116 }].each do |window|
        expect(run.bind_execution_window(**window)).to be(false)
      end
    end

    it 'allows a cold cleanup longer than combat without changing the combat allowance' do
      settings.delete('loot_max_actions')
      settings['max_actions'] = 2
      snapshot[:loot_ids] = []
      engine.on_loot = true
      engine.routine = ->(guard) { 25.times { guard.transmit('look in #987') {} } }
      expect(engine).not_to receive(:quick_loot_restore)
      expect(run.tick).to include(state: :running, loot_sends: 26)
      expect(run.tick).to include(state: :completed, reason: 'room_clear', loot_sends: 26)
      expect(run.status[:limits]).to include(max_actions: 2)
    end

    it 'uses a bounded restoration-only reserve after the work budget and terminates truthfully' do
      engine.on_loot = true
      engine.routine = ->(guard) { 20.times { guard.transmit('skin #123') {} } }
      expect(engine).to receive(:quick_loot_restore) do |guard:, **|
        guard.transmit('put #789 in #987') {}
        guard.transmit('stand') {}
        { outcome: :complete }
      end
      expect(run.tick).to include(state: :stopped, reason: 'command_limit', loot_sends: 12,
                                  loot_recovery: { outcome: :complete, sends: 2 })
    end

    it 'rechecks a queued stop before allowing a recovery command' do
      instance = run
      allow(engine).to receive(:quick_loot_execute) do |guard:, **|
        instance.request('stop')
        guard.interrupt!('command_limit')
      end
      restored = []
      allow(engine).to receive(:quick_loot_restore) do |guard:, **|
        guard.transmit('stand') { restored << true }
      end
      expect(instance.tick).to include(state: :stopped)
      expect(restored).to be_empty
      expect(instance.status[:loot_recovery]).to include(outcome: :unconfirmed, sends: 0)
    end

    it 'never attempts recovery for a direct safety or permission interruption' do
      allow(engine).to receive(:quick_loot_execute) { raise BigshotQuickRunSpec::QuickGuard::Interrupted, 'permission_revoked' }
      expect(engine).not_to receive(:quick_loot_restore)
      expect(run.tick).to include(state: :held, reason: 'permission_revoked')
    end

    [%w[assist ignore], %w[watch group]].each do |mode, unknown|
      %i[unverified replaced].each do |change|
        it "revokes #{mode}/#{unknown} loot before the next send when group membership is #{change}" do
          settings.merge!('mode' => mode, 'unknown' => unknown)
          snapshot[:members_verified] = true
          snapshot[:member_records] = [{ id: '77', name: 'Friend' }]
          engine.on_loot = true
          engine.routine = lambda do |guard|
            if change == :unverified
              snapshot[:members_verified] = false
            else
              # Names remain equal; exact native member IDs must still match.
              snapshot[:member_records] = [{ id: '88', name: 'Friend' }]
            end
            guard.transmit('search #123') { engine.sends << 'unexpected search' }
          end
          expect(engine).not_to receive(:quick_loot_restore)
          expect(run.tick).to include(state: :held, reason: 'group_membership_unverified', loot_sends: 1)
          expect(engine.sends).to eq(['loot #123'])
        end
      end
    end

    it 'does not allow budget recovery to bypass a changed group roster' do
      settings['mode'] = 'assist'
      snapshot[:members_verified] = true
      snapshot[:member_records] = [{ id: '77', name: 'Friend' }]
      engine.on_loot = true
      engine.routine = ->(guard) { guard.interrupt!('command_limit') }
      attempted = []
      allow(engine).to receive(:quick_loot_restore) do |guard:, **|
        snapshot[:member_records] = [{ id: '88', name: 'Friend' }]
        guard.transmit('stand') { attempted << true }
      end
      expect(run.tick).to include(state: :held, reason: 'group_membership_unverified', loot_sends: 1,
                                  loot_recovery: { outcome: :unconfirmed, sends: 0 })
      expect(attempted).to be_empty
    end

    it 'does not require group membership for ordinary solo room cleanup' do
      snapshot[:members_verified] = false
      engine.on_loot = true
      engine.routine = ->(guard) { guard.transmit('search #123') { engine.sends << 'search #123' } }
      expect(run.tick).to include(state: :running, loot_sends: 2)
      expect(engine.sends).to eq(['loot #123', 'search #123'])
    end

    it 'allows an ordinary hostile arrival during a group pass with the same verified roster' do
      settings['mode'] = 'assist'
      snapshot[:members_verified] = true
      snapshot[:member_records] = [{ id: '77', name: 'Friend' }]
      engine.on_loot = true
      engine.routine = lambda do |guard|
        snapshot[:targets] = [target]
        guard.transmit('search #123') { engine.sends << 'search #123' }
      end
      expect(run.tick).to include(state: :running, loot_sends: 2)
      expect(engine.sends).to eq(['loot #123', 'search #123'])
    end

    it 'preserves an explicit stop when group invalidation happens at the same checkpoint' do
      settings['mode'] = 'assist'
      snapshot[:members_verified] = true
      instance = run
      engine.on_loot = true
      engine.routine = lambda do |guard|
        snapshot[:members_verified] = false
        instance.request('stop')
        guard.checkpoint!
      end
      expect(instance.tick).to include(state: :stopped, reason: 'manual_stop', loot_sends: 1)
      expect(engine.sends).to eq(['loot #123'])
    end

    it 'caps recovery retries at twelve sends rather than renewing the work budget' do
      allow(engine).to receive(:quick_loot_execute) { raise BigshotQuickRunSpec::QuickGuard::Interrupted, 'command_limit' }
      allow(engine).to receive(:quick_loot_restore) do |guard:, **|
        20.times { guard.transmit('stand') {} }
      end
      expect(run.tick).to include(state: :stopped, reason: 'command_limit', loot_sends: 12,
                                  loot_recovery: { outcome: :unconfirmed, sends: 12 })
    end

    it 'rejects recovery after its ten-second allowance' do
      allow(engine).to receive(:quick_loot_execute) { raise BigshotQuickRunSpec::QuickGuard::Interrupted, 'time_limit' }
      attempted = []
      allow(engine).to receive(:quick_loot_restore) do |guard:, **|
        clock[0] += 10
        guard.transmit('stand') { attempted << true }
      end
      expect(run.tick).to include(state: :stopped, reason: 'time_limit', loot_sends: 0,
                                  loot_recovery: { outcome: :unconfirmed, sends: 0 })
      expect(attempted).to be_empty
    end

    it 'finishes clear only after bounded corpse and room sends, without calling the attack engine' do
      expect(run.tick).to include(state: :running, loot_sends: 1)
      expect(run.tick).to include(state: :running, loot_sends: 2)
      expect(run.tick).to include(state: :completed, reason: 'room_clear', loot_sends: 2)
      expect(engine.sends).to eq(['loot #123', 'loot room'])
      expect(engine.calls).to be_empty
    end

    it 'holds and accounts the emitted loot command when hold arrives during the helper' do
      instance = run
      engine.on_loot = true
      engine.routine = ->(guard) { instance.request('hold'); guard.checkpoint! }
      expect(instance.tick).to include(state: :held, reason: 'manual_hold', loot_sends: 1)
      expect(engine.sends).to eq(['loot #123'])
    end

    it 'preempts cleanup with deferred retreat outside the native scope' do
      instance = run
      engine.on_loot = true
      engine.routine = ->(guard) { instance.request('retreat'); guard.checkpoint! }
      expect(instance.tick).to include(state: :stopped, reason: 'retreated', loot_sends: 1)
      expect(retreat_calls).to eq([false])
      expect(engine.sends).to eq(['loot #123'])
    end

    it 'finishes the admitted loot pass and equipment restoration before fighting an arriving hostile' do
      engine.on_loot = true
      engine.routine = lambda do |guard|
        guard.transmit('_drag #789 left') { engine.sends << '_drag #789 left' }
        snapshot[:targets] = [target]
        guard.checkpoint!
        guard.transmit('_drag #789 #987') { engine.sends << '_drag #789 #987' }
      end
      expect(run.tick).to include(state: :running, loot_sends: 3)
      expect(engine.sends).to eq(['loot #123', '_drag #789 left', '_drag #789 #987'])
      engine.on_loot = false
      engine.routine = ->(guard) { guard.transmit('attack #123') { engine.sends << 'attack #123' } }
      expect(run.tick).to include(state: :running, loot_sends: 3, sends: 1)
      expect(engine.sends).to eq(['loot #123', '_drag #789 left', '_drag #789 #987', 'attack #123'])
    end

    it 'does not turn a simultaneous safety failure and hostile arrival into a combat retry' do
      engine.on_loot = true
      engine.routine = lambda do |guard|
        snapshot[:targets] = [target]
        snapshot[:safe] = false
        snapshot[:safety_reason] = 'wounded'
        guard.checkpoint!
      end
      expect(run.tick).to include(state: :held, reason: 'wounded', loot_sends: 1)
      expect(engine.sends).to eq(['loot #123'])
    end

    it 'does not overwrite session loss with cleanup or retreat completion' do
      instance = run
      engine.on_loot = true
      engine.routine = ->(guard) { snapshot[:session] = 'new-login'; guard.checkpoint! }
      expect(instance.tick).to include(state: :stopped, reason: 'session_changed', loot_sends: 1)
      expect(engine.sends).to eq(['loot #123'])
    end

    it 'does not loot during trials, even when the named sequence target disappears' do
      settings['mode'] = 'trial'
      expect(run.tick).to include(state: :stopped, reason: 'target_unavailable', loot_sends: 0)
      expect(engine.sends).to be_empty
    end
  end
end
