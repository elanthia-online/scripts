# frozen_string_literal: true

require_relative '../spec_helper'

# The setup window is a native WebUI page rendered from the settings hash. These run the
# real Ewaggle::Setup class against stubs and a recording builder that, like the real one,
# evaluates child blocks with the builder as self.
RSpec.describe 'Ewaggle::Setup' do
  let(:path) { find_lic_source('ewaggle.lic', from: __dir__) }
  let(:source) { File.read(path, encoding: 'UTF-8') }
  let(:setup_source) { source[/^  class Setup\r?\n.*?^  end\r?\n(?=end\r?\n)/m].gsub(/\r\n/, "\n") }

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

  let(:known) { { 101 => 'Spirit Warding I', 107 => 'Spirit Shield', 712 => 'Cloak of Shadows', 1009 => 'Sonic Shield', 1012 => 'Sonic Weapon' } }
  let(:saved) { [] }

  let(:namespace) do
    spells = known
    saves = saved
    spell = Struct.new(:num, :name, :time_per, :known) { def known? = known }
    Module.new.tap do |ns|
      ns.const_set(:Spell, Module.new {
        define_singleton_method(:[]) { |n| spell.new(n.to_i, spells.fetch(n.to_i, "Spell #{n}"), 1, spells.key?(n.to_i)) }
        define_singleton_method(:list) { spells.keys.map { |n| self[n] } }
      })
      ns.const_set(:Society, Module.new {
        define_singleton_method(:membership) { 'None' }
        define_singleton_method(:rank) { 0 }
      })
      ns.const_set(:Armor, Module.new { define_singleton_method(:known?) { |_name| false } })
      ns.const_set(:Script, Module.new { define_singleton_method(:current) { Struct.new(:name).new('ewaggle') } })
      ns.const_set(:Ewaggle, Module.new {
        define_singleton_method(:get_script_version) { '2.2.0' }
        define_singleton_method(:armor_spells) { {} }
        define_singleton_method(:save_profile) { saves << :saved }
        define_singleton_method(:data) { Struct.new(:settings).new({}) }
      })
      form = Module.new { define_singleton_method(:choice_options) { |choices| choices.map { |v| { value: v, label: v } } } }
      ns.const_set(:Lich, Module.new { const_set(:WebUI, Module.new { const_set(:SettingsForm, form) }) })
      ns.module_eval(setup_source, path)
      ns.const_get(:Setup).class_eval { define_method(:respond) { |*| nil } }
    end
  end

  let(:setup_class) { namespace.const_get(:Setup) }

  def build(settings = {})
    setup_class.new({ cast_list: [] }.merge(settings))
  end

  # Stands in for SettingsForm's field renderer: emits the field definition as a component.
  def render(setup)
    field = lambda do |ui, key, **overrides|
      definition = setup.fields.find { |f| f[:key] == key }
      ui.public_send(definition[:type], **definition.reject { |name, _| name == :type }, **overrides, key: key.to_s)
    end
    save = ->(ui, **props) { ui.button(key: 'save', label: 'Save & Close', **props) }
    recorder_class.new.tap { |ui| setup.render(ui, field, save, -> {}) }.nodes
  end

  def node(nodes, key)
    nodes.find { |n| n[:key].to_s == key.to_s }
  end

  it 'has no GTK calls left in the script' do
    expect(source.sub(/\A.*?^=end/m, '')).not_to match(/\bGtk\.|Gtk::Builder\b(?! window)|\bGdk\b|<interface>/)
  end

  it 'uses the current constants when the script is re-run in the same session' do
    setup_class.send(:remove_const, :SPINS)
    setup_class.const_set(:SPINS, {}.freeze)

    namespace.module_eval(setup_source, path)

    expect(node(render(build), :start_at)).not_to be_nil
  end

  it 'fills defaults and removes settings that no longer exist' do
    settings = build({ retired: true }).settings

    expect(settings).to include(start_at: 180, reserve_mana: 0, use_multicast: true)
    expect(settings).not_to have_key(:retired)
  end

  it 'forces off options the character cannot use and does not show them' do
    setup = build({ use_203: true, use_wracking: true })
    nodes = render(setup)

    expect(setup.settings).to include(use_203: false, use_wracking: false)
    expect(node(nodes, :use_203)).to be_nil
  end

  it 'drops cast-list spells the character no longer knows and lists the rest as not cast' do
    settings = build({ cast_list: ['101  Spirit Warding I', '999  Forgotten'] }).settings

    expect(settings[:cast_list]).to eq(['101  Spirit Warding I'])
    expect(settings[:not_to_cast]).to include('107  Spirit Shield')
    expect(settings[:not_to_cast]).not_to include('101  Spirit Warding I')
  end

  it 'restores the GTK hints on the text fields' do
    nodes = render(build)

    expect(node(nodes, :sonic_weapon)).to include(placeholder: 'Name of sonic weapon (follow link for options)')
    expect(node(nodes, :sonic_shield)).to include(placeholder: 'Name of sonic shield (follow link for options)')
    expect(node(nodes, :retribution_spell)).to include(placeholder: 'Spell Number Only')
  end

  it 'renders Save & Close and Cancel, and no live change handlers on fields' do
    nodes = render(build)

    expect(node(nodes, :save)).to include(label: 'Save & Close')
    expect(node(nodes, :cancel)).to include(label: 'Cancel')
    expect(node(nodes, :use_multicast)).not_to have_key(:on)
  end

  it 'gives spells that share a number unique row keys' do
    setup = build({ cast_list: ['101  Spirit Warding I', '101 Spirit Warding I'] })

    expect(setup.row_keys.values).to contain_exactly('spell-101', 'spell-101-2', 'spell-107', 'spell-712', 'spell-1009', 'spell-1012')
  end

  it 'moves spells between the lists, and ignores a drop on the list they are in' do
    setup = build

    setup.move_spell('spell-107', :cast_list)
    expect(setup.settings[:cast_list]).to eq(['107  Spirit Shield'])
    expect(setup.settings[:not_to_cast]).not_to include('107  Spirit Shield')

    setup.move_spell('spell-107', :cast_list)
    expect(setup.settings[:cast_list]).to eq(['107  Spirit Shield'])
  end

  it 'moves the selected spell with the buttons, and says so when nothing is selected' do
    setup = build

    setup.select_row(:not_to_cast, 'spell-101')
    setup.move_selected(:cast_list)
    expect(setup.settings[:cast_list]).to include('101  Spirit Warding I')

    setup.move_selected(:cast_list)
    expect(setup.status).to include('Select a spell')
  end

  describe 'saving' do
    it 'coerces submitted values and takes both lists from the window' do
      setup = build
      setup.move_spell('spell-107', :cast_list)

      result = setup.normalize(setup.settings.merge(use_multicast: nil, start_at: '999', sonic_weapon: ' sword ', cast_list: []))

      expect(result).to include(use_multicast: false, start_at: 250, sonic_weapon: 'sword', cast_list: ['107  Spirit Shield'])
      expect(result[:not_to_cast]).not_to include('107  Spirit Shield')
    end

    it 'reports an error from a callback instead of raising it into the dispatcher' do
      expect { build.act { raise 'boom' } }.not_to raise_error
    end
  end
end
