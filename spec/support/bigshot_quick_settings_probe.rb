# frozen_string_literal: true

# Run in a subprocess: native Lich constants and GTK thread ownership must not
# leak into the fast unit suite. All database writes go to a temporary directory.
require 'tmpdir'
require 'json'
require 'sequel'
require 'gtk3'
require 'yaml'

native = ARGV.fetch(0)
source = File.read(ARGV.fetch(1)).gsub("\r\n", "\n")
# Native Lich requires these process-wide constants; this probe is isolated.
# rubocop:disable Lint/ConstantDefinitionInBlock
Dir.mktmpdir('quick-settings-probe') do |root|
  DATA_DIR = root
  LIB_DIR = File.join(native, 'lib')
  $LOAD_PATH.unshift(LIB_DIR)
  %w[common/script common/limitedarray common/sharedbuffer].each { |name| require name }
  Object.include Lich::Common
  module Lich
    def self.log(*); end
    def self.open_sequel_sqlite(path); Sequel.sqlite(path); end

    module Messaging
      def self.msg(*); end
    end
  end

  def respond(*); end
  require 'common/class_exts/nilclass'
  require 'common/settings'
  require 'common/settings/charsettings'
  # The application migration creates this index before settings are saved.
  Sequel.sqlite(File.join(root, 'lich.db3')) do |db|
    db.add_index(:script_auto_settings, [:script, :scope], unique: true)
  end
  XMLData = Struct.new(:game, :name).new('GSIV', 'OfflineFixture')
  UserVars = Struct.new(:op).new({})
  $_CLIENTBUFFER_ = LimitedArray.new
  module Probe; end
  %w[EncounterSettings QuickRequest].each do |name|
    Probe.module_eval(source[/^  class #{name}\n.*?^  end$/m])
  end
  Probe.module_eval(source[/^  class Setup < Gtk::Builder\n.*?^  end$/m])
  class Probe::Setup
    def load_settings(*); end
    def set_tooltips; end
  end

  def Gtk.queue(&block)
    GLib::Timeout.add(1) { block.call; false }
  end

  def pump
    done = false
    GLib::Timeout.add(30) { done = true; false }
    Gtk.main_iteration until done
  end

  def with_editor
    pending = Queue.new
    editor = nil
    parent = Script.subscript do
      Script.current.define_singleton_method(:name) { 'bigshot' }
      CharSettings['targetable'] = ['existing target']
      if CharSettings['bigshot_encounters']
        restored = Probe::EncounterSettings.new(CharSettings['bigshot_encounters'])
        raise 'runtime preset failed to reload' unless restored.names.include?('Smoke')
      end
      editor = Probe::Setup.new(profile_current: 'fixture')
      pending.pop
    end
    100.times { pump; break if editor && editor['main'] }
    raise 'editor missing' unless editor && editor['main']
    yield editor
  ensure
    editor['main'].destroy if editor && editor['main'] && !editor['main'].destroyed?
    pending << true
    parent&.join(2)
  end

  with_editor do |editor|
    raise 'GUI must not own a script' unless Script.current.nil?
    editor.instance_variable_get(:@encounter_name).text = 'Smoke'
    editor.instance_variable_get(:@encounter_fields).fetch('fallback_commands').text = 'unarmed jab'
    editor.instance_variable_get(:@quick_trial_name).text = 'fixture-trial'
    editor.instance_variable_get(:@quick_trial_commands).buffer.text = "unarmed jab\nunarmed punch"
    editor.on_close_clicked
    pump
  end
  table = Lich::Common::Settings.instance_variable_get(:@db_adapter).table
  read_settings = lambda do
    row = table.first(script: 'bigshot', scope: 'GSIV:OfflineFixture')
    row ? Marshal.load(row[:hash]) : {}
  end
  saved = read_settings.call
  names = saved.dig('bigshot_encounters', 'presets')&.keys || []
  raise 'saved Smoke preset missing from native database' unless names.include?('Smoke')
  raise 'unrelated settings lost' unless saved['targetable'] == ['existing target']
  # Reopen with a new script owner and a cold cache, like the next setup run.
  Lich::Common::Settings.instance_variable_get(:@settings_cache).clear
  with_editor do |editor|
    settings = editor.instance_variable_get(:@encounter_settings)
    raise 'preset failed to reload' unless settings.preset('Smoke')['fallback_commands'] == 'unarmed jab'
    raise 'trial failed to reload' unless settings.trial('fixture-trial')['actions'] == ['unarmed jab', 'unarmed punch']
    editor.instance_variable_get(:@encounter_name).text = 'Discarded'
    editor.save_encounter_form
    editor['main'].close
    pump
  end
  raise 'window close persisted unsaved edits' unless read_settings.call == saved
  raise 'save leaked into another namespace' unless table.all.all? { |row| row[:script] == 'bigshot' && row[:scope] == 'GSIV:OfflineFixture' }
  puts JSON.generate(preset_names: names, reopened: true, cancel_preserved: true)
end
# rubocop:enable Lint/ConstantDefinitionInBlock
