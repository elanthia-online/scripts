# frozen_string_literal: true

# Tests for the dynamic map renderer components in scripts/map.lic
#
# These tests verify ZoneResolver and LayoutEngine behavior without
# requiring GTK3 or a live Lich runtime. They use minimal doubles
# that replicate the Room/Map interfaces.

require 'rspec'

# Minimal Room double
class MockRoom
  attr_accessor :id, :title, :description, :paths, :uid, :location,
                :image, :wayto, :timeto, :tags

  def initialize(id:, wayto: {}, timeto: {}, image: nil, location: nil, **_opts)
    @id = id
    @wayto = wayto
    @timeto = timeto
    @image = image
    @location = location
    @title = []
    @description = []
    @paths = []
    @uid = []
    @tags = []
  end
end

# DR room with Genie fields
class MockDRRoom < MockRoom
  attr_accessor :genie_id, :genie_zone, :genie_pos

  def initialize(id:, genie_id: nil, genie_zone: nil, genie_pos: nil, **opts)
    super(id: id, **opts)
    @genie_id = genie_id
    @genie_zone = genie_zone
    @genie_pos = genie_pos
  end
end

# Mock Map class for zone resolver tests
MockMapList = []

module Map
  class << self
    def list
      MockMapList
    end

    def [](id)
      MockMapList[id.to_i]
    end
  end
end

# Define the modules under test (extracted from map.lic).
# In production these live inside the ElanthiaMap module.
# We redefine them here to test in isolation without GTK3.

module ElanthiaMap
  module ZoneResolver
    @cache = {}

    def self.clear_cache
      @cache = {}
    end

    def self.has_location?(room)
      room.location.is_a?(String) && !room.location.empty?
    end

    def self.resolve(room)
      return nil if room.nil?

      zone_key = if room.respond_to?(:genie_zone) && room.genie_zone
                   "gz:#{room.genie_zone}"
                 elsif room.image
                   "img:#{room.image}"
                 elsif has_location?(room)
                   "loc:#{room.location}"
                 else
                   "cc:#{room.id}"
                 end

      return @cache[zone_key] if @cache[zone_key]

      rooms = if room.respond_to?(:genie_zone) && room.genie_zone
                Map.list.select { |r| r && r.respond_to?(:genie_zone) && r.genie_zone == room.genie_zone }
              elsif room.image
                Map.list.select { |r| r && r.image == room.image }
              elsif has_location?(room)
                Map.list.select { |r| r && r.location == room.location }
              else
                bfs_zone(room)
              end

      @cache[zone_key] = { zone_id: zone_key, rooms: rooms }
    end

    def self.bfs_zone(start_room, max_depth: 40)
      visited = { start_room.id => true }
      queue = [[start_room, 0]]
      result = [start_room]
      while (entry = queue.shift)
        current, depth = entry
        next if depth >= max_depth

        current.wayto.each_key do |target_id|
          tid = target_id.to_i
          next if visited[tid]

          neighbor = Map[tid]
          next if neighbor.nil?
          next if (neighbor.respond_to?(:genie_zone) && neighbor.genie_zone) || neighbor.image || has_location?(neighbor)

          visited[tid] = true
          result << neighbor
          queue << [neighbor, depth + 1]
        end
      end
      result
    end
  end

  module LayoutEngine
    DIRECTION_OFFSETS = {
      'north' => [0, -1], 'south' => [0, 1],
      'east' => [1, 0], 'west' => [-1, 0],
      'northeast' => [1, -1], 'northwest' => [-1, -1],
      'southeast' => [1, 1], 'southwest' => [-1, 1],
      'n' => [0, -1], 's' => [0, 1], 'e' => [1, 0], 'w' => [-1, 0],
      'ne' => [1, -1], 'nw' => [-1, -1], 'se' => [1, 1], 'sw' => [-1, 1],
      'up' => [0, -1], 'down' => [0, 1], 'out' => [1, 0]
    }.freeze

    GRID_SPACING = 20

    def self.point_on_segment?(px, py, ax, ay, bx, by)
      return false if ax == bx && ay == by

      cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
      return false unless cross == 0

      px.between?([ax, bx].min, [ax, bx].max) && py.between?([ay, by].min, [ay, by].max)
    end

    def self.on_connection_line?(px, py, positions, room_index, skip_neighbors_of: nil)
      skip_set = nil
      if skip_neighbors_of
        skip_room = room_index[skip_neighbors_of]
        if skip_room
          skip_set = {}
          skip_room.wayto.each_key { |k| skip_set[k.to_i] = true }
          room_index.each do |rid, r|
            skip_set[rid] = true if r.wayto.key?(skip_neighbors_of.to_s)
          end
        end
      end

      positions.each do |room_id, pos|
        room = room_index[room_id]
        next unless room

        room.wayto.each_key do |target_id|
          tid = target_id.to_i
          target_pos = positions[tid]
          next unless target_pos
          next if (px == pos[:x] && py == pos[:y]) || (px == target_pos[:x] && py == target_pos[:y])
          next if skip_set && (skip_set[room_id] || skip_set[tid])

          return true if point_on_segment?(px, py, pos[:x], pos[:y], target_pos[:x], target_pos[:y])
        end
      end
      false
    end

    def self.direction_offset(move_cmd)
      return nil if move_cmd.start_with?(';e ')

      d = move_cmd.strip.downcase
      DIRECTION_OFFSETS[d]
    end

    def self.layout(rooms, seed_room)
      if rooms.all? { |r| r.respond_to?(:genie_pos) && r.genie_pos.is_a?(Array) && r.genie_pos.size == 3 }
        positions = {}
        rooms.each do |r|
          positions[r.id] = { x: r.genie_pos[0], y: r.genie_pos[1], z: r.genie_pos[2] }
        end
        return positions
      end

      room_index = {}
      rooms.each { |r| room_index[r.id] = r }

      positions = {}
      positions[seed_room.id] = { x: 0, y: 0, z: 0 }
      occupied = { [0, 0] => true }

      queue = [seed_room]
      visited = { seed_room.id => true }

      while (current = queue.shift)
        cx = positions[current.id][:x]
        cy = positions[current.id][:y]

        current.wayto.each do |target_id, move_cmd|
          tid = target_id.to_i
          next if visited[tid]
          next unless room_index[tid]

          offset = direction_offset(move_cmd.to_s)

          if offset
            new_x = cx + offset[0] * GRID_SPACING
            new_y = cy + offset[1] * GRID_SPACING
            attempts = 0
            while occupied[[new_x, new_y]] && attempts < 15
              new_x += offset[0] * GRID_SPACING
              new_y += offset[1] * GRID_SPACING
              attempts += 1
            end
          else
            new_x = cx + GRID_SPACING
            new_y = cy
          end

          if occupied[[new_x, new_y]]
            [[1, 0], [0, 1], [-1, 0], [0, -1], [1, -1], [-1, -1], [1, 1], [-1, 1]].each do |dx, dy|
              test_x = cx + dx * GRID_SPACING
              test_y = cy + dy * GRID_SPACING
              unless occupied[[test_x, test_y]]
                new_x = test_x
                new_y = test_y
                break
              end
            end
          end

          positions[tid] = { x: new_x, y: new_y, z: 0 }
          occupied[[new_x, new_y]] = true
          visited[tid] = true
          queue << room_index[tid]
        end
      end

      resolve_line_collisions(positions, occupied, room_index)
      positions
    end

    def self.resolve_line_collisions(positions, occupied, room_index, max_passes: 3)
      max_passes.times do
        moved = false
        positions.each do |room_id, pos|
          next unless on_connection_line?(pos[:x], pos[:y], positions, room_index, skip_neighbors_of: room_id)

          [[0, -1], [0, 1], [-1, 0], [1, 0], [1, -1], [-1, -1], [1, 1], [-1, 1]].each do |dx, dy|
            nx = pos[:x] + dx * GRID_SPACING
            ny = pos[:y] + dy * GRID_SPACING
            unless occupied[[nx, ny]] || on_connection_line?(nx, ny, positions, room_index, skip_neighbors_of: room_id)
              occupied.delete([pos[:x], pos[:y]])
              pos[:x] = nx
              pos[:y] = ny
              occupied[[nx, ny]] = true
              moved = true
              break
            end
          end
        end
        break unless moved
      end
    end
  end
end

# ============================================================
# Specs
# ============================================================

RSpec.describe ElanthiaMap::ZoneResolver do
  before(:each) do
    ElanthiaMap::ZoneResolver.clear_cache
    MockMapList.clear
  end

  describe '.has_location?' do
    it 'returns true for a non-empty string location' do
      room = MockRoom.new(id: 1, location: 'Wehnimers Landing')
      expect(ElanthiaMap::ZoneResolver.has_location?(room)).to be true
    end

    it 'returns false for nil location' do
      room = MockRoom.new(id: 1, location: nil)
      expect(ElanthiaMap::ZoneResolver.has_location?(room)).to be false
    end

    it 'returns false for empty string location' do
      room = MockRoom.new(id: 1, location: '')
      expect(ElanthiaMap::ZoneResolver.has_location?(room)).to be false
    end

    it 'returns false for non-string location' do
      room = MockRoom.new(id: 1, location: false)
      expect(ElanthiaMap::ZoneResolver.has_location?(room)).to be false
    end
  end

  describe '.resolve' do
    it 'returns nil for nil room' do
      expect(ElanthiaMap::ZoneResolver.resolve(nil)).to be_nil
    end

    it 'uses genie_zone as highest priority' do
      r1 = MockDRRoom.new(id: 0, genie_zone: '1', image: 'img1', location: 'Loc')
      r2 = MockDRRoom.new(id: 1, genie_zone: '1', image: 'img2')
      r3 = MockDRRoom.new(id: 2, genie_zone: '2')
      MockMapList[0] = r1
      MockMapList[1] = r2
      MockMapList[2] = r3

      result = ElanthiaMap::ZoneResolver.resolve(r1)
      expect(result[:zone_id]).to eq('gz:1')
      expect(result[:rooms].map(&:id)).to contain_exactly(0, 1)
    end

    it 'falls back to image when no genie_zone' do
      r1 = MockRoom.new(id: 0, image: 'wl-town', location: 'Loc')
      r2 = MockRoom.new(id: 1, image: 'wl-town')
      r3 = MockRoom.new(id: 2, image: 'other')
      MockMapList[0] = r1
      MockMapList[1] = r2
      MockMapList[2] = r3

      result = ElanthiaMap::ZoneResolver.resolve(r1)
      expect(result[:zone_id]).to eq('img:wl-town')
      expect(result[:rooms].map(&:id)).to contain_exactly(0, 1)
    end

    it 'falls back to location when no image' do
      r1 = MockRoom.new(id: 0, location: 'Wehnimers Landing')
      r2 = MockRoom.new(id: 1, location: 'Wehnimers Landing')
      r3 = MockRoom.new(id: 2, location: 'Icemule Trace')
      MockMapList[0] = r1
      MockMapList[1] = r2
      MockMapList[2] = r3

      result = ElanthiaMap::ZoneResolver.resolve(r1)
      expect(result[:zone_id]).to eq('loc:Wehnimers Landing')
      expect(result[:rooms].map(&:id)).to contain_exactly(0, 1)
    end

    it 'falls back to BFS when no zone, image, or location' do
      r1 = MockRoom.new(id: 0, wayto: { '1' => 'north' })
      r2 = MockRoom.new(id: 1, wayto: { '0' => 'south' })
      MockMapList[0] = r1
      MockMapList[1] = r2

      result = ElanthiaMap::ZoneResolver.resolve(r1)
      expect(result[:zone_id]).to eq('cc:0')
      expect(result[:rooms].map(&:id)).to contain_exactly(0, 1)
    end

    it 'caches results for same zone key' do
      r1 = MockRoom.new(id: 0, image: 'map1')
      MockMapList[0] = r1

      result1 = ElanthiaMap::ZoneResolver.resolve(r1)
      result2 = ElanthiaMap::ZoneResolver.resolve(r1)
      expect(result1).to equal(result2) # same object reference
    end
  end

  describe '.bfs_zone' do
    it 'collects connected rooms without zone assignments' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'n', '2' => 'e' })
      r1 = MockRoom.new(id: 1, wayto: { '0' => 's' })
      r2 = MockRoom.new(id: 2, wayto: { '0' => 'w' })
      MockMapList[0] = r0
      MockMapList[1] = r1
      MockMapList[2] = r2

      result = ElanthiaMap::ZoneResolver.bfs_zone(r0)
      expect(result.map(&:id)).to contain_exactly(0, 1, 2)
    end

    it 'stops at rooms with image (zone boundary)' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'n' })
      r1 = MockRoom.new(id: 1, wayto: { '0' => 's', '2' => 'n' }, image: 'different-zone')
      r2 = MockRoom.new(id: 2, wayto: { '1' => 's' })
      MockMapList[0] = r0
      MockMapList[1] = r1
      MockMapList[2] = r2

      result = ElanthiaMap::ZoneResolver.bfs_zone(r0)
      expect(result.map(&:id)).to eq([0])
    end

    it 'stops at rooms with location (zone boundary)' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'n' })
      r1 = MockRoom.new(id: 1, wayto: { '0' => 's' }, location: 'Other Place')
      MockMapList[0] = r0
      MockMapList[1] = r1

      result = ElanthiaMap::ZoneResolver.bfs_zone(r0)
      expect(result.map(&:id)).to eq([0])
    end

    it 'stops at rooms with genie_zone (zone boundary)' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'n' })
      r1 = MockDRRoom.new(id: 1, wayto: { '0' => 's' }, genie_zone: '5')
      MockMapList[0] = r0
      MockMapList[1] = r1

      result = ElanthiaMap::ZoneResolver.bfs_zone(r0)
      expect(result.map(&:id)).to eq([0])
    end

    it 'respects max_depth' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'n' })
      r1 = MockRoom.new(id: 1, wayto: { '2' => 'n' })
      r2 = MockRoom.new(id: 2, wayto: {})
      MockMapList[0] = r0
      MockMapList[1] = r1
      MockMapList[2] = r2

      result = ElanthiaMap::ZoneResolver.bfs_zone(r0, max_depth: 1)
      expect(result.map(&:id)).to contain_exactly(0, 1)
    end
  end
end

RSpec.describe ElanthiaMap::LayoutEngine do
  describe '.direction_offset' do
    it 'returns correct offset for cardinal directions' do
      expect(ElanthiaMap::LayoutEngine.direction_offset('north')).to eq([0, -1])
      expect(ElanthiaMap::LayoutEngine.direction_offset('south')).to eq([0, 1])
      expect(ElanthiaMap::LayoutEngine.direction_offset('east')).to eq([1, 0])
      expect(ElanthiaMap::LayoutEngine.direction_offset('west')).to eq([-1, 0])
    end

    it 'returns correct offset for abbreviated directions' do
      expect(ElanthiaMap::LayoutEngine.direction_offset('n')).to eq([0, -1])
      expect(ElanthiaMap::LayoutEngine.direction_offset('se')).to eq([1, 1])
      expect(ElanthiaMap::LayoutEngine.direction_offset('nw')).to eq([-1, -1])
    end

    it 'returns correct offset for vertical directions' do
      expect(ElanthiaMap::LayoutEngine.direction_offset('up')).to eq([0, -1])
      expect(ElanthiaMap::LayoutEngine.direction_offset('down')).to eq([0, 1])
    end

    it 'returns nil for non-directional moves' do
      expect(ElanthiaMap::LayoutEngine.direction_offset('go door')).to be_nil
      expect(ElanthiaMap::LayoutEngine.direction_offset('climb ladder')).to be_nil
    end

    it 'returns nil for StringProc commands' do
      expect(ElanthiaMap::LayoutEngine.direction_offset(';e fput "go door"')).to be_nil
    end

    it 'handles case insensitivity' do
      expect(ElanthiaMap::LayoutEngine.direction_offset('North')).to eq([0, -1])
      expect(ElanthiaMap::LayoutEngine.direction_offset('EAST')).to eq([1, 0])
    end

    it 'handles whitespace' do
      expect(ElanthiaMap::LayoutEngine.direction_offset(' north ')).to eq([0, -1])
    end
  end

  describe '.point_on_segment?' do
    it 'detects point on horizontal segment' do
      expect(ElanthiaMap::LayoutEngine.point_on_segment?(20, 0, 0, 0, 40, 0)).to be true
    end

    it 'detects point on vertical segment' do
      expect(ElanthiaMap::LayoutEngine.point_on_segment?(0, 20, 0, 0, 0, 40)).to be true
    end

    it 'detects point on diagonal segment' do
      expect(ElanthiaMap::LayoutEngine.point_on_segment?(20, 20, 0, 0, 40, 40)).to be true
    end

    it 'rejects point not on segment' do
      expect(ElanthiaMap::LayoutEngine.point_on_segment?(20, 10, 0, 0, 40, 0)).to be false
    end

    it 'rejects point on the line but outside segment' do
      expect(ElanthiaMap::LayoutEngine.point_on_segment?(60, 0, 0, 0, 40, 0)).to be false
    end

    it 'rejects zero-length segments' do
      expect(ElanthiaMap::LayoutEngine.point_on_segment?(0, 0, 0, 0, 0, 0)).to be false
    end

    it 'treats endpoints as on the segment' do
      expect(ElanthiaMap::LayoutEngine.point_on_segment?(0, 0, 0, 0, 40, 0)).to be true
      expect(ElanthiaMap::LayoutEngine.point_on_segment?(40, 0, 0, 0, 40, 0)).to be true
    end
  end

  describe '.layout' do
    it 'uses Genie positions when all rooms have genie_pos (Mode A)' do
      r1 = MockDRRoom.new(id: 0, genie_pos: [100, 200, 0])
      r2 = MockDRRoom.new(id: 1, genie_pos: [120, 200, 0])

      positions = ElanthiaMap::LayoutEngine.layout([r1, r2], r1)
      expect(positions[0]).to eq({ x: 100, y: 200, z: 0 })
      expect(positions[1]).to eq({ x: 120, y: 200, z: 0 })
    end

    it 'falls back to auto-layout when not all rooms have genie_pos' do
      r1 = MockDRRoom.new(id: 0, genie_pos: [100, 200, 0], wayto: { '1' => 'north' })
      r2 = MockRoom.new(id: 1, wayto: { '0' => 'south' })

      positions = ElanthiaMap::LayoutEngine.layout([r1, r2], r1)
      expect(positions[0]).to eq({ x: 0, y: 0, z: 0 })
      expect(positions[1][:y]).to be < positions[0][:y]
    end

    it 'places seed room at origin' do
      r1 = MockRoom.new(id: 0, wayto: {})
      positions = ElanthiaMap::LayoutEngine.layout([r1], r1)
      expect(positions[0]).to eq({ x: 0, y: 0, z: 0 })
    end

    it 'places rooms in correct relative positions' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'north', '2' => 'east' })
      r1 = MockRoom.new(id: 1, wayto: { '0' => 'south' })
      r2 = MockRoom.new(id: 2, wayto: { '0' => 'west' })

      positions = ElanthiaMap::LayoutEngine.layout([r0, r1, r2], r0)

      expect(positions[1][:y]).to be < positions[0][:y]
      expect(positions[1][:x]).to eq(positions[0][:x])

      expect(positions[2][:x]).to be > positions[0][:x]
      expect(positions[2][:y]).to eq(positions[0][:y])
    end

    it 'handles non-directional moves' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'go door' })
      r1 = MockRoom.new(id: 1, wayto: { '0' => 'go door' })

      positions = ElanthiaMap::LayoutEngine.layout([r0, r1], r0)
      expect(positions[0]).not_to eq(positions[1])
    end

    it 'avoids position collisions' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'north', '2' => 'north' })
      r1 = MockRoom.new(id: 1, wayto: {})
      r2 = MockRoom.new(id: 2, wayto: {})

      positions = ElanthiaMap::LayoutEngine.layout([r0, r1, r2], r0)

      pos_pairs = positions.values.map { |p| [p[:x], p[:y]] }
      expect(pos_pairs.uniq.size).to eq(pos_pairs.size)
    end

    it 'assigns positions to all rooms in the zone' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'n', '2' => 'e', '3' => 's' })
      r1 = MockRoom.new(id: 1, wayto: { '0' => 's' })
      r2 = MockRoom.new(id: 2, wayto: { '0' => 'w' })
      r3 = MockRoom.new(id: 3, wayto: { '0' => 'n' })

      positions = ElanthiaMap::LayoutEngine.layout([r0, r1, r2, r3], r0)
      expect(positions.keys).to contain_exactly(0, 1, 2, 3)
    end

    it 'handles a linear corridor' do
      r0 = MockRoom.new(id: 0, wayto: { '1' => 'east' })
      r1 = MockRoom.new(id: 1, wayto: { '0' => 'west', '2' => 'east' })
      r2 = MockRoom.new(id: 2, wayto: { '1' => 'west' })

      positions = ElanthiaMap::LayoutEngine.layout([r0, r1, r2], r0)

      expect(positions[0][:x]).to be < positions[1][:x]
      expect(positions[1][:x]).to be < positions[2][:x]
      expect(positions[0][:y]).to eq(positions[1][:y])
      expect(positions[1][:y]).to eq(positions[2][:y])
    end
  end

  describe '.on_connection_line?' do
    it 'detects a point on a connection line' do
      positions = {
        0 => { x: 0, y: 0 },
        2 => { x: 40, y: 0 }
      }
      room_index = {
        0 => MockRoom.new(id: 0, wayto: { '2' => 'east' }),
        2 => MockRoom.new(id: 2, wayto: { '0' => 'west' })
      }

      expect(ElanthiaMap::LayoutEngine.on_connection_line?(20, 0, positions, room_index)).to be true
    end

    it 'does not flag endpoints as on the line' do
      positions = {
        0 => { x: 0, y: 0 },
        2 => { x: 40, y: 0 }
      }
      room_index = {
        0 => MockRoom.new(id: 0, wayto: { '2' => 'east' }),
        2 => MockRoom.new(id: 2, wayto: { '0' => 'west' })
      }

      expect(ElanthiaMap::LayoutEngine.on_connection_line?(0, 0, positions, room_index)).to be false
    end

    it 'skips lines to neighbor rooms when skip_neighbors_of is provided' do
      positions = {
        0 => { x: 0, y: 0 },
        1 => { x: 20, y: 0 },
        2 => { x: 40, y: 0 }
      }
      room_index = {
        0 => MockRoom.new(id: 0, wayto: { '1' => 'east', '2' => 'east' }),
        1 => MockRoom.new(id: 1, wayto: { '0' => 'west', '2' => 'east' }),
        2 => MockRoom.new(id: 2, wayto: { '0' => 'west', '1' => 'west' })
      }

      expect(ElanthiaMap::LayoutEngine.on_connection_line?(20, 0, positions, room_index, skip_neighbors_of: 1)).to be false
    end
  end
end
