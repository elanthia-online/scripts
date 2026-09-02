# frozen_string_literal: true

require_relative '../spec_helper'
require 'ostruct'

RSpec.describe 'EBounty authoritative container scans' do
  let(:source_path) { find_lic_source('ebounty.lic', from: __dir__) }
  let(:source) { File.read(source_path) }

  def build_harness(source, source_path, open_result: 'That is already open.')
    item = Struct.new(:name).new('a ruby')
    container = Struct.new(:id, :name, :contents).new('201', 'a gem pouch', [])

    game_obj = Module.new
    game_obj.define_singleton_method(:containers) { { container.id => container } }

    task = Module.new
    task.singleton_class.attr_accessor :prepped
    task.prepped = false
    task.define_singleton_method(:prep) { |no_check:| self.prepped = no_check }

    hunting = Module.new
    hunting.singleton_class.attr_accessor :started
    hunting.started = false
    hunting.define_singleton_method(:go_hunting) { self.started = true }

    data = OpenStruct.new(
      close_containers: [],
      containers: [container],
      settings: { hording_script: '' },
      loot_script: 'none'
    )

    commands = []
    ebounty = Module.new
    ebounty.const_set(:EBounty, ebounty)
    ebounty.const_set(:GameObj, game_obj)
    ebounty.const_set(:Task, task)
    ebounty.const_set(:Hunting, hunting)
    ebounty.define_singleton_method(:data) { data }
    ebounty.define_singleton_method(:msg) { |*| nil }
    ebounty.define_singleton_method(:checkbounty) { 'You have been tasked with collecting gems.' }
    ebounty.define_singleton_method(:load_default_profile) { nil }
    ebounty.define_singleton_method(:get_command) do |command, *_args, **_kwargs|
      commands << command
      if command.start_with?('open ')
        [open_result]
      else
        container.contents = [item]
        ['<container id="201">']
      end
    end
    ebounty.module_eval(extract_lic_method(source, 'open_container', source_path: source_path))
    ebounty.module_eval(extract_lic_method(source, 'gem_bounty', source_path: source_path))

    [ebounty, container, commands, task, hunting]
  end

  it 'refreshes cached gem containers before deciding whether to hunt' do
    ebounty, _container, commands, task, hunting = build_harness(source, source_path)

    ebounty.gem_bounty('ruby', 1)

    expect(commands).to eq(['open #201', 'look in #201'])
    expect(task.prepped).to be true
    expect(hunting.started).to be false
  end

  it 'does not schedule an already-open container for closure after a forced scan' do
    ebounty, container, _commands, = build_harness(source, source_path)

    if ebounty.method(:open_container).parameters.any? { |_kind, name| name == :refresh }
      ebounty.open_container(container, refresh: true)
    else
      ebounty.open_container(container)
    end

    expect(ebounty.data.close_containers).to be_empty
  end

  it 'keeps the cached fast path for a non-authoritative open request' do
    ebounty, container, commands, = build_harness(source, source_path)

    ebounty.open_container(container)

    expect(commands).to be_empty
  end
end
