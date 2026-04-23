require 'tmpdir'
require 'fileutils'
require 'ostruct'

$login_time = Time.new(2026, 4, 23, 10, 0, 0)

module XMLData
  def self.game;       "GSIV";          end
  def self.name;       "TestChar";      end
  def self.room_id;    1234;            end
  def self.room_title; "[Town Square]"; end
end

module Lich
  def self.log(_msg); end
end

class Script
  def self.current
    @current ||= OpenStruct.new(
      want_script_output: nil,
      want_upstream: nil,
      vars: [""],
      downstream_buffer: [],
      name: "log"
    )
  end
end

def hide_me; end
def echo(_msg); end

$reget_lines = []
def reget
  $reget_lines
end

def get
  raise StopIteration
end

def upstream_get
  raise StopIteration
end

script_path = File.join(__dir__, '..', '..', 'scripts', 'log.lic')
script_content = File.read(script_path)
module_code = script_content[/^module GameLogger.*?^end/m]
eval(module_code, binding, script_path,
     script_content.lines.index { |l| l.start_with?('module GameLogger') } + 1)

RSpec.describe GameLogger do
  describe GameLogger::Opts do
    describe '.parse' do
      it 'parses --timestamp flag with value' do
        result = described_class.parse(['--timestamp=%F %T %Z'])
        expect(result.timestamp).to eq('%F %T %Z')
      end

      it 'parses --rnum as boolean flag' do
        result = described_class.parse(['--rnum'])
        expect(result.rnum).to be true
      end

      it 'parses --roomnum as boolean flag' do
        result = described_class.parse(['--roomnum'])
        expect(result.roomnum).to be true
      end

      it 'parses --exclude with comma-separated values' do
        result = described_class.parse(['--exclude=288,2300,u7199'])
        expect(result.exclude).to eq(%w[288 2300 u7199])
      end

      it 'parses --exclude with single value as string' do
        result = described_class.parse(['--exclude=288'])
        expect(result.exclude).to eq('288')
      end

      it 'parses --lines with numeric value' do
        result = described_class.parse(['--lines=50000'])
        expect(result.lines).to eq('50000')
      end

      it 'returns nil for unset options' do
        result = described_class.parse([])
        expect(result.timestamp).to be_nil
        expect(result.rnum).to be_nil
        expect(result.exclude).to be_nil
      end

      it 'parses multiple flags together' do
        result = described_class.parse(['--timestamp=%F %T', '--rnum', '--lines=10000'])
        expect(result.timestamp).to eq('%F %T')
        expect(result.rnum).to be true
        expect(result.lines).to eq('10000')
      end

      it 'parses positional commands as true' do
        result = described_class.parse(['something'])
        expect(result.something).to be true
      end
    end
  end

  describe '.main' do
    let(:log_dir) { Dir.mktmpdir }
    let(:frozen_time) { Time.new(2026, 4, 23, 10, 0, 5) }

    before do
      stub_const('LICH_DIR', log_dir)
      allow(Time).to receive(:now).and_return(frozen_time)
      $login_time = Time.new(2026, 4, 23, 10, 0, 0)
    end

    after do
      FileUtils.rm_rf(log_dir)
    end

    def run_main
      GameLogger.main
    end

    def find_log_file
      Dir.glob(File.join(log_dir, '**', '*.log')).first
    end

    def log_content
      File.read(find_log_file)
    end

    context 'with timestamps enabled' do
      before do
        GameLogger.instance_variable_set(:@options, OpenStruct.new(timestamp: '%F %T'))
      end

      it 'timestamps reget lines with $login_time' do
        $reget_lines = ['You see a door.', 'Obvious exits: north, south.']
        run_main
        expect(log_content).to include('2026-04-23 10:00:00: You see a door.')
        expect(log_content).to include('2026-04-23 10:00:00: Obvious exits: north, south.')
      end

      it 'filters pushStream tags from reget lines' do
        $reget_lines = ['<pushStream id="room"/>', 'You see a door.', '<popStream/>']
        run_main
        expect(log_content).not_to include('pushStream')
        expect(log_content).not_to include('popStream')
        expect(log_content).to include('2026-04-23 10:00:00: You see a door.')
      end

      it 'uses $login_time not current time for reget timestamps' do
        $login_time = Time.new(2026, 1, 1, 12, 30, 45)
        allow(Time).to receive(:now).and_return(Time.new(2026, 1, 1, 12, 30, 50))
        $reget_lines = ['Test line']
        run_main
        expect(log_content).to include('2026-01-01 12:30:45: Test line')
      end
    end

    context 'without timestamps' do
      before do
        GameLogger.instance_variable_set(:@options, OpenStruct.new)
      end

      it 'writes reget lines without timestamps' do
        $reget_lines = ['You see a door.']
        run_main
        door_line = log_content.lines.find { |l| l.include?('You see a door.') }
        expect(door_line).to start_with('You see a door.')
      end

      it 'still filters pushStream/popStream from reget' do
        $reget_lines = ['<pushStream id="room"/>', 'content line', '<popStream/>']
        run_main
        expect(log_content).not_to include('pushStream')
        expect(log_content).not_to include('popStream')
        expect(log_content).to include('content line')
      end
    end

    context 'when login was more than 30 seconds ago' do
      before do
        $login_time = frozen_time - 60
        GameLogger.instance_variable_set(:@options, OpenStruct.new(timestamp: '%F %T'))
      end

      it 'does not write reget lines' do
        $reget_lines = ['Should not appear']
        run_main
        expect(log_content).not_to include('Should not appear')
      end

      it 'does not write reget marker comment' do
        $reget_lines = ['ignored']
        run_main
        expect(log_content).not_to include('Above contents from reget')
      end
    end

    it 'writes reget marker comment when reget is used' do
      $login_time = frozen_time - 5
      $reget_lines = ['test']
      GameLogger.instance_variable_set(:@options, OpenStruct.new)
      run_main
      expect(log_content).to include('<!-- Above contents from reget; full logging now active -->')
    end

    it 'creates log directory with game and character name' do
      $reget_lines = []
      GameLogger.instance_variable_set(:@options, OpenStruct.new)
      run_main
      expect(find_log_file).to include('GSIV-TestChar')
    end

    it 'handles empty reget buffer' do
      $reget_lines = []
      GameLogger.instance_variable_set(:@options, OpenStruct.new(timestamp: '%F %T'))
      run_main
      expect(log_content).to include('<!-- Above contents from reget; full logging now active -->')
      expect(log_content.lines.count { |l| l.include?('2026-04-23 10:00:00:') }).to eq(0)
    end
  end
end
