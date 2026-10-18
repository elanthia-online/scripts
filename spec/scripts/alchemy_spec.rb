# frozen_string_literal: true

require_relative '../spec_helper'

# alchemy.lic runs as a top-level script, so its where_is proc (which decides
# whether the nearest guild is within max-travel-time) is extracted verbatim
# and evaluated against lich-5's real map code from the local or CI-pinned
# checkout (see load_lich5_map in spec_helper.rb). Skipped without one.
#
# Graph (timeto in seconds), numbered densely from 0 because where_is walks
# every entry of Map.list and the list is indexed by room id:
#   0 -12-> 1 (guild) -1-> 2     0 -3.5 (StringProc)-> 3 (guild)
#   1 -12-> 0                    4 (guild) is not connected to anything
module AlchemySpec
  SOURCE_PATH = find_lic_source('alchemy.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH)
  WHERE_IS = extract_from_source(SOURCE, /^where_is_previous_var = nil\n.*?^where_is = proc \{.*?^\}\n/m,
                                 label: 'where_is', source_path: SOURCE_PATH)

  module Sandbox; end
  MAP = load_lich5_map(Sandbox)

  if MAP
    string_proc = Sandbox::Lich::Common::StringProc
    add_room = lambda do |id, wayto, timeto, tags = []|
      MAP.new(id, ["[Room #{id}]"], ["Room #{id}."], ['Obvious paths: none.'], [], nil, nil, nil, wayto, timeto, nil, nil, tags)
    end
    add_room.call(0, { '1' => 'east', '3' => 'climb ladder' }, { '1' => 12.0, '3' => string_proc.new('3.5') })
    add_room.call(1, { '2' => 'east', '0' => 'west' }, { '2' => 1.0, '0' => 12.0 }, ['guild herb'])
    add_room.call(2, {}, {}, ['guild herb'])
    add_room.call(3, {}, {})
    add_room.call(4, {}, {})
  end
end

RSpec.describe 'alchemy guild travel time check' do
  let(:map) { AlchemySpec::MAP }
  let(:settings) { { 'max-travel-time' => max_travel_time } }
  let(:messages) { [] }

  before do
    skip 'needs a lich-5 checkout (LICH5_PATH or a sibling ../lich-5)' unless map

    stub_const('Room', map)
    stub_const('Map', map)
    stub_const('CharSettings', settings)
    stub_const('Char', Struct.new(:prof).new('Empath'))
    allow(map).to receive(:current).and_return(map[0])
  end

  # Runs the real where_is for one place, with the nearest guild at
  # guild_id, and reports what alchemy decided about that guild.
  def check_guild(guild_id, place: 'guild herb')
    allow(map[0]).to receive(:find_nearest_by_tag).with('empath alchemy administrator').and_return(guild_id)
    log = messages
    scope = Object.new
    scope.define_singleton_method(:echo) { |message| log << message }
    where_is, state = scope.instance_eval("#{AlchemySpec::WHERE_IS}\n[where_is, binding]", AlchemySpec::SOURCE_PATH)
    rooms = where_is.call(place)
    { accepted: state.local_variable_get(:where_is_previous_var) != false, rooms: rooms, messages: messages }
  end

  context 'with max-travel-time 10' do
    let(:max_travel_time) { 10 }

    it 'turns down an adjacent guild 12 seconds away' do
      result = check_guild(1)
      expect(result[:accepted]).to be(false)
      expect(result[:rooms]).to eq([])
      expect(result[:messages]).to eq(['warning: nearest guild exceeds max travel time'])
    end

    it 'accepts a guild behind a 3.5 second StringProc edge' do
      expect(check_guild(3)[:accepted]).to be(true)
    end

    it 'reports a guild with no path instead of raising' do
      result = check_guild(4)
      expect(result[:accepted]).to be(false)
      expect(result[:messages]).to eq(['warning: failed to find a path to your guild'])
    end
  end

  context 'with max-travel-time 12' do
    let(:max_travel_time) { 12 }

    it 'accepts a guild exactly at the limit and lists places from it' do
      result = check_guild(1)
      expect(result[:accepted]).to be(true)
      expect(result[:messages]).to eq([])
      # 1 itself (0 s from the guild) and 2 (1 s) are both in range.
      expect(result[:rooms]).to eq([1, 2])
    end
  end

  context 'when standing in the guild' do
    let(:max_travel_time) { 0 }

    it 'accepts it without estimating anything' do
      allow(map[0]).to receive(:path_to).and_raise('path_to should not be called')
      expect(check_guild(0, place: 'none')[:accepted]).to be(true)
    end
  end

  context 'with the path_to of Lich before 5.14, which also leaves out the destination' do
    let(:max_travel_time) { 10 }

    it 'still counts the edge into an adjacent guild' do
      allow(map[0]).to receive(:path_to).with(1).and_return([])
      expect(check_guild(1)[:accepted]).to be(false)
    end
  end
end
