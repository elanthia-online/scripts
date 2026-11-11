# frozen_string_literal: true

require_relative '../../spec_helper'

# The setup window is a Lich::WebUI::ListSettingsForm. These run the real ELoot::Setup
# class against stubs: a stand-in form class that records its options, and a recording
# builder that, like the real one, evaluates child blocks with the builder as self.
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

  let(:form_stub) do
    Class.new do
      attr_reader :options

      def initialize(**options)
        @options = options
      end

      def page = :page
    end
  end

  let(:known_spells) { [] }
  let(:saved) { [] }
  let(:refreshed) { [] }

  let(:namespace) do
    spells = known_spells
    saves = saved
    refreshes = refreshed
    stub = form_stub
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
      webui = Module.new { define_singleton_method(:refresh) { |page| refreshes << page } }
      webui.const_set(:ListSettingsForm, stub)
      ns.const_set(:Lich, Module.new).const_set(:WebUI, webui)
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

  # Renders the window's layout (one form per setup, as in a session); fields are recorded with their key and overrides.
  def render(setup)
    options = (@forms ||= {}.compare_by_identity)[setup] ||= setup.form.options
    ref = Struct.new(:cid)
    ui = recorder_class.new
    field = lambda do |_parent, key, **props|
      ui.nodes << props.merge(type: :field, key: key.to_s)
      ref.new("cid-#{key}")
    end
    options[:layout].call(ui, field, ->(_parent, **props) { ui.nodes << props.merge(type: :save, key: 'save') })
    ui.nodes
  end

  def node(nodes, key)
    nodes.find { |n| n[:key].to_s == key.to_s }
  end

  it 'has no GTK left anywhere in the script' do
    code = source.sub(/\A.*?^=end/m, '')
    expect(code).not_to match(/\bGtk\b|\bGdk\b|glade|<interface>/i)
  end

  it 'uses the current constants when the script is re-run in the same session' do
    setup_class
    stale = setup_source.gsub(/\r\n/, "\n")
    namespace.const_get(:Setup).send(:remove_const, :HOARD_LABELS)
    namespace.const_get(:Setup).const_set(:HOARD_LABELS, { gem: {}, alchemy: {} }.freeze)

    namespace.module_eval(stale, eloot_path)

    nodes = render(build)
    expect(node(nodes, 'gem_everything_entry')[:placeholder]).to eq('Gems to Exclude')
    expect(node(nodes, 'alchemy_list_entry')[:placeholder]).to eq('Ingredients to Include')
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

  describe 'the form' do
    let(:setup) { build }
    let(:options) { setup.form.options }

    it 'declares a field for every shown setting, and a list for every table' do
      keys = options[:fields].map { |field| field[:key] }
      lists = options[:lists].keys
      (setup.shown_keys - setup_class::MEMBERS.keys - lists).each { |key| expect(keys).to include(key), "no field for #{key}" }
      expect(lists).to match_array(setup_class::LISTS)
      expect(keys).to include(:'loot_types-lm_trap', :'gem_horde_containers-gem')
      expect(keys.uniq).to eq(keys)
    end

    it 'renders every field it declares' do
      rendered = render(setup).select { |n| n[:type] == :field }.map { |n| n[:key] }
      declared = options[:fields].map { |field| field[:key].to_s } +
                 options[:lists].keys.flat_map { |key| [key, "#{key}_entry", "#{key}_add", "#{key}_delete"].map(&:to_s) }

      expect(rendered).to match_array(declared)
    end

    it 'pairs either/or options with exclusive:' do
      fields = options[:fields].to_h { |field| [field[:key], field] }

      expect(fields[:use_standard_tipping][:exclusive]).to eq(fields[:use_incremental_tipping][:exclusive])
      expect(fields[:gem_everything_list][:exclusive]).to eq(fields[:gem_only_list][:exclusive])
      expect(fields[:gem_horde_locker][:exclusive]).not_to eq(fields[:gem_only_list][:exclusive])
      expect(fields[:skin_enable]).not_to have_key(:exclusive)
    end

    it 'offers Mist Harbor only with the FWI trinket, and keeps a locker name not on the list' do
      setup = build({ gem_locker_name: 'Somewhere Custom' })
      locker = setup.form.options[:fields].find { |field| field[:key] == :gem_locker_name }

      expect(locker[:options].map { |option| option[:value] }).to eq(['', 'Icemule Trace'])
      expect(locker).to include(editable: true)
      expect(setup.form.options[:values][:gem_locker_name]).to eq('Somewhere Custom')
    end
  end

  describe 'values the window shows' do
    it 'keeps a spinner inside its bounds and on its step' do
      values = build({ sell_keep_silver: 5_000_000, alpha_rate: 2.25, base_tip: -5 }).form_values

      expect(values).to include(sell_keep_silver: 999_999, base_tip: 0)
      expect([2.2, 2.3]).to include(values[:alpha_rate])
    end

    it 'shows the first choice for a saved choice that is not offered' do
      values = build({ loot_stance: 'off', locksmith_priority: 'bogus' }).form_values

      expect(values).to include(loot_stance: 'none', locksmith_priority: 'pool')
    end

    it 'shows member lists as checkboxes without spaces in their keys' do
      expect(build({ loot_types: ['lm trap'] }).form_values).to include('loot_types-lm_trap': true, 'loot_types-gem': false)
    end
  end

  describe 'rendering' do
    it 'disables with disabled:, because sensitive: means a confidential value' do
      nodes = render(build)

      expect(nodes.select { |n| n.key?(:sensitive) }).to be_empty
      expect(node(nodes, :skin_sheath)[:disabled]).to be(true)
    end

    it 'gates dependent controls' do
      nodes = render(build({ sell_locksmith_pool: false, skin_enable: true, gem_horde: true, gem_horde_locker_che: true, gem_only_list: true }))

      expect(node(nodes, :base_tip)[:disabled]).to be(true)
      expect(node(nodes, :tipping_test)[:disabled]).to be(true)
      expect(node(nodes, :locksmith_priority)[:disabled]).to be(true)
      expect(node(nodes, :skin_sheath)[:disabled]).to be(false)
      expect(node(nodes, :gem_horde_che_rooms)[:disabled]).to be(false)
      expect(node(nodes, :gem_locker_name)[:disabled]).to be(true)
      expect(node(nodes, :gem_list)[:disabled]).to be(false)
      expect(node(nodes, :gem_everything)[:disabled]).to be(true)
      expect(node(nodes, :alchemy_horde_container)[:disabled]).to be(true)
    end

    it 're-renders when a gate changes, and only then' do
      setup = build({ skin_enable: false })
      nodes = render(setup)
      expect(node(nodes, :skin_kneel)).not_to have_key(:on)
      node(nodes, :skin_enable)[:on][:change].call(Struct.new(:payload).new({ value: true }))

      expect(refreshed).to eq([:page])
      expect(node(render(setup), :skin_sheath)[:disabled]).to be(false)
    end

    it 'leaves the re-render to the form when ticking one half of a pair' do
      setup = build({ gem_horde: true, gem_everything_list: true })
      render(setup)
      setup.gate_changed(:gem_only_list, true)

      expect(refreshed).to be_empty
      expect(setup.live).to include(gem_only_list: true, gem_everything_list: false)
    end

    it 'previews tipping from the values in the window' do
      nodes = render(build)
      button = node(nodes, :tipping_test)

      expect(button[:submit].map(&:cid)).to eq(%w[cid-base_tip cid-max_tip cid-alpha_rate])
    end

    it 'has Cancel and Save & Close, and says what each does' do
      nodes = render(build)

      expect(node(nodes, :cancel)[:label]).to eq('Cancel')
      expect(node(nodes, :save)).to include(variant: :primary)
      expect(node(nodes, 'footer-text')[:content]).to include('Save & Close saves', 'Cancel or closing the window discards')
    end
  end

  describe 'saving' do
    let(:setup) { build({ alpha_rate: 2.25, loot_stance: 'off', loot_types: %w[gem custom], sell_keep_silver: 5_000_000 }) }
    let(:draft) { setup.form_values }

    it 'returns the settings, keeping values the window had to adjust when left alone' do
      result = setup.normalize(draft)

      expect(result).to include(alpha_rate: 2.25, loot_stance: 'off', sell_keep_silver: 5_000_000, loot_types: %w[custom gem])
      expect(result.keys).to match_array(setup.shown_keys)
    end

    it 'takes edits, merging member checkboxes and keeping values the window does not offer' do
      result = setup.normalize(draft.merge('loot_types-box': true, 'loot_types-gem': false, alpha_rate: 3.4, skin_weapon: ' knife ', loot_stance: 'guarded'))

      expect(result).to include(loot_types: %w[box custom], alpha_rate: 3.4, skin_weapon: 'knife', loot_stance: 'guarded')
    end

    it 'refuses a missing number with a message' do
      expect { setup.normalize(draft.merge(base_tip: nil)) }.to raise_error(ArgumentError, /base_tip/)
    end

    it 'forces off what the character cannot use' do
      expect(setup.normalize(draft.merge(loot_phase: true))[:loot_phase]).to be(false)
    end

    it 'applies, corrects types and saves once' do
      setup.apply(setup.normalize(draft).merge(base_tip: '500'))

      expect(saved).to eq([:saved])
      expect(setup.settings[:base_tip]).to eq(500)
    end

    it 'saves on Save & Close and not on Cancel' do
      result = nil
      form = Struct.new(:result) do
        def show = self
        def wait = result
      end
      setup.define_singleton_method(:form) { form.new(result) }

      setup.start
      expect(saved).to be_empty
      result = { base_tip: 7 }
      setup.start
      expect(saved).to eq([:saved])
      expect(setup.settings[:base_tip]).to eq(7)
    end
  end

  describe 'lists' do
    it 'edits a copy, kept unique and sorted' do
      settings = { loot_keep: ['zinc'] }
      setup = build(settings)
      spec = setup.form.options[:lists][:loot_keep]

      spec[:add].call('  (?:gold|silver) ring ')
      spec[:add].call('zinc')
      expect(spec[:value].call).to eq(['(?:gold|silver) ring', 'zinc'])
      spec[:delete].call(1)
      expect(spec[:value].call).to eq(['(?:gold|silver) ring'])
      expect(settings[:loot_keep]).to eq(['zinc'])
      expect(spec).to include(clear_after_add: true)
    end

    it 'orders keep-scrolls numerically, plain before vibrant, and refuses what is not a spell' do
      setup = build({ sell_keep_scrolls: ['303', 101, '101v', 'junk'] })
      spec = setup.form.options[:lists][:sell_keep_scrolls]

      expect(spec[:value].call.map(&:to_s)).to eq(%w[101 101v 303])
      spec[:add].call('nope')
      expect(spec[:value].call.size).to eq(3)
      expect(setup.status).to include('nope')
      spec[:add].call('202 vibrant')
      expect(spec[:value].call.map(&:to_s)).to eq(['101', '101v', '202 vibrant', '303'])
    end

    it 'shows scroll rows with the spell name and vibrant flag' do
      rows = build({ sell_keep_scrolls: ['101', '101v'] }).form.options[:lists][:sell_keep_scrolls][:rows].call

      expect(rows).to eq([{ 'number' => '101', 'name' => 'Spell 101', 'vibrant' => '' },
                          { 'number' => '101', 'name' => 'Spell 101', 'vibrant' => 'Vibrant' }])
    end
  end
end
