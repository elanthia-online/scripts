# frozen_string_literal: true

require_relative '../spec_helper'

# Runs the real map window's drawing and geometry against a stubbed WebUI contract. These
# pin what the WebUI contract requires of the page: the layer kinds it accepts, its layer
# limit, and the absolute pixels its click events report.
RSpec.describe 'ElanthiaMap::Window' do
  let(:path) { find_lic_source('map.lic', from: __dir__) }
  let(:source) { File.read(path, encoding: 'UTF-8').gsub(/\r\n/, "\n") }
  let(:module_source) { source[/^module ElanthiaMap\n.*?^end\n(?=\nbefore_dying)/m].gsub('::Lich::WebUI::Contract', 'StubContract') }
  let(:room_class) { Struct.new(:id, :image, :image_coords, :tags, :location, keyword_init: true) }
  let(:rooms) { [] }
  let(:said) { [] }

  let(:namespace) do
    list = rooms
    Module.new.tap do |ns|
      ns.const_set(:StubContract, Module.new.tap { |c| c.const_set(:BOUNDS, { short_text: 512, collection: 512 }.freeze) })
      ns.const_set(:Room, Module.new { define_singleton_method(:list) { list } })
      ns.module_eval(module_source, path)
    end
  end

  let(:window) do
    log = said
    namespace.const_get(:ElanthiaMap).const_get(:Window).allocate.tap do |w|
      w.define_singleton_method(:respond) { |text = ''| log << text }
      w.instance_variable_set(:@lock, Mutex.new)
      w.instance_variable_set(:@settings, { expanded_canvas: true, global_scale: 1.0, global_scale_enabled: false, map_scale: {}, dynamic_indicator_size: false, keep_centered: true })
      w.instance_variable_set(:@notes, {})
      w.instance_variable_set(:@menu_revision, 0)
      w.instance_variable_set(:@current_map, 'maps/sheet.png')
      w.instance_variable_set(:@image_sizes, { 'maps/sheet.png' => [1000, 800] })
      w.instance_variable_set(:@rooms_by_sheet, { 'sheet.png' => rooms })
      w.instance_variable_set(:@route, '/files/map-sheets/')
    end
  end

  def room(id, tags: [])
    room_class.new(id: id, image: 'sheet.png', image_coords: [10, 20, 30, 40], tags: tags, location: 'Town')
  end

  it 'has no GTK or retired WebUI calls left' do
    code = source.sub(/\A.*?^=end/m, '')

    expect(code).not_to match(/\bGtk\b|\bGdk\b|Cairo\b(?! any more)/)
    expect(code).not_to match(/menu_item|builder\.menu\(|surface_zoom|viewer_ids|kind: 'line'|kind: 'ellipse'/)
  end

  it 'draws the current room as a ring centred on it, and the sheet at its canvas offset' do
    rooms << room(1)
    window.instance_variable_set(:@current_room, rooms.first)

    layers = window.layers

    expect(layers.first).to include(kind: 'image', x: 500, y: 400, w: 1000, h: 800)
    expect(layers.last).to include(kind: 'marker', shape: 'ring', w: 58, h: 58, x: 500 + 20 - 29, y: 400 + 30 - 29)
  end

  it 'draws a selected tag as one cross per room' do
    rooms << room(1, tags: ['bank']) << room(2, tags: ['inn'])
    window.instance_variable_set(:@active_tag, 'bank')

    crosses = window.layers.select { |layer| layer[:shape] == 'cross' }

    expect(crosses.size).to eq(1)
    expect(crosses.first).to include(kind: 'marker', x: 510, y: 420, w: 20, h: 20)
  end

  it 'stays within the composite layer limit and says so once when it has to cut markers' do
    600.times { |index| rooms << room(index, tags: ['herb']) }
    window.instance_variable_set(:@active_tag, 'herb')

    expect(window.layers.size).to eq(512)
    window.layers
    expect(said.size).to eq(1)
    expect(said.first).to include('600 rooms match')
  end

  it 'reads clicks as absolute surface pixels, minus the canvas offset' do
    rooms << room(1)
    started = []
    window.define_singleton_method(:defer_start_script) { |name, args| started << [name, args] }
    window.define_singleton_method(:diag) { |*| nil }
    event = Struct.new(:payload).new({ x: 520, y: 430, button: 'primary', modifiers: [] })

    window.on_surface_activate(event)

    expect(started).to eq([['go2', ['1', '_disable_confirm_']]])
  end

  it 'returns focus to the frontend after a left click, but not a right click' do
    returned = []
    window.define_singleton_method(:return_focus) { returned << :focus }
    window.define_singleton_method(:diag) { |*| nil }
    window.define_singleton_method(:defer_start_script) { |*| nil }

    window.on_surface_activate(Struct.new(:payload).new({ x: 520, y: 430, button: 'secondary', modifiers: [] }))
    expect(returned).to be_empty

    window.on_surface_activate(Struct.new(:payload).new({ x: 520, y: 430, button: 'primary', modifiers: [] }))
    expect(returned).to eq([:focus])
  end

  it 'returns focus once when the window first opens, not when a viewer reconnects' do
    returned = []
    window.define_singleton_method(:return_focus) { returned << :focus }
    window.instance_variable_set(:@attached, false)

    2.times { window.on_attach }

    expect(returned).to eq([:focus])
  end

  context 'with a frontend to return to' do
    let(:calls) { [] }

    before do
      log = calls
      frontend = Module.new do
        define_singleton_method(:pid) { 5888 }
        define_singleton_method(:refocus) { log << :refocus }
      end
      namespace.const_get(:ElanthiaMap).const_get(:Window).send(:const_set, :Frontend, frontend)
      window.define_singleton_method(:diag) { |*| nil }
    end

    def return_focus_and_wait
      before = Thread.list
      window.return_focus
      (Thread.list - before).each(&:join)
    end

    it 'refocuses it' do
      stub_const('ENV', ENV.to_h.reject { |key, _| key == 'HYDRA_SEAT' })

      return_focus_and_wait

      expect(calls).to eq([:refocus])
    end

    it 'leaves focus alone under Hydra, which cannot be told which character this is' do
      stub_const('ENV', ENV.to_h.merge('HYDRA_SEAT' => 'GSIV:Nisugi'))

      return_focus_and_wait

      expect(calls).to be_empty
    end
  end

  it 'returns focus after clicking a room with a note' do
    returned = []
    window.define_singleton_method(:return_focus) { returned << :focus }
    window.define_singleton_method(:defer_start_script) { |*| nil }

    window.on_region_activate(Struct.new(:payload).new({ region: 'note-5' }))

    expect(returned).to eq([:focus])
  end

  it 'centres through the shared scroll origin once the viewport is known' do
    window.instance_variable_set(:@viewport, { width: 400, height: 300 })

    window.center_on(100, 100)

    expect(window.scroll_origin_prop).to eq({ scroll_origin: [(500 + 100) - 200, (400 + 100) - 150] })
  end

  it 'holds a centre until the browser has reported the viewport' do
    window.center_on(100, 100)

    expect(window.scroll_origin_prop).to eq({})
    expect(window.instance_variable_get(:@pending_center)).to eq([100, 100])
  end

  it 'zooms around the middle of the view' do
    window.instance_variable_set(:@viewport, { width: 400, height: 300 })
    window.instance_variable_set(:@last_position, [600, 500])
    window.define_singleton_method(:settings_changed) { nil }
    window.define_singleton_method(:refresh) { nil }
    event = Struct.new(:payload).new({ direction: 'in' })

    window.on_zoom(event)

    expect(window.scale).to be_within(0.001).of(1.1)
    expect(window.scroll_origin_prop[:scroll_origin]).to eq([(800 * 1.1 - 200).round, (650 * 1.1 - 150).round])
  end

  it 'gives a menu item a new key after an outside change, because the viewer keeps its checked state' do
    window.define_singleton_method(:refresh) { nil }
    before = window.menu_key('tags-0')

    window.on_tag('bank')

    expect(window.menu_key('tags-0')).not_to eq(before)
  end

  it 'keeps Find open and explains when nothing matches' do
    namespace.const_get(:Room).define_singleton_method(:[]) { |_text| nil }
    window.define_singleton_method(:refresh) { nil }
    window.instance_variable_set(:@panel, :find)
    window.instance_variable_set(:@find_text, 'nowhere')

    window.on_find

    expect(window.instance_variable_get(:@panel)).to eq(:find)
    expect(window.find_status).to eq('No matching room.')
  end

  it 'moves focus to the Find box each time it opens, with any old error cleared' do
    window.define_singleton_method(:refresh) { nil }
    window.instance_variable_set(:@find_focus, 0)
    window.instance_variable_set(:@find_status, 'No matching room.')

    window.on_open_panel(:find)

    expect(window.find_focus).to eq(1)
    expect(window.find_status).to eq('')
  end

  it 'keeps the scroller inside the window, leaving room for an open panel' do
    window.instance_variable_set(:@char_settings, { window_height: 600 })

    expect(window.view_height).to eq(598)
    window.instance_variable_set(:@panel, :find)
    expect(window.view_height).to eq(502)
  end
end
