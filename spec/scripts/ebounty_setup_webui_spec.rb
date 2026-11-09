# frozen_string_literal: true

require_relative '../spec_helper'
require 'tmpdir'
require 'fileutils'

# The setup window is a native WebUI page rendered from the settings hash. These run the
# real EBounty::Setup class against stubs and a recording builder that, like the real one,
# evaluates child blocks with the builder as self.
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

  let(:known_spells) { [] }
  let(:prof) { 'Warrior' }
  let(:blessings) { 0 }
  let(:saved) { [] }
  let(:pushed) { [] }
  let(:game) { 'GSIV' }

  let(:namespace) do
    spells = known_spells
    profession = prof
    ranks = blessings
    saves = saved
    game_name = game
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
      ns.module_eval(setup_source, path)
      ns.const_get(:Setup).class_eval { define_method(:respond) { |*| nil } }
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

  describe 'rendering' do
    it 'has a control for every setting' do
      nodes = render(build)
      general = setup_class.class_variable_get(:@@categories)[:general].keys
      member_lists = %i[bounty_types escort_types forage_options heirloom_options]
      tables = %i[creature_exclude herb_exclude gem_exclude location_exclude]
      paired_names = %i[default_name profile_name_bandits] + ('a'..'j').map { |letter| :"profile_name_#{letter}" }

      (general - member_lists - tables - paired_names - [:only_required_creatures]).each { |key| expect(node(nodes, key)).not_to be_nil, "no control for #{key}" }
      tables.each { |key| expect(node(nodes, "#{key}-table")).not_to be_nil, "no table for #{key}" }
      member_lists.each { |key| expect(nodes.any? { |n| n[:key].to_s.start_with?("#{key}-") }).to be(true), "no boxes for #{key}" }
    end

    it 'offers every escort route, with none from a town to itself' do
      keys = render(build).map { |n| n[:key].to_s }.grep(/\Aescort_types-/)

      expect(keys.size).to eq(30)
      expect(keys.grep(/-(\w+)_to_\1\z/)).to be_empty
      expect(keys).to include('escort_types-landing_to_vaalor')
    end

    it 'disables with disabled:, because sensitive: means a confidential value' do
      expect(render(build).select { |n| n.key?(:sensitive) }).to be_empty
    end

    it 'disables options the character lacks, without changing what is saved' do
      setup = build({ forage_options: ['use_140'] })
      nodes = render(setup)

      expect(node(nodes, 'forage_options-use_140')).to include(disabled: true, checked: true)
      expect(setup.settings[:forage_options]).to eq(['use_140'])
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

    it 'shows Any for a blank boost choice, without changing the setting' do
      setup = build

      expect(node(render(setup), :boost_type)[:value]).to eq('Any')
      expect(setup.settings[:boost_type]).to eq('')
    end

    it 'shows a saved spinner as a whole number, as GTK saved them as floats' do
      expect(node(render(build({ culling_max: 12.0 })), :culling_max)[:value]).to eq(12)
    end

    it 'commits text as it is typed, so Close cannot lose it' do
      expect(node(render(build), :death_script)).to include(change_mode: :input)
    end

    it 'keeps a profile name that has no file' do
      expect(node(render(build({ profile_a: 'Custom' })), :profile_a)).to include(value: 'Custom', editable: true)
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
  end

  describe 'changes' do
    def with_page(setup, *keys)
      pushes = pushed
      components = keys.map { |key| Struct.new(:type, :props, :cid).new(:checkbox, { key: key.to_s }, "cid-#{key}") }
      tree = Object.new.tap { |t| t.define_singleton_method(:each) { components } }
      result = Struct.new(:tree).new(tree)
      page = Object.new
      page.define_singleton_method(:last_render) { result }
      page.define_singleton_method(:set) { |*args| pushes << args }
      setup.instance_variable_set(:@page, page)
    end

    it 'keeps only one resting choice on, in the window too' do
      setup = build({ table_rest: true, custom_rest: true })
      with_page(setup, :table_rest, :custom_rest, :rest_random, :use_script)

      setup.set_check(:bigshot_rest, true)

      expect(setup.settings).to include(bigshot_rest: true, table_rest: false, custom_rest: false, rest_random: false, use_script: false)
      expect(pushed).to include(['cid-table_rest', :checked, false], ['cid-custom_rest', :checked, false])
    end

    it 'does not touch the others when a resting choice is turned off' do
      setup = build({ table_rest: true, bigshot_rest: true })

      setup.set_check(:bigshot_rest, false)

      expect(setup.settings[:table_rest]).to be(true)
    end

    it 'treats rest when mind full and keep hunting as a pair' do
      setup = build({ exp_pause: true })

      setup.set_check(:keep_hunting, true)

      expect(setup.settings).to include(keep_hunting: true, exp_pause: false)
    end

    it 'clears and disables a new bounty on exit when run one bounty is turned off' do
      setup = build({ once_and_done: true, new_bounty_on_exit: true })
      with_page(setup, :new_bounty_on_exit)
      expect(node(render(setup), :new_bounty_on_exit)[:disabled]).to be(false)

      setup.set_check(:once_and_done, false)

      expect(setup.settings[:new_bounty_on_exit]).to be(false)
      expect(pushed).to eq([['cid-new_bounty_on_exit', :checked, false]])
      expect(node(render(setup), :new_bounty_on_exit)[:disabled]).to be(true)
    end

    it 'saves a profile choice to both of its settings' do
      setup = build

      setup.set_profile(:profile_a, :profile_name_a, ' trolls ')

      expect(setup.settings).to include(profile_a: 'trolls', profile_name_a: 'trolls')
    end

    it 'clamps and types spinner values' do
      setup = build

      setup.set_number(:gem_max, 500)
      setup.set_number(:wander_wait, 1.5)

      expect(setup.settings).to include(gem_max: 100, wander_wait: 1.5)
    end

    it 'keeps member lists unique and sorted' do
      setup = build({ bounty_types: %w[skinning culling] })

      setup.toggle_member(:bounty_types, 'rescue', true)
      expect(setup.settings[:bounty_types]).to eq(%w[culling rescue skinning])
      setup.toggle_member(:bounty_types, 'culling', false)
      expect(setup.settings[:bounty_types]).to eq(%w[rescue skinning])
    end

    it 'adds and deletes exclusions, when the list had no duplicates (old code raised here)' do
      setup = build({ gem_exclude: ['zircon'] })

      setup.set_entry(:gem_exclude, '  (?:blue|red) gem ')
      setup.add_entry(:gem_exclude)
      setup.set_entry(:gem_exclude, 'zircon')
      setup.add_entry(:gem_exclude)
      expect(setup.settings[:gem_exclude]).to eq(['(?:blue|red) gem', 'zircon'])
      expect(node(render(setup), 'gem_exclude-entry-2')).not_to be_nil

      setup.delete_entry(:gem_exclude)
      expect(setup.settings[:gem_exclude].size).to eq(2)
      setup.select_row(:gem_exclude, 'row-0')
      setup.delete_entry(:gem_exclude)
      expect(setup.settings[:gem_exclude]).to eq(['zircon'])
    end
  end

  describe 'closing' do
    before do
      namespace.const_set(:Lich, Module.new)
      namespace.const_get(:Lich).const_set(:WebUI, Module.new { define_singleton_method(:close) { |_page| nil } })
    end

    it 'saves once and does not refresh the closed page' do
      setup = build

      setup.act { setup.on_close_clicked }

      expect(saved.size).to eq(1)
      expect(setup.instance_variable_get(:@closed).pop(true)).to eq(:close)
    end

    it 'reports an error from a callback instead of raising it into the dispatcher' do
      expect { build.act { raise 'boom' } }.not_to raise_error
    end
  end
end
