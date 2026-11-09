# frozen_string_literal: true

require_relative 'support/harness'

# LNet::Hook: which lines typed in the game client lnet takes, and what it
# does with them when lnet is or isn't running.
RSpec.describe 'lnet.lic client hook' do
  def command_for(line, lich_char: ';') = lnet::Hook.command_for(line, lich_char: lich_char, script_name: 'lnet')

  {
    ';chat hi'               => [:shortcut, 'chat hi'],
    ';,hi there'             => [:shortcut, 'chat hi there'],
    ";chat hi\n"             => [:shortcut, 'chat hi'],
    '<c>;chat hi'            => [:shortcut, 'chat hi'],
    ';reply ok'              => [:shortcut, 'reply ok'],
    ';who'                   => [:shortcut, 'who'],
    ';who General'           => [:shortcut, 'who General'],
    ';channels'              => [:shortcut, 'channels'],
    ';channel'               => [:shortcut, 'channel'],
    ';channels full'         => [:shortcut, 'channels full'],
    ';locate Bob'            => [:shortcut, 'locate Bob'],
    ';tune Help'             => [:shortcut, 'tune Help'],
    ';lnet'                  => [:script, ''],
    ';lnet help'             => [:script, 'help'],
    ';lnet  allow locate all' => [:script, 'allow locate all'],
    ';Bob:hi there'          => [:shortcut, 'chat ::Bob hi there'],
    ';Bob: hi'               => [:shortcut, 'chat ::Bob  hi'],
    ';GSIV:Bob hi'           => [:shortcut, 'chat ::GSIV:Bob hi'],
    ';gsiv:Bob:hi'           => [:shortcut, 'chat ::gsiv:Bob hi'],
    ';DR:Ann see you'        => [:shortcut, 'chat ::DR:Ann see you']
  }.each do |line, expected|
    it "takes #{line.inspect} as #{expected.inspect}" do
      expect(command_for(line)).to eq(expected)
    end
  end

  [';whois Bob', ';channelsearch', ';lnet-callbacks', ';lnetx', ';lnet2 go', ';chat', ';Chat hi', ';e echo 1', 'chat hi',
   'look', ';go2 town', ''].each do |line|
    it "leaves #{line.inspect} for Lich" do
      expect(command_for(line)).to be_nil
    end
  end

  it "treats Lich's command prefix literally, even when it is a regex character" do
    expect(command_for('.chat hi', lich_char: '.')).to eq([:shortcut, 'chat hi'])
    expect(command_for('xchat hi', lich_char: '.')).to be_nil
    expect(command_for('*lnet help', lich_char: '*')).to eq([:script, 'help'])
  end

  it 'takes nothing when the prefix is unknown' do
    expect(command_for(';chat hi', lich_char: nil)).to be_nil
  end

  describe 'the hook' do
    let(:hook) { lnet::Hook.build('lnet') }

    def through_hook(line) = LnetSpec.capture { @result = hook.call(line) }

    it 'hands the command to the running lnet and swallows the line' do
      buffer = []
      LnetSpec::Game.running_scripts = [LnetSpec::RunningScript.new('lnet', buffer)]
      through_hook(';chat hi')
      expect(@result).to be_nil
      expect(buffer).to eq(['chat hi'])
    end

    it 'passes every other line through untouched' do
      through_hook("look\n")
      expect(@result).to eq("look\n")
      expect(LnetSpec::Game.removed_hooks).to be_empty
    end

    it 'says lnet is not running, swallows a shortcut and removes itself' do
      out = through_hook(';who')
      expect(@result).to be_nil
      expect(out).to eq([[:respond, '--- Lich: lnet is not running']])
      expect(LnetSpec::Game.removed_hooks).to eq(['lnet'])
    end

    it 'lets an ;lnet command through when lnet is not running, so Lich starts it' do
      through_hook(';lnet password=x')
      expect(@result).to eq(';lnet password=x')
      expect(LnetSpec::Game.removed_hooks).to eq(['lnet'])
    end

    it 'removes itself and passes the line through if something goes wrong' do
      allow(lnet::Hook).to receive(:command_for).and_raise('boom')
      through_hook(';chat hi')
      expect(@result).to eq(';chat hi')
      expect(LnetSpec::Game.removed_hooks).to eq(['lnet'])
    end
  end
end
