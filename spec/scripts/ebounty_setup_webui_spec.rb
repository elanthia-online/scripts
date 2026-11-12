# frozen_string_literal: true

require_relative '../spec_helper'
require 'tmpdir'
require 'fileutils'

# The setup window is a Lich::WebUI::ListSettingsForm. These run the real EBounty::Setup
# class against stubs: a stand-in form class that records its options, and a recording
# builder that, like the real one, evaluates child blocks with the builder as self.
RSpec.describe 'EBounty::Setup' do
  let(:path) { find_lic_source('ebounty.lic', from: __dir__) }
  let(:source) { File.read(path, encoding: 'UTF-8') }
  let(:setup_source) { source[/^  class Setup\r?\n.*?(?=^  module Hunting)/m].gsub(/\r\n/, "\n") }

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

      def page = @page ||= Struct.new(:sets) { def set(*args, **kw) = sets << [args, kw] }.new([])
    end
  end

  let(:known_spells) { [] }
  let(:prof) { 'Warrior' }
  let(:blessings) { 0 }
  let(:saved) { [] }
  let(:refreshed) { [] }
  let(:game) { 'GSIV' }

  let(:namespace) do
    spells = known_spells
    profession = prof
    ranks = blessings
    saves = saved
    refreshes = refreshed
    game_name = game
    stub = form_stub
    spell = Struct.new(:num, :known) { def known? = known }
    Module.new.tap do |ns|
      ns.const_set(:Spell, Module.new { define_singleton_method(:[]) { |n| spell.new(n.to_i, spells.include?(n.to_i)) } })
      ns.const_set(:Stats, Module.new { define_singleton_method(:prof) { profession } })
      ns.const_set(:Skills, Module.new { define_singleton_method(:slblessings) { ranks } })
      ns.const_set(:Script, Module.new { define_singleton_method(:current) { :script } })
      ns.const_set(:XMLData, Module.new { define_singleton_method(:game) { game_name } })
      ns.const_set(:Char, Module.new { define_singleton_method(:name) { 'Harness' } })
      ns.const_set(:EBounty, Module.new {
        define_singleton_method(:get_script_version) { '1.13.0' }
        define_singleton_method(:save_profile) { |settings| saves << settings }
        define_singleton_method(:msg) { |*| nil }
      })
      webui = Module.new { define_singleton_method(:refresh) { |page| refreshes << page } }
      webui.const_set(:ListSettingsForm, stub)
      ns.const_set(:Lich, Module.new).const_set(:WebUI, webui)
      ns.module_eval(setup_source, path)
      ns.const_get(:Setup).class_eval { define_method(:respond) { |*| nil } }
    end
  end

  let(:setup_class) { namespace.const_get(:Setup) }

  def build(settings = {})
    setup_class.new(settings)
  end

  # Renders the window's layout (one form per setup, as in a session); fields are
  # recorded with their key, overrides and initial value.
  def render(setup)
    options = (@forms ||= {}.compare_by_identity)[setup] ||= setup.form.options
    ref = Struct.new(:cid)
    ui = recorder_class.new
    field = lambda do |_parent, key, **props|
      ui.nodes << props.merge(type: :field, key: key.to_s, value: options[:values][key])
      ref.new("cid-#{key}")
    end
    options[:layout].call(ui, field, ->(_parent, **props) { ui.nodes << props.merge(type: :save, key: 'save') })
    ui.nodes
  end

  def node(nodes, key)
    nodes.find { |n| n[:key].to_s == key.to_s }
  end

  it 'has no GTK left anywhere in the script' do
    expect(source.sub(/\A.*?^=end/m, '')).not_to match(/\bGtk\b|\bGdk\b|glade|<interface>/i)
  end

  it 'loads with no window system and is available only when Lich can present a window' do
    expect(setup_class.available?).to be_falsey
  end

  it 'uses the current constants when the script is re-run in the same session' do
    setup_class.send(:remove_const, :BOUNTY_TYPES)
    setup_class.const_set(:BOUNTY_TYPES, [].freeze)

    namespace.module_eval(setup_source, path)

    expect(node(render(build), 'bounty_types-rescue')).not_to be_nil
  end

  describe 'opening a profile' do
    it 'fills blank settings with defaults and removes settings that no longer exist' do
      settings = build({ selling_script: '', healing_script: 'mine', retired: true }).settings

      expect(settings).to include(selling_script: 'eloot', healing_script: 'mine', culling_max: 30, wander_wait: 0.5)
      expect(settings).not_to have_key(:retired)
    end

    it 'does not share default arrays between profiles' do
      build.settings[:bounty_types] << 'culling'

      expect(build.settings[:bounty_types]).to eq([])
    end

    it 'uses the resting rooms for the game being played' do
      expect(build.settings[:contempt_resting]).to eq('35603')
    end

    context 'on Shattered' do
      let(:game) { 'GSF' }

      it 'uses the Shattered resting rooms' do
        expect(build.settings).to include(contempt_resting: '', fwi_resting: '3668')
      end
    end
  end

  describe 'the form' do
    let(:setup) { build }
    let(:options) { setup.form.options }

    it 'declares a field for every setting the window shows, and renders each of them' do
      general = setup_class.class_variable_get(:@@categories)[:general].keys
      hidden = %i[default_name profile_name_bandits only_required_creatures] + ('a'..'j').map { |letter| :"profile_name_#{letter}" }
      keys = options[:fields].map { |field| field[:key] }
      lists = options[:lists].keys

      expect(lists).to match_array(%i[creature_exclude herb_exclude gem_exclude location_exclude])
      (general - hidden - lists - setup_class::MEMBERS.keys).each { |key| expect(keys).to include(key), "no field for #{key}" }
      expect(keys.uniq).to eq(keys)

      rendered = render(setup).select { |n| n[:type] == :field }.map { |n| n[:key] }
      declared = keys.map(&:to_s) + lists.flat_map { |key| [key, "#{key}_entry", "#{key}_add", "#{key}_delete"].map(&:to_s) }
      expect(rendered).to match_array(declared)
    end

    it 'offers every escort route, with none from a town to itself' do
      keys = options[:fields].map { |field| field[:key].to_s }.grep(/\Aescort_types-/)

      expect(keys.size).to eq(30)
      expect(keys.grep(/-(\w+)_to_\1\z/)).to be_empty
      expect(keys).to include('escort_types-landing_to_vaalor')
    end

    it 'makes the resting choices one exclusive group and rest/keep hunting another' do
      groups = options[:fields].to_h { |field| [field[:key], field[:exclusive]] }

      expect(groups.values_at(:table_rest, :bigshot_rest, :custom_rest, :rest_random, :use_script).uniq.size).to eq(1)
      expect(groups[:exp_pause]).to eq(groups[:keep_hunting])
      expect(groups[:exp_pause]).not_to eq(groups[:table_rest])
      expect(groups[:join_player]).to be_nil
    end
  end

  describe 'rendering' do
    it 'disables with disabled:, because sensitive: means a confidential value' do
      expect(render(build).select { |n| n.key?(:sensitive) }).to be_empty
    end

    it 'disables options the character lacks, without changing what is saved' do
      setup = build({ forage_options: ['use_140'] })
      nodes = render(setup)

      expect(node(nodes, 'forage_options-use_140')).to include(disabled: true, value: true)
      expect(setup.normalize(setup.form_values)[:forage_options]).to eq(['use_140'])
    end

    context 'with the spell known' do
      let(:known_spells) { [140, 604] }

      it 'enables it' do
        expect(node(render(build), 'forage_options-use_140')[:disabled]).to be(false)
      end

      it 'needs enough blessings lore for the 604 evoke' do
        expect(build.option_known?(:forage_options, 'use_604evoke', 604)).to be(false)
      end
    end

    context 'with enough blessings lore' do
      let(:known_spells) { [604] }
      let(:blessings) { 16 }

      it 'allows the 604 evoke' do
        expect(build.option_known?(:forage_options, 'use_604evoke', 604)).to be(true)
      end
    end

    context 'as neither a rogue nor a ranger' do
      it 'enables gambits only for rogues' do
        expect(build.option_known?(:forage_options, 'use_gambit', nil)).to be(false)
      end

      it 'disables ranger track for everyone else' do
        expect(node(render(build), :ranger_track)[:disabled]).to be(true)
      end
    end

    context 'as a ranger' do
      let(:prof) { 'Ranger' }

      it 'enables ranger track' do
        expect(node(render(build), :ranger_track)[:disabled]).to be(false)
      end
    end

    it 'shows Any for a blank boost choice' do
      expect(build.form_values[:boost_type]).to eq('Any')
    end

    it 'shows a saved spinner as a whole number, as GTK saved them as floats' do
      expect(build({ culling_max: 12.0 }).form_values[:culling_max]).to eq(12)
    end

    it 'shows a spinner on its step' do
      expect([0.2, 0.3]).to include(build({ wander_wait: 0.25 }).form_values[:wander_wait])
    end

    it 'keeps a profile name that has no file' do
      setup = build({ profile_a: 'Custom' })

      expect(setup.form_values[:profile_a]).to eq('Custom')
      expect(setup.form.options[:fields].find { |field| field[:key] == :profile_a }).to include(editable: true)
    end

    it 'lists only yaml files as profiles, and survives a missing folder' do
      Dir.mktmpdir do |dir|
        $data_dir = "#{dir}/"
        setup = build
        expect(setup.profile_options).to eq([{ value: '', label: '' }])

        folder = File.join(dir, 'GSIV', 'Harness', 'bigshot_profiles')
        FileUtils.mkdir_p(folder)
        %w[trolls.yaml kobolds.yaml notes.txt].each { |name| File.write(File.join(folder, name), '') }
        expect(build.profile_options.map { |option| option[:value] }).to eq(['', 'kobolds', 'trolls'])
      ensure
        $data_dir = nil
      end
    end

    it 'clears and disables a new bounty on exit when run one bounty is turned off' do
      setup = build({ once_and_done: true, new_bounty_on_exit: true })
      nodes = render(setup)
      expect(node(nodes, :new_bounty_on_exit)[:disabled]).to be(false)

      node(nodes, :once_and_done)[:on][:change].call(Struct.new(:payload, :viewer_id).new({ value: false }, 'v1'))

      expect(node(render(setup), :new_bounty_on_exit)[:disabled]).to be(true)
    end

    it 'pushes the cleared box to the viewer that turned run one bounty off' do
      setup = build({ once_and_done: true, new_bounty_on_exit: true })
      form = setup.form
      ui = recorder_class.new
      form.options[:layout].call(ui, ->(_p, key, **) { Struct.new(:cid).new("cid-#{key}") }, ->(*, **) {})

      setup.once_and_done_changed(false, 'v1')
      expect(form.page.sets).to eq([[['cid-new_bounty_on_exit', :checked, false], { viewer: 'v1' }]])
      setup.once_and_done_changed(true, 'v1')
      expect(refreshed).to eq([form.page])
    end

    it 'has Cancel and Save & Close, and says what each does' do
      nodes = render(build)

      expect(node(nodes, :cancel)[:label]).to eq('Cancel')
      expect(node(nodes, :save)).to include(variant: :primary)
      expect(node(nodes, 'footer-text')[:content]).to include('Save & Close saves', 'Cancel or closing the window discards')
    end
  end

  describe 'saving' do
    let(:setup) { build({ wander_wait: 0.25, bounty_types: %w[skinning custom], profile_a: 'trolls', profile_name_a: 'trolls' }) }
    let(:draft) { setup.form_values }

    it 'returns the settings, keeping values the window had to adjust when left alone' do
      result = setup.normalize(draft)

      expect(result).to include(wander_wait: 0.25, boost_type: '', bounty_types: %w[custom skinning])
      expect(result).not_to have_key(:profile_name_a)
    end

    it 'takes edits, merging member checkboxes and keeping values the window does not offer' do
      result = setup.normalize(draft.merge('bounty_types-rescue': true, 'bounty_types-skinning': false, gem_max: 50, wander_wait: 1.5, death_script: ' rip '))

      expect(result).to include(bounty_types: %w[custom rescue], gem_max: 50, wander_wait: 1.5, death_script: 'rip')
    end

    it 'saves a changed profile choice to both of its settings' do
      expect(setup.normalize(draft.merge(profile_a: ' kobolds '))).to include(profile_a: 'kobolds', profile_name_a: 'kobolds')
    end

    it 'never saves a new bounty on exit without run one bounty' do
      expect(setup.normalize(draft.merge(once_and_done: false, new_bounty_on_exit: true))[:new_bounty_on_exit]).to be(false)
    end

    it 'refuses a missing number with a message' do
      expect { setup.normalize(draft.merge(gem_max: nil)) }.to raise_error(ArgumentError, /gem_max/)
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
      result = { gem_max: 7 }
      setup.start
      expect(saved.size).to eq(1)
      expect(setup.settings[:gem_max]).to eq(7)
    end
  end

  describe 'exclusion lists' do
    it 'edits a copy, kept unique and sorted' do
      settings = { gem_exclude: ['zircon'] }
      spec = build(settings).form.options[:lists][:gem_exclude]

      spec[:add].call('  (?:blue|red) gem ')
      spec[:add].call('zircon')
      expect(spec[:value].call).to eq(['(?:blue|red) gem', 'zircon'])
      expect(spec[:rows].call).to eq([{ 'entry' => '(?:blue|red) gem' }, { 'entry' => 'zircon' }])
      spec[:delete].call(0)
      expect(spec[:value].call).to eq(['zircon'])
      expect(settings[:gem_exclude]).to eq(['zircon'])
      expect(spec).to include(clear_after_add: true)
    end
  end
end
