# frozen_string_literal: true

module BigshotQuickRetreatObservationSpec
  class Harness
    attr_accessor :targets, :is_dead, :pcs

    def initialize
      @targets, @pcs, @ALWAYS_FLEE_FROM = [], [], []
    end

    def bs_targets = targets
    def dead? = !!is_dead
    def dead_or_gone?(target) = target.dead
    def creature_backed?(target) = !target.creature.nil?
    def checkpcs = pcs
  end
  source = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  %w[quick_retreat_observation quick_environment_reason].each do |name|
    body = source[/^  def #{name}(?:\([^\n]*\))?\n.*?^  end$/m]
    raise "could not extract #{name}" unless body

    Harness.class_eval(body)
  end
end

RSpec.describe 'Quick pure retreat destination observation' do
  let(:engine) { BigshotQuickRetreatObservationSpec::Harness.new }
  let(:owner) { Object.new }
  let(:room) { double(id: 200) }
  let(:xml) { double(room_count: 2, game: 'GS4') }
  let(:character) { double(name: 'Tester', health: 30, spirit: 5) }
  let(:objects) { double(loot: [], npcs: []) }

  before do
    harness = 'BigshotQuickRetreatObservationSpec::Harness'
    stub_const("#{harness}::XMLData", xml)
    stub_const("#{harness}::Char", character)
    stub_const("#{harness}::Room", double(current: room))
    stub_const("#{harness}::Script", double(list: [owner]))
    stub_const("#{harness}::Game", double(closed?: false))
    stub_const("#{harness}::GameObj", objects)
  end

  def observe
    engine.quick_retreat_observation(session: 'run', owner: owner)
  end

  it 'accepts a stable empty refuge without asking whether wounds or mana permit combat' do
    # These settings deliberately cannot be evaluated by the pure observer.
    engine.instance_variable_set(:@WOUNDED_EVAL, "raise 'must not evaluate wounds'")
    expect(observe).to include(session: 'run:GS4:Tester', room_id: 200, room_epoch: 2,
                               alive: true, stable: true, destination_safe: true)
  end

  it 'requires health, spirit and the native death observation to indicate survival' do
    allow(character).to receive(:health).and_return(0)
    expect(observe).to include(alive: false, destination_safe: false)
    allow(character).to receive(:health).and_return(30)
    allow(character).to receive(:spirit).and_return(0)
    expect(observe).to include(alive: false, destination_safe: false)
    allow(character).to receive(:spirit).and_return(5)
    engine.is_dead = true
    expect(observe).to include(alive: false, destination_safe: false)
  end

  it 'rejects any live native hostile, even one excluded from attacking' do
    creature = double(crtr_flag?: true)
    target = Struct.new(:creature, :dead).new(creature, false)
    engine.targets << target
    expect(observe[:destination_safe]).to be(false)
    target.dead = true
    expect(observe[:destination_safe]).to be(true)
  end

  it 'preserves configured environmental and named flee checks for refuge proof' do
    engine.instance_variable_set(:@FLEE_CLOUDS, true)
    allow(objects).to receive(:loot).and_return([double(noun: 'cloud', name: 'poison cloud')])
    expect(observe[:destination_safe]).to be(false)
    allow(objects).to receive(:loot).and_return([])
    engine.instance_variable_set(:@ALWAYS_FLEE_FROM, ['Danger'])
    engine.pcs = ['Danger']
    expect(observe[:destination_safe]).to be(false)
  end

  it 'rejects changing, missing or placeholder mapped rooms' do
    allow(xml).to receive(:room_count).and_return(2, 3)
    expect(observe).to include(stable: false, destination_safe: false)
    allow(xml).to receive(:room_count).and_return(3)
    [nil, 4].each do |id|
      allow(room).to receive(:id).and_return(id)
      expect(observe).to include(stable: false, destination_safe: false)
    end
  end
end
