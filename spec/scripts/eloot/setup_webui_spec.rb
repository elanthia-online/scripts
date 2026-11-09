# frozen_string_literal: true

require_relative '../../spec_helper'

# The setup window is a native WebUI page rendered from the settings hash. These run the
# real ELoot::Setup class against stubs and a recording builder that, like the real one,
# evaluates child blocks with the builder as self.
RSpec.describe 'ELoot::Setup' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(eloot_path, encoding: 'UTF-8') }
  let(:setup_source) { source[/^module ELoot # UI Setup\r?\n(.*?)^end\r?\n\r?\nmodule ELoot # Profile loading/m, 1] }

  let(:recorder_class) do
    Class.new do
      attr_reader :nodes

      def initialize
        @nodes = []
      end

      def method_missing(type, **props, &block)
        @nodes << props.merge(type: type)
        instance_eval(&block) if block
        nil
      end

      def respond_to_missing?(*)
        true
      end
    end
  end

  let(:known_spells) { [] }
  let(:saved) { [] }
  let(:pushed) { [] }

  let(:namespace) do
    spells = known_spells
    saves = saved
    spell = Struct.new(:num, :name, :known) { def known? = known }
    Module.new.tap do |ns|
      ns.const_set(:Spell, Module.new { define_singleton_method(:[]) { |n| n.to_i.zero? ? nil : spell.new(n.to_i, "Spell #{n.to_i}", spells.include?(n.to_i)) } })
      ns.const_set(:Stats, Module.new { define_singleton_method(:prof) { 'Warrior' } })
      ns.const_set(:Script, Module.new { define_singleton_method(:current) { :script } })
      ns.const_set(:UserVars, Module.new { define_singleton_method(:mapdb_fwi_trinket) { false } })
      room = Struct.new(:tags, :location)
      ns.const_set(:Map, Module.new {
        define_singleton_method(:list) do
          [room.new(['publiclockers'], 'the town of Icemule Trace'), room.new(['publiclockers'], 'Mist Harbor'), room.new(['publiclockers'], nil), room.new(['town'], 'Nowhere')]
        end
      })
      ns.const_set(:ELoot, Module.new {
        define_singleton_method(:get_script_version) { '2.15.0' }
        define_singleton_method(:save_profile) { saves << :saved }
        define_singleton_method(:msg) { |**| nil }
      })
      ns.module_eval(setup_source.gsub(/\r\n/, "\n"), eloot_path)
      ns.const_get(:Setup).class_eval do
        define_method(:respond) { |*| nil }
        define_method(:echo) { |*| nil }
      end
    end
  end

  let(:setup_class) { namespace.const_get(:Setup) }

  def build(settings = {})
    setup_class.new(settings)
  end

  def render(setup)
    recorder_class.new.tap { |ui| setup.render(ui) }.nodes
  end

  def node(nodes, key)
    nodes.find { |n| n[:key].to_s == key.to_s }
  end

  it 'has no GTK left anywhere in the script' do
    code = source.sub(/\A.*?^=end/m, '')
    expect(code).not_to match(/\bGtk\b|\bGdk\b|glade|<interface>/i)
  end

  it 'is available only when Lich can present a window' do
    expect(setup_class.available?).to be_falsey
  end

  describe 'opening a profile' do
    it 'fills defaults, corrects types and removes settings that no longer exist' do
      settings = build({ locksmith_withdraw_amount: '12345', alpha_rate: 3, retired_setting: true }).settings

      expect(settings).to include(locksmith_withdraw_amount: 12_345, alpha_rate: 3.0, loot_stance: 'none', loot_keep: [])
      expect(settings).not_to have_key(:retired_setting)
    end

    it 'does not share default arrays between profiles' do
      build.settings[:loot_exclude] << 'mine'

      expect(build.settings[:loot_exclude]).to eq(['black ora', 'urglaes'])
    end

    it 'forces off what the character cannot use and shows it disabled' do
      setup = build({ loot_phase: true, skin_604: true })
      nodes = render(setup)

      expect(setup.settings).to include(loot_phase: false, skin_604: false)
      expect(node(nodes, :loot_phase)[:disabled]).to be(true)
    end

    it 'keeps what the character can use' do
      known_spells << 604

      expect(build({ skin_604: true }).settings[:skin_604]).to be(true)
    end

    it 'keeps the first half of a pair that was saved with both on' do
      settings = build({ gem_everything_list: true, gem_only_list: true, alchemy_horde_locker: true, alchemy_horde_locker_che: true }).settings

      expect(settings).to include(gem_everything_list: true, gem_only_list: false, alchemy_horde_locker: true, alchemy_horde_locker_che: false)
    end
  end

  describe 'rendering' do
    it 'renders every setting the old window had, through the builder as self' do
      nodes = render(build)
      keys = setup_class.class_variable_get(:@@categories).values_at(:loot, :boxes, :sell, :skin, :hoard).flat_map(&:keys)
      arrays = keys.select { |key| setup_class.get_setting(key)[:default].is_a?(Array) }
      not_on_page = %i[gem_horde_inv alchemy_horde_inv tipping_test gem_locker alchemy_locker]
      member_lists = %i[loot_types sell_loot_types sell_container sell_appraise_types trash_dump_types gem_horde_containers alchemy_horde_containers]

      (keys - arrays - not_on_page).each { |key| expect(node(nodes, key)).not_to be_nil, "no control for #{key}" }
      (arrays - not_on_page - member_lists).each { |key| expect(node(nodes, "#{key}-table")).not_to be_nil, "no table for #{key}" }
      member_lists.each { |key| expect(nodes.any? { |n| n[:type] == :checkbox && n[:key].to_s.start_with?("#{key}-") }).to be(true), "no boxes for #{key}" }
    end

    it 'gives member checkboxes keys without spaces' do
      nodes = render(build({ loot_types: ['lm trap'] }))

      expect(node(nodes, 'loot_types-lm_trap')).to include(checked: true)
    end

    it 'disables with disabled:, because sensitive: means a confidential value' do
      nodes = render(build)

      expect(nodes.select { |n| n.key?(:sensitive) }).to be_empty
      expect(node(nodes, :skin_sheath)[:disabled]).to be(true)
    end

    it 'gates dependent controls' do
      setup = build({ sell_locksmith_pool: false, skin_enable: true, gem_horde: true, gem_horde_locker_che: true, gem_only_list: true })
      nodes = render(setup)

      expect(node(nodes, :base_tip)[:disabled]).to be(true)
      expect(node(nodes, :tipping_test)[:disabled]).to be(true)
      expect(node(nodes, :locksmith_priority)[:disabled]).to be(true)
      expect(node(nodes, :skin_sheath)[:disabled]).to be(false)
      expect(node(nodes, :gem_horde_che_rooms)[:disabled]).to be(false)
      expect(node(nodes, :gem_locker_name)[:disabled]).to be(true)
      expect(node(nodes, 'gem_list-table')[:disabled]).to be(false)
      expect(node(nodes, 'gem_everything-table')[:disabled]).to be(true)
      expect(node(nodes, :alchemy_horde_container)[:disabled]).to be(true)
    end

    it 'only offers Mist Harbor with the FWI trinket, and keeps a locker name not on the list' do
      nodes = render(build({ gem_locker_name: 'Somewhere Custom' }))
      locker = node(nodes, :gem_locker_name)

      expect(locker[:options].map { |option| option[:value] }).to eq(['', 'Icemule Trace'])
      expect(locker).to include(value: 'Somewhere Custom', editable: true)
    end

    it 'keeps a spinner value inside its bounds for display without changing the setting' do
      setup = build({ sell_keep_silver: 5_000_000 })

      expect(node(render(setup), :sell_keep_silver)[:value]).to eq(999_999)
      expect(setup.settings[:sell_keep_silver]).to eq(5_000_000)
    end

    it 'commits text as it is typed, so Close cannot lose it' do
      expect(node(render(build), :skin_weapon)).to include(change_mode: :input)
    end
  end

  describe 'changes' do
    it 'turns off the other half of a pair, in the window too' do
      setup = build
      pushes = pushed
      component = Struct.new(:type, :props, :cid).new(:checkbox, { key: 'use_standard_tipping' }, 'cid-standard')
      tree = Object.new.tap { |t| t.define_singleton_method(:each) { [component] } }
      render_result = Struct.new(:tree).new(tree)
      page = Object.new
      page.define_singleton_method(:last_render) { render_result }
      page.define_singleton_method(:set) { |*args| pushes << args }
      setup.instance_variable_set(:@page, page)

      setup.set_check(:use_incremental_tipping, true)

      expect(setup.settings).to include(use_incremental_tipping: true, use_standard_tipping: false)
      expect(pushed).to eq([['cid-standard', :checked, false]])
    end

    it 'leaves the pair alone when turning one off' do
      setup = build({ use_standard_tipping: true })

      setup.set_check(:use_incremental_tipping, false)

      expect(setup.settings[:use_standard_tipping]).to be(true)
    end

    it 'keeps member lists unique and sorted' do
      setup = build({ loot_types: %w[gem box] })

      setup.toggle_member(:loot_types, 'lm trap', true)
      expect(setup.settings[:loot_types]).to eq(['box', 'gem', 'lm trap'])
      setup.toggle_member(:loot_types, 'gem', false)
      expect(setup.settings[:loot_types]).to eq(['box', 'lm trap'])
    end

    it 'clamps and types spinner values' do
      setup = build

      setup.set_number(:base_tip, 999_999)
      setup.set_number(:alpha_rate, 2.5)

      expect(setup.settings).to include(base_tip: 100_000, alpha_rate: 2.5)
    end

    it 'adds a list entry with no duplicates, when the list had none (old code crashed here)' do
      setup = build({ loot_keep: ['zinc'] })

      setup.set_entry(:loot_keep, '  (?:gold|silver) ring ')
      setup.add_entry(:loot_keep)
      setup.set_entry(:loot_keep, 'zinc')
      setup.add_entry(:loot_keep)

      expect(setup.settings[:loot_keep]).to eq(['(?:gold|silver) ring', 'zinc'])
      expect(setup.entries[:loot_keep]).to eq('')
    end

    it 'gives the entry box a new key after Add, which is what clears it in the window' do
      setup = build
      before = node(render(setup), 'loot_keep-entry-0')

      setup.set_entry(:loot_keep, 'ring')
      setup.add_entry(:loot_keep)

      expect(before).not_to be_nil
      expect(node(render(setup), 'loot_keep-entry-1')).not_to be_nil
    end

    it 'deletes the selected row and nothing without a selection' do
      setup = build({ loot_keep: %w[a b c] })

      setup.delete_entry(:loot_keep)
      expect(setup.settings[:loot_keep]).to eq(%w[a b c])
      setup.select_row(:loot_keep, 'row-1')
      setup.delete_entry(:loot_keep)
      expect(setup.settings[:loot_keep]).to eq(%w[a c])
    end

    it 'orders keep-scrolls numerically, plain before vibrant, and refuses what is not a spell' do
      setup = build({ sell_keep_scrolls: ['303', 101, '101v', 'junk'] })

      expect(setup.settings[:sell_keep_scrolls].map(&:to_s)).to eq(%w[101 101v 303])
      setup.set_entry(:sell_keep_scrolls, 'nope')
      setup.add_entry(:sell_keep_scrolls)
      expect(setup.settings[:sell_keep_scrolls].size).to eq(3)
      expect(setup.status).to include('nope')
      setup.set_entry(:sell_keep_scrolls, '202 vibrant')
      setup.add_entry(:sell_keep_scrolls)
      expect(setup.settings[:sell_keep_scrolls].map(&:to_s)).to eq(['101', '101v', '202 vibrant', '303'])
    end

    it 'shows scroll rows with the spell name and vibrant flag' do
      rows = node(render(build({ sell_keep_scrolls: ['101', '101v'] })), 'sell_keep_scrolls-table')[:rows]

      expect(rows.map { |row| row[:cells] }).to eq([
                                                     { 'number' => '101', 'name' => 'Spell 101', 'vibrant' => '' },
                                                     { 'number' => '101', 'name' => 'Spell 101', 'vibrant' => 'Vibrant' }
                                                   ])
    end

    it 'gives exclusion rows safe keys, whatever the entry contains' do
      rows = node(render(build({ loot_exclude: ['(?:a|b) wand'] })), 'loot_exclude-table')[:rows]

      expect(rows).to eq([{ key: 'row-0', cells: { 'entry' => '(?:a|b) wand' } }])
    end
  end

  describe 'closing' do
    let(:webui) { Module.new { define_singleton_method(:close) { |_page| nil } } }

    before do
      namespace.const_set(:Lich, Module.new)
      namespace.const_get(:Lich).const_set(:WebUI, webui)
    end

    it 'corrects types, saves once, and does not refresh the closed page' do
      setup = build
      setup.instance_variable_get(:@settings)[:base_tip] = '500'

      setup.act { setup.on_close_clicked }

      expect(saved).to eq([:saved])
      expect(setup.settings[:base_tip]).to eq(500)
      expect(setup.instance_variable_get(:@closed).pop(true)).to eq(:close)
    end

    it 'reports an error from a callback instead of raising it into the dispatcher' do
      setup = build

      expect { setup.act { raise 'boom' } }.not_to raise_error
    end
  end
end
