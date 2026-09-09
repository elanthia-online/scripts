require 'yaml'
require 'tmpdir'

module BigshotEncounterSettingsSpec
  SOURCE = File.read(File.expand_path('../../scripts/bigshot.lic', __dir__)).gsub("\r\n", "\n")
  SETTINGS_SOURCE = SOURCE[/^  class EncounterSettings\n.*?^  end$/m]
  raise 'EncounterSettings source missing' unless SETTINGS_SOURCE

  module Harness
    module_eval(SETTINGS_SOURCE)
    module_eval(SOURCE[/^  class QuickRequest\n.*?^  end$/m])
  end
end

RSpec.describe BigshotEncounterSettingsSpec::Harness::EncounterSettings do
  it 'defaults to an inert policy and returns independent copies' do
    settings = described_class.new
    expect(settings.preset).to include('unknown' => 'ignore', 'loot' => 'off', 'safety_action' => 'hold')
    copy = settings.to_h
    copy['presets']['default']['fallback_commands'].replace('attack target')
    expect(settings.preset['fallback_commands']).to eq('')
    expect(described_class::DEFAULTS['fallback_commands']).to eq('')
  end

  it 'keeps presets separate, persists selection and copies caller data' do
    settings = described_class.new
    fallback = { 'profile' => 'temple', 'mode' => 'assist', 'unknown' => 'group',
                 'fallback_commands' => 'jab target', 'excluded_creatures' => 'town guard' }
    settings.save('invasion', fallback)
    fallback['fallback_commands'].replace('kick target')
    settings.select('invasion')
    restored = described_class.new(settings.to_h)
    expect(restored.selected).to eq('invasion')
    expect(restored.preset['fallback_commands']).to eq('jab target')
    expect(restored.preset('default')['unknown']).to eq('ignore')
    restored.delete('invasion')
    expect(restored.selected).to eq('default')
    expect { restored.delete('default') }.to raise_error(ArgumentError, /at least one/)
  end

  it 'migrates old presets with independent loot defaults and roundtrips overrides' do
    settings = described_class.new('presets' => { 'old' => { 'max_actions' => 2 } }, 'selected_preset' => 'old')
    expect(settings.preset).to include('max_actions' => 2, 'loot_max_actions' => 60, 'loot_max_seconds' => 60)
    settings.save('old', settings.preset.merge('loot_max_actions' => '40', 'loot_max_seconds' => '30'))
    expect(described_class.new(settings.to_h).preset).to include('loot_max_actions' => 40, 'loot_max_seconds' => 30)
    %w[loot_max_actions loot_max_seconds].each do |key|
      [0, -1, 1.5, 'Infinity'].each do |value|
        expect { described_class.normalize(key => value) }.to raise_error(ArgumentError)
      end
    end
  end

  it 'rejects invalid enums, unbounded limits and unknown settings' do
    [{ 'unknown' => 'attack-everything' }, { 'loot' => 'all' }, { 'max_actions' => 0 },
     { 'max_seconds' => 'Infinity' }, { 'max_ineffective' => 1.5 }, { 'oops' => true }].each do |values|
      expect { described_class.normalize(values) }.to raise_error(ArgumentError)
    end
    expect(described_class.normalize('max_actions' => '3')['max_actions']).to eq(3)
  end

  it 'rejects malformed stored state instead of silently replacing it' do
    [[], { 'version' => 99 }, { 'presets' => {} }, { 'selected_preset' => 'missing' }, { 'trials' => [] }].each do |state|
      expect { described_class.new(state) }.to raise_error(ArgumentError)
    end
  end

  it 'roundtrips independent named trials in the request resolver format' do
    settings = described_class.new
    commands = ['jab target', 'grapple target']
    settings.save_trial('uac-opening', 'actions' => commands, 'max_actions' => '3', 'max_seconds' => '20')
    commands.first.replace('kick target')
    restored = described_class.new(settings.to_h)
    expect(restored.trial_names).to eq(['uac-opening'])
    request_class = BigshotEncounterSettingsSpec::Harness::QuickRequest
    resolved = request_class.resolve(request_class.parse(%w[trial uac-opening --target 123]), restored.to_h, {}, '/unused')
    expect(resolved[:trial]).to eq(target_id: '123', actions: ['jab target', 'grapple target'])
    expect(resolved[:settings]).to include('max_actions' => 3, 'max_seconds' => 20)
    restored.delete_trial('uac-opening')
    expect(restored.trial_names).to be_empty
    expect(settings.trial_names).to eq(['uac-opening'])
  end

  it 'rejects malformed trial commands and limits before changing stored trials' do
    settings = described_class.new
    settings.save_trial('opening', 'actions' => ['jab target'])
    [{ 'actions' => [] }, { 'actions' => ["jab target\nkick target"] },
     { 'actions' => ['jab target'], 'max_actions' => 0 }, { 'actions' => ['jab target'], 'max_seconds' => 'Infinity' },
     { 'actions' => ['jab target'], 'repeat' => true }].each do |sequence|
      expect { settings.save_trial('opening', sequence) }.to raise_error(ArgumentError)
    end
    expect(settings.trial('opening')).to eq('actions' => ['jab target'])
  end

  it 'snapshots current settings without mutating nested values or selecting a profile' do
    current = { 'profile_current' => 'ordinary', 'boons_ignore' => ['ethereal'] }
    snapshot = described_class.profile_snapshot(current, '/unused')
    snapshot['boons_ignore'] << 'regen'
    snapshot['profile_current'] = 'invasion'
    expect(current).to eq('profile_current' => 'ordinary', 'boons_ignore' => ['ethereal'])
    expect { described_class.profile_snapshot([], '/unused') }.to raise_error(ArgumentError, /mapping/)
  end

  it 'reads legacy symbol-key profiles without altering current settings' do
    Dir.mktmpdir('bigshot-encounter-profile') do |directory|
      File.write(File.join(directory, 'temple.yaml'), { targets: 'spider', hunting_commands: 'attack target' }.to_yaml)
      current = { 'profile_current' => 'ordinary' }
      expect(described_class.profile_snapshot(current, directory, 'temple')).to eq(
        'targets' => 'spider', 'hunting_commands' => 'attack target'
      )
      expect(current['profile_current']).to eq('ordinary')
      expect { described_class.profile_snapshot(current, directory, '../temple') }.to raise_error(ArgumentError, /path/)
      File.write(File.join(directory, 'invalid.yaml'), [].to_yaml)
      expect { described_class.profile_snapshot(current, directory, 'invalid') }.to raise_error(ArgumentError, /mapping/)
    end
  end
end

module BigshotEncounterSettingsSpec
  class EditorHarness
    EncounterSettings = Harness::EncounterSettings
    CharSettings = {}
    UserVars = Struct.new(:op).new({ 'profile_current' => 'ordinary' })
    module Lich
      module Messaging
        def self.msg(*); end
      end
    end

    module Gtk
      class Widget
        attr_accessor :wrap, :xalign, :hexpand, :row_spacing, :column_spacing, :margin, :text, :active_id, :height_request
        attr_reader :children

        def initialize(text = nil, *)
          @text = text
          @children = []
        end

        def attach(child, *)
          @children << child
        end

        def add(child)
          @children << child
        end

        def pack_start(child, **)
          @children << child
        end

        def signal_connect(*); end
        def append(*); end
        def remove_all; end

        def buffer
          @buffer ||= Struct.new(:text).new('')
        end
      end
      %i[Label Grid ComboBoxText Entry Box Button ScrolledWindow TextView].each { |name| const_set(name, Class.new(Widget)) }
    end
    Field = Struct.new(:text, :active_id)
    Window = Struct.new(:destroyed) do
      def destroy
        self.destroyed = true
      end

      def append_page(child, title)
        @pages ||= []
        @pages << [child, title]
      end

      def pages
        @pages || []
      end
    end
    attr_reader :window, :encounter_settings, :encounter_fields, :encounter_message

    def initialize
      @encounter_store = CharSettings
      @encounter_settings = EncounterSettings.new
      @encounter_name = Field.new('default')
      @encounter_message = Field.new('')
      @encounter_fields = @encounter_settings.preset.each_with_object({}) do |(key, value), out|
        out[key] = Field.new(value.to_s, value)
      end
      @settings = UserVars.op.dup
      @window = Window.new(false)
      CharSettings.clear
    end

    def refresh_encounter_presets; end
    def pre_save; end

    def [](_name)
      @window
    end

    %w[save_encounter_form on_close_clicked build_encounter_tab show_encounter_preset
       build_quick_trial_editor refresh_quick_trials new_quick_trial load_quick_trial save_quick_trial delete_quick_trial].each do |name|
      class_eval(SOURCE[/^    def #{name}(?:\n|\().*?^    end$/m])
    end
  end
end

RSpec.describe BigshotEncounterSettingsSpec::EditorHarness do
  def trial_widget(editor, name)
    editor.instance_variable_get("@quick_trial_#{name}")
  end

  it 'labels Quick Combat and explains the guard dependency, loot ownership and budgets' do
    editor = described_class.new
    editor.build_encounter_tab
    scroll, title = editor.window.pages.last
    expect(title.text).to eq('Quick Combat')
    labels = scroll.children.first.children.grep(described_class::Gtk::Label).map(&:text)
    expect(labels).to include(
      'Maximum actions per target (whole run for trials)',
      'Maximum seconds per target (whole run for trials)',
      'Maximum ineffective actions per target'
    )
    expect(labels.first).to start_with('Quick Combat requires Lich execution guard support. Existing bare quick is unchanged.')
    expect(labels).to include('Designated looter (blank = this character)')
  end

  it 'stages preset edits and only persists them on Close, preserving the combat profile' do
    editor = described_class.new
    editor.encounter_fields['fallback_commands'].text = 'jab target'
    expect(editor.save_encounter_form).to eq(true)
    expect(described_class::CharSettings).to eq({})
    editor.on_close_clicked
    stored = described_class::CharSettings.fetch('bigshot_encounters')
    expect(stored['presets']['default']['fallback_commands']).to eq('jab target')
    expect(described_class::UserVars.op).to eq('profile_current' => 'ordinary')
    expect(editor.window.destroyed).to eq(true)
  end

  it 'keeps the editor open and does not persist invalid limits' do
    editor = described_class.new
    editor.encounter_fields['max_seconds'].text = '0'
    editor.on_close_clicked
    expect(editor.window.destroyed).to eq(false)
    expect(described_class::CharSettings).to eq({})
    expect(editor.encounter_message.text).to include('positive whole number')
  end

  it 'preserves malformed encounter data and allows normal setup to close' do
    editor = described_class.new
    malformed = { 'version' => 999, 'presets' => [] }
    described_class::CharSettings['bigshot_encounters'] = malformed
    expect { editor.build_encounter_tab }.not_to raise_error
    expect(editor.encounter_settings).to be_nil
    notice, title = editor.window.pages.last
    expect(title.text).to eq('Quick Combat')
    expect(notice.text).to start_with('Quick Combat configuration could not be loaded:')
    editor.on_close_clicked
    expect(editor.window.destroyed).to eq(true)
    expect(described_class::CharSettings['bigshot_encounters']).to equal(malformed)
    expect(described_class::UserVars.op).to eq('profile_current' => 'ordinary')
  end

  it 'edits named multiline trials and saves them separately from the hunting profile on Close' do
    editor = described_class.new
    editor.build_encounter_tab
    trial_widget(editor, 'name').text = 'uac-opening'
    trial_widget(editor, 'commands').buffer.text = "jab target\n\ngrapple target\n"
    trial_widget(editor, 'max_actions').text = '3'
    trial_widget(editor, 'max_seconds').text = '20'
    expect(editor.save_quick_trial).to eq(true)
    expect(described_class::CharSettings).to be_empty
    editor.new_quick_trial
    trial_widget(editor, 'picker').active_id = 'uac-opening'
    editor.load_quick_trial
    expect(trial_widget(editor, 'commands').buffer.text).to eq("jab target\ngrapple target")
    expect(trial_widget(editor, 'max_actions').text).to eq('3')
    expect(trial_widget(editor, 'max_seconds').text).to eq('20')
    editor.on_close_clicked
    expect(described_class::CharSettings['bigshot_encounters']['trials']['uac-opening']).to eq(
      'actions' => ['jab target', 'grapple target'], 'max_actions' => 3, 'max_seconds' => 20
    )
    expect(described_class::UserVars.op).to eq('profile_current' => 'ordinary')
  end

  it 'validates an edited trial on Close and leaves the window open with a useful error' do
    editor = described_class.new
    editor.build_encounter_tab
    trial_widget(editor, 'name').text = 'opening'
    trial_widget(editor, 'commands').buffer.text = 'jab target'
    trial_widget(editor, 'max_seconds').text = '0'
    editor.on_close_clicked
    expect(editor.encounter_message.text).to include('Trial max_seconds must be a positive whole number')
    expect(editor.window.destroyed).to eq(false)
    expect(described_class::CharSettings).to be_empty
    expect(editor.encounter_settings.trial_names).to be_empty
  end

  it 'reports missing commands and allows blank trial limits to inherit the preset' do
    editor = described_class.new
    editor.build_encounter_tab
    trial_widget(editor, 'name').text = 'opening'
    expect(editor.save_quick_trial).to eq(false)
    expect(editor.encounter_message.text).to include('at least one trial command')
    trial_widget(editor, 'commands').buffer.text = 'jab target'
    expect(editor.save_quick_trial).to eq(true)
    expect(editor.encounter_settings.trial('opening')).to eq('actions' => ['jab target'])
  end

  it 'stages trial deletion and allows saving an empty trial collection' do
    editor = described_class.new
    editor.build_encounter_tab
    trial_widget(editor, 'name').text = 'opening'
    trial_widget(editor, 'commands').buffer.text = 'jab target'
    editor.save_quick_trial
    editor.delete_quick_trial
    expect(editor.encounter_settings.trial_names).to be_empty
    expect(described_class::CharSettings).to be_empty
    expect(trial_widget(editor, 'commands').buffer.text).to eq('')
    editor.on_close_clicked
    expect(described_class::CharSettings['bigshot_encounters']['trials']).to eq({})
    expect(editor.window.destroyed).to eq(true)
  end
end
