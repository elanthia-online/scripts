require 'yaml'
require 'tmpdir'

module BigshotQuickRequestSpec
  SOURCE = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[QuickRequest EncounterSettings].each do |name|
    body = SOURCE[/^  class #{name}\n.*?^  end$/m]
    raise "#{name} source missing" unless body

    module_eval(body)
  end
end

RSpec.describe BigshotQuickRequestSpec::QuickRequest do
  it 'requires paired finite refuge deadlines and explicit profile area' do
    args = %w[clear --area profile --supervised-start-v1 100,110 --supervised-refuge-v1 900,130]
    request = described_class.parse(args)
    window = described_class.execution_window(request.options['supervised-start-v1'])
    expect(described_class.refuge_window(request.options['supervised-refuge-v1'], window)).to eq(room_id: 900, return_deadline: 130.0)
    %w[4,130 900,119 900,231 900,NaN 900,Infinity 0,130 900,130,140].each do |value|
      expect { described_class.parse(args[0...-1] + [value]) }.to raise_error(ArgumentError)
    end
    expect { described_class.parse(%w[clear --area profile --supervised-refuge-v1 900,130]) }.to raise_error(ArgumentError)
    expect { described_class.parse(%w[clear --supervised-start-v1 100,110 --supervised-refuge-v1 900,130]) }.to raise_error(ArgumentError)
    expect { described_class.parse(%w[clear --area profile --supervised-start-v1 100,100 --supervised-refuge-v1 900,130]) }.to raise_error(ArgumentError)
  end

  it 'accepts only a finite bounded private launch window without saving it in presets' do
    request = described_class.parse(%w[clear --supervised-start-v1 100.5,110.5])
    expect(described_class.execution_window(request.options['supervised-start-v1'])).to eq(work_deadline: 100.5, cleanup_deadline: 110.5)
    resolved = described_class.resolve(request, nil, { 'profile_current' => 'fixture' }, '/unused')
    expect(resolved[:settings]).not_to have_key('supervised-start-v1')
    %w[NaN,110 100,Infinity 100,111 110,100 100;look,110 100,110,120].each do |value|
      expect { described_class.parse(['clear', '--supervised-start-v1', value]) }.to raise_error(ArgumentError)
    end
    expect { described_class.parse(%w[clear --supervised-start-v1 100,110 --supervised-start-v1 100,110]) }.to raise_error(ArgumentError)
  end

  it 'opts into native profile boundaries without mutating the saved preset' do
    state = BigshotQuickRequestSpec::EncounterSettings.new
    request = described_class.parse(%w[watch --area profile])
    result = described_class.resolve(request, state.to_h, { 'profile_current' => 'fixture' }, '/unused')
    expect(result[:settings]['area']).to eq('profile')
    expect(state.preset['area']).to eq('off')
    expect { described_class.parse(%w[watch --area everywhere]) }.to raise_error(ArgumentError, /--area/)
    expect { described_class.parse(%w[watch --area profile --area off]) }.to raise_error(ArgumentError, /Duplicate/)
  end
  it 'preserves only the documented exact legacy forms' do
    [[], ['once'], ['single'], ['ONCE']].each do |args|
      expect(described_class.parse(args)).to be_legacy
    end
    [%w[clera], %w[once extra], %w[single --profile invasion], %w[solo], %w[giant rat]].each do |args|
      expect { described_class.parse(args) }.to raise_error(ArgumentError)
    end
  end

  it 'parses run options without changing or retaining mutable caller strings' do
    args = %w[assist --preset invasion --leader FriendName --profile temple]
    request = described_class.parse(args)
    args.last.replace('changed')
    expect(request.command).to eq('assist')
    expect(request.options).to eq('preset' => 'invasion', 'leader' => 'FriendName', 'profile' => 'temple')
    expect(request).not_to be_legacy
    expect { request.options['profile'].replace('changed') }.to raise_error(FrozenError)
    expect { request.options['leader'] = 'Someone' }.to raise_error(FrozenError)
  end

  it 'accepts explicit controls and rejects their extra arguments' do
    described_class::CONTROL_COMMANDS.each do |command|
      expect(described_class.parse([command]).command).to eq(command)
      expect { described_class.parse([command, '--preset', 'invasion']) }.to raise_error(ArgumentError)
    end
  end

  it 'rejects unknown, duplicate, missing and contradictory run options' do
    [%w[clear --typo yes], %w[watch --profile], %w[clear --profile --preset x],
     %w[clear --profile a --profile b], %w[clear extra], %w[assist --trigger stranger],
     %w[assist --leader Friend --trigger any-group], %w[watch --leader Friend],
     %w[clear --target 1], %w[trial], %w[trial --target 1], %w[trial opening],
     %w[trial opening --target 0], %w[trial opening --target 1;look]].each do |args|
      expect { described_class.parse(args) }.to raise_error(ArgumentError)
    end
  end

  it 'requires an explicit positive trial target and accepts the # prefix' do
    expect(described_class.parse(%w[trial opening --target #123]).options).to eq('trial' => 'opening', 'target' => '123')
  end

  it 'parses exact manual engagement without interpreting names or command blocks' do
    expect(described_class.parse(%w[engage #123]).options).to eq('target' => '123')
    [[], ['0'], ['rat'], ['123', 'attack'], ["123\nlook"]].each do |args|
      expect { described_class.parse(['engage', *args]) }.to raise_error(ArgumentError)
    end
  end

  it 'resolves current-profile overrides without changing stored presets or normal selection' do
    state = BigshotQuickRequestSpec::EncounterSettings.new
    state.save('invasion', 'unknown' => 'group', 'fallback_commands' => 'jab target', 'trigger' => 'any-group')
    stored = state.to_h
    current = { 'profile_current' => 'ordinary', 'boons_ignore' => ['ethereal'] }
    result = described_class.resolve(described_class.parse(%w[assist --preset invasion --leader Friend]), stored, current, '/unused')
    expect(result[:settings]).to include('mode' => 'assist', 'unknown' => 'group', 'trigger' => 'leader', 'leader' => 'Friend')
    expect(result[:profile]).to eq(current)
    expect(result[:trial]).to be_nil
    expect(result[:report_metadata]).to eq(preset: 'invasion', profile: 'ordinary', sequence: nil)
    expect { result[:report_metadata][:profile].replace('changed') }.to raise_error(FrozenError)
    expect(stored).to eq(state.to_h)
    expect(current['profile_current']).to eq('ordinary')
    expect { result[:profile]['boons_ignore'] << 'regen' }.to raise_error(FrozenError)
    expect { result[:settings]['leader'].replace('Changed') }.to raise_error(FrozenError)
  end

  it 'reads the explicitly requested profile independently of the preset reference' do
    Dir.mktmpdir('bigshot-quick-request') do |directory|
      File.write(File.join(directory, 'temple.yaml'), { 'targets' => 'spider' }.to_yaml)
      request = described_class.parse(%w[clear --profile temple])
      result = described_class.resolve(request, nil, { 'targets' => 'rat' }, directory)
      expect(result[:profile]).to eq('targets' => 'spider')
      expect(result[:report_metadata][:profile]).to eq('temple')
      expect { described_class.resolve(described_class.parse(%w[clear --profile ../temple]), nil, {}, directory) }.to raise_error(ArgumentError, /path/)
    end
  end

  it 'resolves named trial actions and validates bounded overrides' do
    stored = BigshotQuickRequestSpec::EncounterSettings.new.to_h
    stored['trials']['opening'] = { 'actions' => ['jab target', 'grapple target'], 'max_actions' => 3, 'max_seconds' => 20 }
    request = described_class.parse(%w[trial opening --target 123])
    result = described_class.resolve(request, stored, {}, '/unused')
    expect(result[:trial]).to eq(target_id: '123', actions: ['jab target', 'grapple target'])
    expect(result[:settings]).to include('mode' => 'trial', 'max_actions' => 3, 'max_seconds' => 20)
    expect(result[:report_metadata]).to include(sequence: 'opening', profile: nil)
    expect { result[:trial][:actions].first.replace('kick target') }.to raise_error(FrozenError)
    stored['trials']['opening']['max_seconds'] = 0
    expect { described_class.resolve(request, stored, {}, '/unused') }.to raise_error(ArgumentError, /positive/)
  end

  it 'rejects missing or malformed trials without falling back to regular combat' do
    request = described_class.parse(%w[trial missing --target 1])
    expect { described_class.resolve(request, nil, {}, '/unused') }.to raise_error(ArgumentError, /Unknown quick trial/)
    [[], { 'actions' => [] }, { 'actions' => [''] }, { 'actions' => ['jab target'], 'repeat' => true }].each do |sequence|
      state = { 'trials' => { 'missing' => sequence } }
      expect { described_class.resolve(request, state, {}, '/unused') }.to raise_error(ArgumentError)
    end
  end

  it 'uses the saved trial normalization contract without mutating stored commands' do
    request = described_class.parse(%w[trial opening --target 1])
    sequence = { 'actions' => ['  jab target  '], 'max_actions' => '2' }
    state = { 'trials' => { 'opening' => sequence } }
    result = described_class.resolve(request, state, {}, '/unused')
    expect(result[:trial][:actions]).to eq(['jab target'])
    expect(result[:settings]['max_actions']).to eq(2)
    expect(sequence).to eq('actions' => ['  jab target  '], 'max_actions' => '2')
    ["jab target\n", "jab target\r", "jab target\x00"].each do |command|
      sequence['actions'] = [command]
      expect { described_class.resolve(request, state, {}, '/unused') }.to raise_error(ArgumentError, /one command per line/)
    end
  end

  it 'does not resolve control or legacy requests into a combat run' do
    [[], ['status']].each do |args|
      expect { described_class.resolve(described_class.parse(args), nil, {}, '/unused') }.to raise_error(ArgumentError, /run request/)
    end
  end
end
