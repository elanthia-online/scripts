# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'EHerbs authoritative container scans' do
  let(:source_path) { find_lic_source('eherbs.lic', from: __dir__) }
  let(:source) { File.read(source_path) }

  def build_harness(source, source_path)
    game_obj = Class.new do
      class << self
        attr_accessor :containers, :inv
      end

      attr_accessor :id, :contents

      def initialize(id, contents)
        @id = id
        @contents = contents
      end

      def empty? = false
    end

    container = game_obj.new('101', [])
    game_obj.containers = { container.id => container }
    game_obj.inv = [container]

    data = {
      herb_sack: nil,
      survival_kit: false,
      open_regex: /./,
      needs_closed: /never matches/,
      look_regex: /./,
      close_herbsack: false,
      drinkable: /potion/
    }

    eherbs = Module.new
    eherbs.define_singleton_method(:data) { data }
    eherbs.define_singleton_method(:known_herbs) { [] }

    commands = []
    utility = Module.new
    utility.define_singleton_method(:get_lines) do |command, _regex|
      commands << command
      command.start_with?('open ') ? ['That is already open.'] : ['In the sack you see an herb.']
    end
    utility.define_singleton_method(:determine_survival_kit) { |_container| nil }

    inventory = Module.new
    inventory.const_set(:GameObj, game_obj)
    inventory.const_set(:EHerbs, eherbs)
    inventory.const_set(:Utility, utility)
    inventory.const_set(:Inventory, inventory)
    inventory.module_eval(extract_lic_method(source, 'open_single_container', source_path: source_path))
    inventory.module_eval(extract_lic_method(source, 'herb_container_contents_load', source_path: source_path))

    [inventory, container, commands]
  end

  it 'refreshes a cached herb sack before an authoritative contents load' do
    inventory, container, commands = build_harness(source, source_path)

    inventory.herb_container_contents_load(container)

    expect(commands).to eq(['open #101', 'look in #101'])
  end

  it 'keeps the cached fast path for a non-authoritative open request' do
    inventory, container, commands = build_harness(source, source_path)

    inventory.open_single_container(container)

    expect(commands).to be_empty
  end
end
