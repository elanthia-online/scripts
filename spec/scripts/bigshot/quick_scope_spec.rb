# frozen_string_literal: true

module BigshotQuickScopeSpec
  SOURCE = File.read(File.expand_path('../../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  class Harness
    attr_accessor :live, :gone

    def initialize(guard, target)
      @quick_native_scope = true
      @quick_guard = guard
      @quick_target = target
      @live = true
      @gone = false
    end

    def dead_or_gone?(_) = @gone
    def still_targetable?(_) = @live
  end
  %w[valid_target? should_flee? should_rest? run_script escape_rooms].each do |method|
    body = SOURCE[/^  def #{Regexp.escape(method)}(?:\([^\n]*\))?\n.*?^  end$/m]
    raise "Missing method #{method}" unless body
    Harness.class_eval(body)
  end
end

RSpec.describe 'Bigshot Quick command scope' do
  let(:guard) { double('guard', checkpoint!: true) }
  let(:target) { Struct.new(:id).new('123') }
  let(:engine) { BigshotQuickScopeSpec::Harness.new(guard, target) }

  it 'revalidates only the admitted exact target without probing or writing saved settings' do
    expect(engine.valid_target?(target)).to be(true)
    expect(engine.valid_target?(Struct.new(:id).new('124'))).to be(false)
    engine.live = false
    expect(engine.valid_target?(target)).to be(false)
    engine.live = true
    engine.gone = true
    expect(engine.valid_target?(target)).to be(false)
    expect(guard).to have_received(:checkpoint!).exactly(4).times
  end

  it 'uses guard safety instead of entering hunt rest, loot or group-reassembly checks' do
    expect(engine.should_rest?).to be(false)
    expect(engine.should_flee?).to be(false)
    expect(guard).to have_received(:checkpoint!).twice
    allow(guard).to receive(:checkpoint!).and_raise('held')
    expect { engine.should_rest? }.to raise_error('held')
    expect { engine.should_flee? }.to raise_error('held')
  end

  it 'leaves escape ownership outside the target command scope' do
    expect(engine.escape_rooms).to be_nil
    expect(guard).to have_received(:checkpoint!)
  end

  it 'rejects an unowned child before stopping or starting any script' do
    expect(guard).to receive(:interrupt!).with('child_script_unowned').and_raise('child unowned')
    expect { engine.run_script('loot', true) }.to raise_error('child unowned')
  end
end
