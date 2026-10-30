# frozen_string_literal: true

require_relative '../../spec_helper'

# The game sends no contents updates for a disk, so a cached disk listing still holds
# boxes that were looted and trashed since. Replays a reported log: a new eloot run
# found two already-trashed boxes in the cached disk contents, then tried to open them.
RSpec.describe 'ELoot disk contents' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(eloot_path) }

  let(:obj) { Struct.new(:id, :name, :type, :contents) }
  # An unopened box's contents are nil; under Lich's NilClass patch nil.empty? is nil,
  # which find_boxes relies on to keep it. Stand in for that without the patch.
  let(:unopened) { Object.new.tap { |o| o.define_singleton_method(:empty?) { nil } } }
  let(:trashed_box) { obj.new('930093113', 'weathered thanot box', 'box', unopened) }
  let(:live_box) { obj.new('930099999', 'iron box', 'box', unopened) }
  # disk contents as cached from an earlier look in, replaced by the next look in
  let(:disk) { obj.new('929117520', 'Widmer disk', nil, [trashed_box]) }
  let(:fresh_disk_contents) { [live_box] }
  let(:commands) { [] }

  let(:eloot) do
    disk = self.disk
    fresh = fresh_disk_contents
    commands = self.commands
    data = Struct.new(:settings, :disk, :look_regex).new({ use_disk: true }, disk, /In the/)
    trashed_id = trashed_box.id

    Module.new do
      define_singleton_method(:data) { data }
      define_singleton_method(:msg) { |**| nil }
      define_singleton_method(:wait_rt) { nil }
      define_singleton_method(:wait_for_disk) { nil }
      define_singleton_method(:set_selling_containers) { |**| [] }
      define_singleton_method(:get_command) do |command, *, **|
        commands << command
        if command == "look in ##{disk.id}"
          disk.contents = fresh
          ['<container ...>']
        elsif command == "look in ##{trashed_id}"
          ['I could not find what you were referring to.']
        else
          ['That is closed.']
        end
      end
    end
  end

  before do
    stub_const('ELoot', eloot)
    stub_const('Inventory', Module.new)
    eloot.module_eval(%w[fresh_contents disk_contents find_boxes].map { |m| extract_lic_method(source, m, source_path: eloot_path) }.join("\n"))
  end

  it 'looks in the disk fresh instead of trusting the cached contents' do
    expect(eloot.disk_contents).to eq([live_box])
    expect(commands).to include('look in #929117520')
  end

  it 'returns no contents without a disk' do
    eloot.data.disk = nil
    expect(eloot.disk_contents).to eq([])
  end

  it 'finds only the boxes still in the disk' do
    expect(eloot.find_boxes).to eq([live_box])
  end

  context 'when a box is gone by the time it is looked in' do
    let(:fresh_disk_contents) { [trashed_box, live_box] }

    it 'drops it instead of handing it to the locksmith' do
      expect(eloot.find_boxes).to eq([live_box])
    end
  end
end
