# frozen_string_literal: true

require_relative '../spec_helper'

# Exercise go2's actual option parser and auxiliary-script handling, without
# connecting to a game or substituting a different navigation implementation.
RSpec.describe 'go2 one-trip auxiliary-script preservation' do
  let(:source) { File.read(ENV.fetch('GO2_SOURCE') { File.expand_path('../../scripts/go2.lic', __dir__) }) }
  let(:settings) { {} }

  before do
    stub_const('CharSettings', settings)
    stub_const('XMLData', double(game: 'GSIV'))
    stub_const('Script', Class.new)
    allow(Script).to receive(:running?).and_return(true)
  end

  def parse(arguments)
    allow(Script).to receive(:current).and_return(double(vars: ['go2', *arguments]))
    parser = source[/^  target_search_array\s+=.*?^  target_search_string = target_search_array.join\(' '\)/m]
    raise 'go2 option parser missing' unless parser

    Object.new.instance_eval("setting_value = {'on' => true, 'off' => false}\n#{parser}\n[target_search_string, defined?(setting_preserve_scripts) ? setting_preserve_scripts : false]")
  end

  def auxiliary_actions(preserve)
    handler = source[/^    if !setting_preserve_scripts && Script.running\?\('roomnumbers'\).*?(?=^    if XMLData.game)/m]
    raise 'go2 auxiliary-script block missing' unless handler

    stub_const('Room', Class.new)
    allow(Room).to receive(:current).and_return(double(id: 100))
    allow(Room).to receive(:[]).with(100).and_return(double(tags: ['peer']))
    allow(Room).to receive(:[]).with(101).and_return(double(tags: ['ordinary']))
    actions = []
    scope = Object.new
    scope.define_singleton_method(:stop_script) { |name| actions << [:stop, name] }
    scope.define_singleton_method(:start_script) { |name| actions << [:start, name] }
    scope.define_singleton_method(:before_dying) { |&callback| callback.call }
    scope.instance_eval("setting_preserve_scripts = #{preserve}; path = [101]; est_time = 10\n#{handler}")
    actions
  end

  it 'parses the one-trip flag without saving settings or changing the target' do
    expect(parse(['132', '--preserve-scripts'])).to eq(['132', true])
    expect(settings).to eq({})
  end

  it 'defaults to existing auxiliary handling' do
    expect(parse(['132'])).to eq(['132', false])
    expect(auxiliary_actions(false)).to eq([
                                             [:stop, 'roomnumbers'], [:start, 'roomnumbers'],
                                             [:stop, 'textsubs'], [:start, 'textsubs']
                                           ])
  end

  it 'does not stop or restart either auxiliary script on a preserved trip' do
    expect(auxiliary_actions(true)).to eq([])
  end

  it 'does not persist the flag across independent trips' do
    expect(parse(['132', '--preserve-scripts']).last).to be(true)
    expect(parse(['223']).last).to be(false)
  end

  it 'preserves the numeric destination with the full supervised go2 argument list' do
    arguments = %w[132 --disable-confirm --typeahead=0 --stop-for-dead=off --get-silvers=off --hide-room-descriptions=off --hide-room-titles=off --preserve-scripts]
    expect(parse(arguments)).to eq(['132', true])
    expect(settings).to eq({})
  end
end

# go2's elemental-confluence travel estimates, run against lich-5's real map
# code (path_to, dijkstra and estimate_time) from the local or CI-pinned
# checkout (see load_lich5_map in spec_helper.rb). Skipped without one.
#
# Graph (timeto in seconds):
#   100 -12-> 200 -1-> 300 -0.2-> 400     100 -3.5 (StringProc)-> 500
#   200 -12-> 100                         100 -1-> 0
#   600 is not connected to anything
#
# Room 0 is reachable so that a nil destination wrongly turned into room 0
# (nil.to_i) would measure a real path instead of quietly finding none.
#
# Banks, for go2's choice of a bank it can afford to reach (fares are
# silver-cost tags on the room the fare is paid from):
#   700 -30 (fare 50)-> 710 -1-> 720 (bank)     700 -40-> 730 (bank)
#   740 (bank)
module Go2TravelTimeSpec
  SOURCE_PATH = find_lic_source('go2.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH)

  module Sandbox; end
  MAP = load_lich5_map(Sandbox)

  if MAP
    string_proc = Sandbox::Lich::Common::StringProc
    add_room = lambda do |id, wayto, timeto, tags = []|
      MAP.new(id, ["[Room #{id}]"], ["Room #{id}."], ['Obvious paths: none.'], [], nil, nil, nil, wayto, timeto, nil, nil, tags)
    end
    add_room.call(0, {}, {})
    add_room.call(100, { '200' => 'east', '500' => 'climb ladder', '0' => 'north' }, { '200' => 12.0, '500' => string_proc.new('3.5'), '0' => 1.0 })
    add_room.call(200, { '300' => 'east', '100' => 'west' }, { '300' => 1.0, '100' => 12.0 })
    add_room.call(300, { '400' => 'east' }, { '400' => 0.2 })
    add_room.call(400, {}, {})
    add_room.call(500, {}, {})
    add_room.call(600, {}, {})
    add_room.call(700, { '710' => 'go ferry', '730' => 'west' }, { '710' => 30.0, '730' => 40.0 }, ['silver-cost:710:50'])
    add_room.call(710, { '720' => 'east' }, { '720' => 1.0 })
    add_room.call(720, {}, {}, ['bank'])
    add_room.call(730, {}, {}, ['bank'])
    add_room.call(740, {}, {}, ['bank'])
    # Older Lich keeps rooms in an Array indexed by id and walks all of it in
    # find_all_nearest_by_tag, calling nil.tags on the unused ids; the Lich
    # runtime's NilClass patch absorbs that, but rspec does not load it. Fill
    # the unused ids with unconnected rooms so the walk sees only real rooms.
    (0..740).each { |id| add_room.call(id, {}, {}) unless MAP[id] }
  end

  # The real Go2.travel_path and Go2.estimate_travel_time, with Room and Map
  # bound to the real map class. Built on demand so the caller examples below
  # report a missing helper as an ordinary example failure.
  def self.go2
    @go2 ||= Module.new.tap do |go2|
      go2.const_set(:Room, MAP)
      go2.const_set(:Map, MAP)
      %w[travel_path estimate_travel_time].each do |name|
        go2.module_eval(extract_lic_method(SOURCE, name, source_path: SOURCE_PATH), SOURCE_PATH)
      end
    end
  end

  # go2's real get_silver_cost proc.
  def self.get_silver_cost
    source = extract_from_source(SOURCE, /^  get_silver_cost = proc \{.*?^  \}\n/m, label: 'get_silver_cost', source_path: SOURCE_PATH)
    Object.new.instance_eval("#{source}\nget_silver_cost", SOURCE_PATH)
  end

  # go2's real choice of a bank to fetch silver from: the `unless (bank_id =
  # ...)` block, with its echo and fail_trip captured. Returns the chosen bank
  # id, or :too_poor when go2 would have given up.
  def self.choose_bank(current_silvers)
    block = extract_from_source(
      SOURCE,
      /^( +)(?:bank_origin = Room\.current\n\1)?unless \(bank_id = .*?^\1end\n/m,
      label: 'bank choice', source_path: SOURCE_PATH
    )
    context = Object.new
    context.define_singleton_method(:echo) { |_msg| nil }
    catch(:go2_exit) do
      context.instance_eval(
        "get_silver_cost = Go2TravelTimeSpec.get_silver_cost\nfail_trip = proc { |_reason| throw :go2_exit, :too_poor }\n" \
        "current_silvers = #{Integer(current_silvers)}\n#{block}\nbank_id",
        SOURCE_PATH
      )
    end
  end
end

RSpec.describe 'go2 travel time estimates' do
  let(:map) { Go2TravelTimeSpec::MAP }

  before do
    skip 'needs a lich-5 checkout (LICH5_PATH or a sibling ../lich-5)' unless map
  end

  describe 'Go2.estimate_travel_time' do
    def estimate(origin, destination)
      Go2TravelTimeSpec.go2.estimate_travel_time(origin, destination)
    end

    it 'counts the first leg of a multi-room path' do
      # path_to leaves out room 100 (and, before Lich 5.14, room 300 too).
      expect([[200, 300], [200]]).to include(map[100].path_to(300))
      expect(estimate(100, 300)).to eq(13.0)
    end

    it 'counts every leg of a longer path' do
      expect(estimate(100, 400)).to be_within(1e-9).of(13.2)
    end

    it 'gives an adjacent room its edge time instead of 0' do
      expect(estimate(100, 200)).to eq(12.0)
    end

    it 'evaluates a StringProc first edge' do
      expect(estimate(100, 500)).to eq(3.5)
    end

    it 'matches the graph distance dijkstra computes, for every reachable room' do
      # Indexed by room id: a Hash in current Lich, an Array before 5.14.
      _, distances = map[100].dijkstra
      [0, 200, 300, 400, 500].each do |id|
        expect(estimate(100, id)).to be_within(1e-9).of(distances[id]), "room #{id}"
      end
    end

    it 'accepts the destination as a numeric string' do
      expect(estimate(100, '300')).to eq(13.0)
    end

    it 'is nil when there is no path' do
      expect(estimate(100, 600)).to be_nil
      expect(estimate(400, 100)).to be_nil
    end

    it 'is nil (no path) when already standing in the destination' do
      expect(estimate(100, 100)).to be_nil
    end

    it 'is nil for a starting room that is unknown or not in the map' do
      expect(estimate(nil, 300)).to be_nil
      expect(estimate(999_999, 300)).to be_nil
    end

    it 'is nil for a missing destination instead of measuring a path to room 0' do
      expect(estimate(100, 0)).to eq(1.0)
      expect(estimate(100, nil)).to be_nil
    end

    context 'with the path_to of Lich before 5.14, which also leaves out the destination' do
      it 'restores the last leg as well as the first' do
        allow(map[100]).to receive(:path_to).with(300).and_return([200])
        expect(estimate(100, 300)).to eq(13.0)
      end

      it 'turns the empty path to an adjacent room into that one edge' do
        allow(map[100]).to receive(:path_to).with(200).and_return([])
        expect(estimate(100, 200)).to eq(12.0)
      end
    end
  end

  describe 'Go2.travel_path' do
    def travel_path(origin, destination)
      Go2TravelTimeSpec.go2.travel_path(origin, destination)
    end

    it 'starts at the origin and ends at the destination' do
      expect(travel_path(100, 400)).to eq([100, 200, 300, 400])
      expect(travel_path(100, 200)).to eq([100, 200])
      expect(travel_path(100, '300')).to eq([100, 200, 300])
    end

    it 'is just the origin when already standing in the destination' do
      expect(travel_path(100, 100)).to eq([100])
      expect(travel_path(100, '100')).to eq([100])
    end

    it 'is nil when there is no path, or either room is missing' do
      expect(travel_path(100, 600)).to be_nil
      expect(travel_path(400, 100)).to be_nil
      expect(travel_path(nil, 300)).to be_nil
      expect(travel_path(999_999, 300)).to be_nil
      expect(travel_path(100, nil)).to be_nil
    end

    it 'restores both ends of the path_to of Lich before 5.14' do
      allow(map[100]).to receive(:path_to).with(400).and_return([200, 300])
      allow(map[100]).to receive(:path_to).with(200).and_return([])
      expect(travel_path(100, 400)).to eq([100, 200, 300, 400])
      expect(travel_path(100, 200)).to eq([100, 200])
    end
  end

  describe "go2's choice of a bank it can afford to reach" do
    before do
      stub_const('Go2', Go2TravelTimeSpec.go2)
      stub_const('Room', map)
      stub_const('Map', map)
      stub_const('StringProc', Go2TravelTimeSpec::Sandbox::Lich::Common::StringProc)
    end

    it 'counts the fare out of the current room' do
      allow(map).to receive(:current).and_return(map[700])
      expect(Go2TravelTimeSpec.get_silver_cost.call([700, 710, 720])).to eq(50)
      # 720 is nearer, but the 50 silver ferry out of 700 is out of reach.
      expect(Go2TravelTimeSpec.choose_bank(20)).to eq(730)
      expect(Go2TravelTimeSpec.choose_bank(50)).to eq(720)
    end

    it 'counts a fare on the last leg with the path_to of Lich before 5.14' do
      allow(map).to receive(:current).and_return(map[710])
      allow(map[710]).to receive(:path_to).with(720).and_return([])
      map[710].tags.push('silver-cost:720:5')
      expect(Go2TravelTimeSpec.choose_bank(4)).to eq(:too_poor)
      expect(Go2TravelTimeSpec.choose_bank(5)).to eq(720)
    ensure
      map[710].tags.delete('silver-cost:720:5')
    end

    it 'chooses the bank you are standing in, at no cost' do
      allow(map).to receive(:current).and_return(map[740])
      expect(Go2TravelTimeSpec.choose_bank(0)).to eq(740)
    end
  end

  describe 'the instability callers' do
    around do |example|
      saved = [$mapdb_last_instability, $mapdb_instability_timeto]
      example.run
    ensure
      $mapdb_last_instability, $mapdb_instability_timeto = saved
    end

    before do
      stub_const('Go2', Go2TravelTimeSpec.go2)
      stub_const('Room', map)
      stub_const('Map', map)
    end

    it 'records full town travel times from the instability in both places go2 finds one' do
      loops = Go2TravelTimeSpec::SOURCE.scan(/^( +)(for id in town_ids\n.*?^\1end\n)/m).map(&:last)
      expect(loops.size).to eq(2)

      loops.each do |loop_source|
        $mapdb_last_instability = 100
        $mapdb_instability_timeto = {}
        Object.new.instance_eval("town_ids = [200, 300, 400, 600]\n#{loop_source}", Go2TravelTimeSpec::SOURCE_PATH)
        expect($mapdb_instability_timeto.keys).to eq([200, 300, 400, 600])
        expect($mapdb_instability_timeto[200]).to eq(12.0)
        expect($mapdb_instability_timeto[300]).to eq(13.0)
        expect($mapdb_instability_timeto[400]).to be_within(1e-9).of(13.2)
        expect($mapdb_instability_timeto[600]).to be_nil
      end
    end

    it 'only walks to remembered instabilities that are really within 10 seconds' do
      block = extract_from_source(
        Go2TravelTimeSpec::SOURCE,
        /^        GameSettings\['recent-instabilities'\]\.find_all .*?^        \}\n/m,
        label: 'recent-instabilities walk', source_path: Go2TravelTimeSpec::SOURCE_PATH
      )
      walked = []
      # go2 walks there with Go2.run_nested; stub that one method by name and
      # keep the real estimate_travel_time.
      real_go2 = Go2TravelTimeSpec.go2
      go2 = Module.new
      go2.define_singleton_method(:estimate_travel_time) { |*args| real_go2.estimate_travel_time(*args) }
      go2.define_singleton_method(:run_nested) do |target, _label|
        walked << target.to_s
        nil
      end
      stub_const('Go2', go2)
      stub_const('CharSettings', { 'element' => 'fire' })
      stub_const('GameSettings', { 'recent-instabilities' => [200, 300, 500, 600].map { |id| { room_id: id, element: 'fire' } } })
      allow(map).to receive(:current).and_return(map[100])

      Object.new.instance_eval("check_instability = proc { false }\n#{block}", Go2TravelTimeSpec::SOURCE_PATH)
      # 200 (12 s) and 300 (13 s) are too far; 600 has no path.
      expect(walked).to eq(['500'])
    end
  end
end
