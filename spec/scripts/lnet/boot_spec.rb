# frozen_string_literal: true

require 'delegate'
require_relative 'support/harness'

# Loading saved settings and starting lnet: LNet.load_settings,
# LNet.startup_arguments, and the lines at the end of lnet.lic that run it,
# booted in a sandbox with stand-ins for Lich's globals.
RSpec.describe 'lnet.lic settings and startup' do
  # Like Lich's SettingsProxy: wraps a saved Hash or Array and answers is_a?
  # for it, but is not one (so `case x when Hash` would not match it).
  class LnetSpec::SavedValue < SimpleDelegator
    def is_a?(klass) = __getobj__.is_a?(klass)
    alias kind_of? is_a?
    def dup = self.class.new(__getobj__) # like SettingsProxy: a copy shares the saved value
  end

  let(:char_settings) { {} }
  let(:settings) { {} }

  def load! = lnet.load_settings(char_settings, settings)

  describe 'LNet.load_settings' do
    it 'starts a new character with defaults kept in the saved settings' do
      load!
      expect(lnet.options).to be(char_settings['options'])
      expect(lnet.options).to eq('timestamps' => false, 'fam_window' => false, 'greeting' => true, 'friends' => [],
                                 'enemies' => [], 'ignore' => [], 'permission' => {})
      expect(lnet.alias).to be(settings['alias'])
      lnet.secret = 'pw'
      expect(char_settings['secret']).to eq(['pw'])
    end

    it 'keeps what the character already saved' do
      char_settings['options'] = { 'timestamps' => true, 'greeting' => false, 'friends' => ['Bob'], 'permission' => { 'locate' => 'all' } }
      char_settings['secret'] = ['pw']
      settings['alias'] = { 'GSIV:Jeril' => 'J' }
      load!
      expect(lnet.options).to include('timestamps' => true, 'greeting' => false, 'friends' => ['Bob'], 'permission' => { 'locate' => 'all' })
      expect(lnet.login_attributes['password']).to eq('pw')
      expect(lnet.alias).to eq('GSIV:Jeril' => 'J')
    end

    it 'keeps saved values Lich hands back wrapped, rather than replacing them' do
      options = LnetSpec::SavedValue.new({ 'friends' => LnetSpec::SavedValue.new(['Bob']), 'permission' => LnetSpec::SavedValue.new({ 'info' => 'all' }) })
      char_settings['options'] = options
      char_settings['secret'] = LnetSpec::SavedValue.new(['pw'])
      load!
      expect(lnet.options).to be(options)
      expect(lnet.options['friends']).to eq(['Bob'])
      expect(lnet.options['permission']).to eq('info' => 'all')
      expect(lnet.login_attributes['password']).to eq('pw')
    end

    it 'replaces values of the wrong kind' do
      char_settings['options'] = { 'friends' => 'Bob', 'enemies' => nil, 'ignore' => { 'x' => 1 }, 'permission' => ['all'] }
      char_settings['secret'] = 'pw'
      settings['alias'] = 'nope'
      load!
      expect(lnet.options).to include('friends' => [], 'enemies' => [], 'ignore' => [], 'permission' => {})
      expect(char_settings['secret']).to eq([])
      expect(lnet.alias).to eq({})
    end

    it 'replaces saved options that are not a hash' do
      char_settings['options'] = 'junk'
      load!
      expect(lnet.options).to include('greeting' => true)
    end

    it "imports a new character's options and password from old lnet's shared settings" do
      legacy_friends = ['Bob']
      settings['options'] = { 'timestamps' => true, 'friends' => legacy_friends, 'permission' => { 'locate' => 'friends' },
                              'Tester' => { 'password' => 'old-pw' } }
      load!
      expect(lnet.options).to include('timestamps' => true, 'friends' => ['Bob'], 'permission' => { 'locate' => 'friends' }, 'greeting' => true)
      expect(lnet.login_attributes['password']).to eq('old-pw')
      expect(settings['options']['Tester']['password']).to be_nil
      lnet.options['friends'] << 'Ann'
      expect(legacy_friends).to eq(['Bob'])
    end

    it 'imports plain copies that share nothing with the old shared settings, even from wrapped values' do
      legacy_friends = ['Bob']
      settings['options'] = LnetSpec::SavedValue.new({ 'friends' => LnetSpec::SavedValue.new(legacy_friends),
                                                       'permission' => LnetSpec::SavedValue.new({ 'locate' => 'all' }) })
      load!
      expect(lnet.options['friends']).to be_an_instance_of(Array)
      expect(lnet.options['permission']).to be_an_instance_of(Hash)
      lnet.options['friends'] << 'Ann'
      lnet::Commands.run('del friend bob')
      expect(legacy_friends).to eq(['Bob'])
      expect(lnet.options['friends']).to eq(['Ann'])
    end

    it 'imports nothing for a character that already has options' do
      char_settings['options'] = { 'greeting' => false }
      settings['options'] = { 'timestamps' => true, 'Tester' => { 'password' => 'old-pw' } }
      load!
      expect(lnet.options['timestamps']).to be(false)
      expect(settings['options']['Tester']['password']).to eq('old-pw')
    end

    [nil, 'junk', { 'Tester' => 'not a hash' }, { 'Tester' => { 'password' => nil } }].each do |legacy|
      it "copes with old shared settings of #{legacy.inspect}" do
        settings['options'] = legacy
        expect { load! }.not_to raise_error
        expect(lnet.login_attributes['password']).to be_nil
      end
    end
  end

  describe 'LNet.startup_arguments' do
    it 'saves a password to log in with, without sending anything' do
      lnet.server = LnetSpec::FakeServer.new
      command = :unset
      expect(LnetSpec.capture { command = lnet.startup_arguments('password=s3cret') }).to eq([[:echo, 'Password saved locally.']])
      expect(command).to be_nil
      expect(lnet.login_attributes['password']).to eq('s3cret')
      expect(lnet.server.lines).to be_empty
      expect(LnetSpec.capture { lnet.startup_arguments('PASSWORD=nil') }).to eq([[:echo, 'Password cleared.']])
      expect(lnet.login_attributes['password']).to be_nil
    end

    it 'saves a quoted password without the quotes Lich leaves on the argument string' do
      LnetSpec.capture { lnet.startup_arguments('password="s3cret"') }
      expect(lnet.login_attributes['password']).to eq('s3cret')
    end

    it 'returns anything else as the command to run' do
      expect(lnet.startup_arguments('  allow locate friends ')).to eq('allow locate friends')
    end

    [nil, '', '   '].each do |arguments|
      it "returns nothing for #{arguments.inspect}" do
        expect(lnet.startup_arguments(arguments)).to be_nil
      end
    end
  end

  describe 'LNet.wait_until_connected' do
    it 'returns at once when connected' do
      lnet.server = LnetSpec::FakeServer.new
      expect(lnet.wait_until_connected(5)).to be(true)
    end

    it 'gives up after the timeout' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(lnet.wait_until_connected(0.3)).to be(false)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be_between(0.3, 1)
    end
  end

  describe 'the end of lnet.lic' do
    LnetSpec::FakeScript = Struct.new(:name, :vars, :unique_buffer) unless defined?(LnetSpec::FakeScript)

    # Evaluates the LNet class and then the file's own closing lines in a
    # fresh module, with Lich's globals replaced by recorders.
    def boot(arguments: '', typed: [], scripts: [])
      calls = []
      script = LnetSpec::FakeScript.new('lnet', [arguments], [])
      sandbox = Module.new
      sandbox.const_set(:Script, Module.new.tap do |m|
        m.define_singleton_method(:current) { script }
        m.define_singleton_method(:exists?) { |name| scripts.include?(name) }
        m.define_singleton_method(:running?) { |_name| false }
        m.define_singleton_method(:start) { |name| calls << [:start, name] }
      end)
      sandbox.const_set(:CharSettings, {})
      sandbox.const_set(:Settings, {})
      sandbox.const_set(:XMLData, LnetSpec::Harness::XMLData)
      sandbox.const_set(:UpstreamHook, Module.new.tap do |m|
        m.define_singleton_method(:add) { |name, hook| calls << [:hook_added, name, hook.class] }
        m.define_singleton_method(:remove) { |name| calls << [:hook_removed, name] }
      end)
      sandbox.const_set(:Thread, Module.new.tap { |m| m.define_singleton_method(:new) { |&_block| calls << [:thread] } })
      %i[toggle_unique clear hide_me].each { |name| sandbox.define_singleton_method(name) { calls << [name] } }

      class_source = LnetSpec::SOURCE[/^class LNet\n.*?^end\n/m]
      boot_source = LnetSpec::SOURCE[(LnetSpec::SOURCE.index(class_source) + class_source.size)..]
      sandbox.module_eval(class_source, LnetSpec::SOURCE_PATH)
      lnet_class = sandbox.const_get(:LNet)
      LnetSpec.install_globals!(lnet_class)
      lines = typed.dup
      lnet_class.define_singleton_method(:before_dying) { |&block| calls << [:before_dying, block] }
      lnet_class.define_singleton_method(:unique_get) { script.unique_buffer.shift || lines.shift }
      lnet_class.define_singleton_method(:wait_until_connected) { |seconds| calls << [:waited, seconds] }
      run_command = lnet_class::Commands.method(:run)
      lnet_class::Commands.define_singleton_method(:run) { |line| calls << [:command, line]; run_command.call(line) }
      out = LnetSpec.capture { sandbox.module_eval(boot_source, LnetSpec::SOURCE_PATH) }
      { calls: calls, lnet: lnet_class, out: out, sandbox: sandbox }
    end

    it 'ends with nothing but the lines that start lnet' do
      class_source = LnetSpec::SOURCE[/^class LNet\n.*?^end\n/m]
      boot_source = LnetSpec::SOURCE[(LnetSpec::SOURCE.index(class_source) + class_source.size)..]
      expect(boot_source.strip.lines.map(&:strip)).to eq(%w[toggle_unique clear hide_me LNet.run(Script.current)])
    end

    it 'loads settings, takes over the client commands, starts both threads and runs commands until told to stop' do
      booted = boot(typed: ['allow locate friends', 'timestamps=on'])
      calls = booted[:calls]
      expect(calls.first(3)).to eq([[:toggle_unique], [:clear], [:hide_me]])
      expect(calls).to include([:hook_added, 'lnet', Proc])
      expect(calls.count([:thread])).to eq(2)
      expect(booted[:lnet].options).to include('permission' => { 'locate' => 'friends' }, 'timestamps' => true)
      expect(booted[:sandbox]::CharSettings['options']).to be(booted[:lnet].options)
      expect(booted[:lnet].script.name).to eq('lnet')
    end

    it 'runs a command it was started with that needs LNet only after starting the threads and waiting up to 30 seconds' do
      calls = boot(arguments: 'chat hello')[:calls]
      kinds = calls.map(&:first)
      waited = kinds.index(:waited)
      expect(waited).not_to be_nil
      expect(kinds.each_index.select { |i| kinds[i] == :thread }).to all(be < waited)
      expect(calls.index([:command, 'chat hello'])).to be > waited
      expect(calls).to include([:waited, 30])
    end

    it 'runs a command it was started with that only changes things here at once, without waiting' do
      booted = boot(arguments: 'add friend dr:bob')
      expect(booted[:calls].map(&:first)).not_to include(:waited)
      expect(booted[:calls]).to include([:command, 'add friend dr:bob'])
      expect(booted[:lnet].options['friends']).to eq(['DR:Bob'])
    end

    it 'says it is waiting for LNet before a command that needs it' do
      expect(boot(arguments: 'who')[:out]).to include([:echo, 'waiting for LNet to connect...'])
    end

    it 'does not wait when it was started without a command' do
      expect(boot[:calls].map(&:first)).not_to include(:waited)
    end

    it "starts the user's lnet-callbacks script when there is one" do
      expect(boot(scripts: ['lnet-callbacks'])[:calls]).to include([:start, 'lnet-callbacks'])
      expect(boot[:calls]).not_to include([:start, 'lnet-callbacks'])
    end

    it 'cleans up when the script dies: removes the hook, disconnects and forgets the script' do
      booted = boot
      socket = LnetSpec::FakeServer.new
      booted[:lnet].server = socket
      _, block = booted[:calls].find { |kind, _| kind == :before_dying }
      block.call
      expect(booted[:calls]).to include([:hook_removed, 'lnet'])
      expect(socket.closed?).to be(true)
      expect(booted[:lnet].script).to be_nil
    end
  end
end
