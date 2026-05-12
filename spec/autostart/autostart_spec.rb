# Spec for autostart.lic startup logic:
# 1. Game-agnostic YAML autostart loop (lines 137-150)
# 2. Generic Settings/CharSettings autostart loop (lines 201-233)
#
# We do NOT load the .lic file because it depends on heavy Lich infrastructure
# (Settings, CharSettings, Script, XMLData, Gem::Version, LICH_VERSION, etc.).
# Instead we extract and exercise the relevant code paths through helper methods
# that mirror the production logic.

# -- Mocks ----------------------------------------------------------------

module MockScript
  @running = {}
  @started = []
  @exists  = Hash.new(true)

  class << self
    attr_reader :started

    def running?(name)
      @running.fetch(name, false)
    end

    def start(name, args: [])
      @started << { name: name, args: args }
    end

    def exists?(name)
      @exists.fetch(name, true)
    end

    def set_running(name, val = true)
      @running[name] = val
    end

    def reset!
      @running = {}
      @started = []
      @exists  = Hash.new(true)
    end
  end
end

module MockSettings
  @store = {}

  class << self
    def []=(key, val)
      @store[key] = val
    end

    def [](key)
      @store[key]
    end

    def reset!
      @store = {}
    end
  end
end

module MockCharSettings
  @store = {}

  class << self
    def []=(key, val)
      @store[key] = val
    end

    def [](key)
      @store[key]
    end

    def reset!
      @store = {}
    end
  end
end

module MockXMLData
  class << self
    attr_accessor :game
  end
end

module MockMap
  @applied = false

  class << self
    attr_reader :applied

    def apply_wayto_overrides
      @applied = true
    end

    def respond_to?(method, include_private = false)
      method == :apply_wayto_overrides || super
    end

    def reset!
      @applied = false
    end
  end
end

module MockUserVars
  @store = {}

  class << self
    def autostart_scripts
      @store[:autostart_scripts]
    end

    def autostart_scripts=(val)
      @store[:autostart_scripts] = val
    end

    def reset!
      @store = {}
    end
  end
end

# -- Helper that mirrors the game-agnostic YAML autostart loop ------------

# Replicates lines 137-158 of autostart.lic.
#
# @param script_mod [Module] mock for Script (running?, exists?, start)
# @param map_mod [Module] mock for Map (apply_wayto_overrides)
# @param user_vars_mod [Module] mock for UserVars (autostart_scripts)
# @param yaml_autostarts [Array<String>, nil] simulated get_settings.autostarts
# @param has_get_settings [Boolean] whether get_settings is available
# @param respond_output [Array<String>] collects warning messages
# @return [Array<String>, nil] list of started script names, or nil if skipped
def run_yaml_autostart_loop(script_mod: MockScript,
                            map_mod: MockMap,
                            user_vars_mod: MockUserVars,
                            yaml_autostarts: [],
                            has_get_settings: true,
                            respond_output: [])
  return unless has_get_settings

  user_vars_mod.autostart_scripts ||= []
  all_autostarts = (user_vars_mod.autostart_scripts.to_a +
                    yaml_autostarts.to_a).uniq

  map_mod.apply_wayto_overrides if map_mod.respond_to?(:apply_wayto_overrides)

  started = []
  all_autostarts.each do |script_name|
    next if script_name == 'dependency'
    next if defined?(DR_OBSOLETE_SCRIPTS) && DR_OBSOLETE_SCRIPTS.include?(script_name)
    next if script_mod.running?(script_name)

    unless script_mod.exists?(script_name)
      respond_output << "\n--- autostart: '#{script_name}' not found, skipping\n\n"
      next
    end

    started << script_name
    script_mod.start(script_name)
  end
  started
end

# -- Helper that mirrors the generic Settings/CharSettings autostart loop --

# Replicates lines 199-231 of autostart.lic.
#
# @param settings_mod [Module] mock for Settings
# @param char_settings_mod [Module] mock for CharSettings
# @param script_mod [Module] mock for Script
# @param xml_data_mod [Module] mock for XMLData
# @param lich_version [String] simulated LICH_VERSION
# @param respond_output [Array<String>] collects warning messages
def run_generic_autostart_loop(settings_mod: MockSettings,
                               char_settings_mod: MockCharSettings,
                               script_mod: MockScript,
                               xml_data_mod: MockXMLData,
                               lich_version: "5.7.0",
                               respond_output: [])
  for script_list in [settings_mod['scripts'], char_settings_mod['scripts']]
    if script_list.is_a?(Array)
      for script_info in script_list
        if ['infomon', 'repository', 'dependency'].include?(script_info[:name])
          # dependency removal for DR
          if script_info[:name] == 'dependency' && xml_data_mod.game =~ /^DR/
            respond_output << "dependency removed"
            temp_script_list = settings_mod['scripts']
            if temp_script_list.is_a?(Array) &&
               (temp_script_info = temp_script_list.find { |s| s[:name] == script_info[:name] })
              temp_script_list.delete(temp_script_info)
              settings_mod['scripts'] = temp_script_list
            end
            temp_script_list = char_settings_mod['scripts']
            if temp_script_list.is_a?(Array) &&
               (temp_script_info = temp_script_list.find { |s| s[:name] == script_info[:name] })
              temp_script_list.delete(temp_script_info)
              char_settings_mod['scripts'] = temp_script_list
            end
          end
          next
        elsif script_info[:name] == 'lich5-update' &&
              Gem::Version.new(lich_version) > Gem::Version.new('5.6.2')
          next
        else
          next if script_mod.running?(script_info[:name])

          script_mod.start(script_info[:name], args: script_info[:args])
        end
      end
    end
  end
end

# -- Specs ----------------------------------------------------------------

RSpec.describe "Generic autostart loop" do
  before do
    MockScript.reset!
    MockSettings.reset!
    MockCharSettings.reset!
    MockXMLData.game = "GSIV"
  end

  describe "happy path" do
    it "starts a script that is not already running" do
      MockSettings['scripts'] = [{ name: 'myscript', args: [] }]

      run_generic_autostart_loop
      expect(MockScript.started).to eq([{ name: 'myscript', args: [] }])
    end

    it "starts scripts from both Settings and CharSettings" do
      MockSettings['scripts'] = [{ name: 'script_a', args: [] }]
      MockCharSettings['scripts'] = [{ name: 'script_b', args: ['--verbose'] }]

      run_generic_autostart_loop
      expect(MockScript.started).to contain_exactly(
        { name: 'script_a', args: [] },
        { name: 'script_b', args: ['--verbose'] }
      )
    end
  end

  describe "already running guard (the bug fix)" do
    it "does NOT start a script that is already running" do
      MockSettings['scripts'] = [{ name: 'myscript', args: [] }]
      MockScript.set_running('myscript', true)

      run_generic_autostart_loop
      expect(MockScript.started).to be_empty
    end
  end

  describe "dedup across registries" do
    it "only starts a script once when it appears in both Settings and CharSettings" do
      MockSettings['scripts'] = [{ name: 'shared', args: [] }]
      MockCharSettings['scripts'] = [{ name: 'shared', args: [] }]

      # Simulate production behavior: Script.start makes the script running,
      # so the second iteration's running? check should return true.
      allow(MockScript).to receive(:start).and_wrap_original do |meth, *args, **kwargs|
        meth.call(*args, **kwargs)
        MockScript.set_running(args.first, true)
      end

      run_generic_autostart_loop
      expect(MockScript.started.size).to eq(1)
    end
  end

  describe "empty / nil lists" do
    it "handles nil Settings['scripts'] without error" do
      MockSettings['scripts'] = nil
      MockCharSettings['scripts'] = nil

      expect { run_generic_autostart_loop }.not_to raise_error
      expect(MockScript.started).to be_empty
    end

    it "handles empty array Settings['scripts'] without error" do
      MockSettings['scripts'] = []
      MockCharSettings['scripts'] = []

      expect { run_generic_autostart_loop }.not_to raise_error
      expect(MockScript.started).to be_empty
    end
  end

  describe "non-array Settings['scripts']" do
    it "does not iterate when Settings['scripts'] is a String" do
      MockSettings['scripts'] = "not_an_array"

      expect { run_generic_autostart_loop }.not_to raise_error
      expect(MockScript.started).to be_empty
    end

    it "does not iterate when Settings['scripts'] is a Hash" do
      MockSettings['scripts'] = { name: 'sneaky', args: [] }

      expect { run_generic_autostart_loop }.not_to raise_error
      expect(MockScript.started).to be_empty
    end
  end

  describe "skipped scripts" do
    it "skips infomon" do
      MockSettings['scripts'] = [{ name: 'infomon', args: [] }]

      run_generic_autostart_loop
      expect(MockScript.started).to be_empty
    end

    it "skips repository" do
      MockSettings['scripts'] = [{ name: 'repository', args: [] }]

      run_generic_autostart_loop
      expect(MockScript.started).to be_empty
    end

    it "skips dependency" do
      MockSettings['scripts'] = [{ name: 'dependency', args: [] }]

      run_generic_autostart_loop
      expect(MockScript.started).to be_empty
    end

    it "skips lich5-update when LICH_VERSION > 5.6.2" do
      MockSettings['scripts'] = [{ name: 'lich5-update', args: [] }]

      run_generic_autostart_loop(lich_version: "5.7.0")
      expect(MockScript.started).to be_empty
    end
  end

  describe "DR dependency removal" do
    it "removes dependency from Settings list for DR game" do
      MockXMLData.game = "DRF"
      MockSettings['scripts'] = [{ name: 'dependency', args: [] }]
      output = []

      run_generic_autostart_loop(respond_output: output)
      expect(output).to include("dependency removed")
      expect(MockSettings['scripts']).not_to include(a_hash_including(name: 'dependency'))
    end

    it "removes dependency from CharSettings list for DR game" do
      MockXMLData.game = "DRX"
      MockCharSettings['scripts'] = [{ name: 'dependency', args: [] }]
      output = []

      run_generic_autostart_loop(respond_output: output)
      expect(output).to include("dependency removed")
      expect(MockCharSettings['scripts']).not_to include(a_hash_including(name: 'dependency'))
    end

    it "does NOT remove dependency for non-DR game (still skips it)" do
      MockXMLData.game = "GSIV"
      MockSettings['scripts'] = [{ name: 'dependency', args: [] }]

      run_generic_autostart_loop
      # dependency is skipped but not removed for non-DR games
      expect(MockSettings['scripts']).to include(a_hash_including(name: 'dependency'))
      expect(MockScript.started).to be_empty
    end
  end

  describe "edge case: script_info with empty args" do
    it "starts a script passing empty args array" do
      MockSettings['scripts'] = [{ name: 'noargs', args: [] }]

      run_generic_autostart_loop
      expect(MockScript.started).to eq([{ name: 'noargs', args: [] }])
    end

    it "starts a script passing nil args" do
      MockSettings['scripts'] = [{ name: 'nilargs', args: nil }]

      run_generic_autostart_loop
      expect(MockScript.started).to eq([{ name: 'nilargs', args: nil }])
    end
  end
end

RSpec.describe "YAML autostart loop (game-agnostic)" do
  before do
    MockScript.reset!
    MockMap.reset!
    MockUserVars.reset!
  end

  describe "YAML autostarts" do
    it "starts scripts from YAML autostarts list" do
      started = run_yaml_autostart_loop(yaml_autostarts: ['esp', 'afk'])
      expect(started).to eq(['esp', 'afk'])
    end

    it "does nothing when get_settings is not available" do
      started = run_yaml_autostart_loop(yaml_autostarts: ['esp'], has_get_settings: false)
      expect(started).to be_nil
    end

    it "handles empty YAML autostarts" do
      started = run_yaml_autostart_loop(yaml_autostarts: [])
      expect(started).to eq([])
    end

    it "handles nil YAML autostarts via .to_a" do
      started = run_yaml_autostart_loop(yaml_autostarts: nil)
      expect(started).to eq([])
    end
  end

  describe "UserVars autostarts" do
    it "starts scripts from UserVars.autostart_scripts" do
      MockUserVars.autostart_scripts = ['my-script']
      started = run_yaml_autostart_loop(yaml_autostarts: [])
      expect(started).to eq(['my-script'])
    end

    it "initializes UserVars.autostart_scripts to empty array when nil" do
      MockUserVars.autostart_scripts = nil
      run_yaml_autostart_loop(yaml_autostarts: [])
      expect(MockUserVars.autostart_scripts).to eq([])
    end
  end

  describe "merging UserVars and YAML" do
    it "combines and deduplicates UserVars and YAML autostarts" do
      MockUserVars.autostart_scripts = ['shared', 'uvar-only']
      started = run_yaml_autostart_loop(yaml_autostarts: ['shared', 'yaml-only'])
      expect(started).to contain_exactly('shared', 'uvar-only', 'yaml-only')
    end
  end

  describe "wayto overrides" do
    it "applies Map.apply_wayto_overrides" do
      run_yaml_autostart_loop(yaml_autostarts: [])
      expect(MockMap.applied).to be true
    end
  end

  describe "skip guards" do
    it "skips dependency" do
      started = run_yaml_autostart_loop(yaml_autostarts: ['dependency', 'esp'])
      expect(started).to eq(['esp'])
    end

    it "skips scripts that are already running" do
      MockScript.set_running('esp', true)
      started = run_yaml_autostart_loop(yaml_autostarts: ['esp', 'afk'])
      expect(started).to eq(['afk'])
    end

    it "skips scripts that do not exist" do
      MockScript.reset!
      # Override exists? to return false for a specific script
      allow(MockScript).to receive(:exists?).and_call_original
      allow(MockScript).to receive(:exists?).with('missing').and_return(false)
      started = run_yaml_autostart_loop(yaml_autostarts: ['missing', 'afk'])
      expect(started).to eq(['afk'])
    end
  end

  describe "game-agnostic behavior" do
    it "works for GSIV game type" do
      MockXMLData.game = "GSIV"
      started = run_yaml_autostart_loop(yaml_autostarts: ['esp', 'afk'])
      expect(started).to eq(['esp', 'afk'])
    end

    it "works for DR game type" do
      MockXMLData.game = "DRF"
      started = run_yaml_autostart_loop(yaml_autostarts: ['moonwatch'])
      expect(started).to eq(['moonwatch'])
    end
  end

  describe "GS character with no YAML profiles" do
    it "handles nil autostarts from missing base.yaml and no character profile" do
      MockUserVars.autostart_scripts = nil
      started = run_yaml_autostart_loop(yaml_autostarts: nil)
      expect(started).to eq([])
      expect(MockUserVars.autostart_scripts).to eq([])
    end

    it "still applies wayto overrides even with no autostarts" do
      MockUserVars.autostart_scripts = nil
      run_yaml_autostart_loop(yaml_autostarts: nil)
      expect(MockMap.applied).to be true
    end

    it "handles empty autostarts from base.yaml without autostarts key" do
      started = run_yaml_autostart_loop(yaml_autostarts: [])
      expect(started).to eq([])
    end
  end

  describe "adversarial inputs" do
    it "handles nil entries in UserVars.autostart_scripts" do
      MockUserVars.autostart_scripts = [nil, 'esp', nil]
      allow(MockScript).to receive(:running?).and_call_original
      allow(MockScript).to receive(:exists?).and_call_original
      allow(MockScript).to receive(:running?).with(nil).and_return(false)
      allow(MockScript).to receive(:exists?).with(nil).and_return(false)
      started = run_yaml_autostart_loop(yaml_autostarts: [])
      expect(started).to eq(['esp'])
    end

    it "handles nil entries in YAML autostarts" do
      allow(MockScript).to receive(:running?).and_call_original
      allow(MockScript).to receive(:exists?).and_call_original
      allow(MockScript).to receive(:running?).with(nil).and_return(false)
      allow(MockScript).to receive(:exists?).with(nil).and_return(false)
      started = run_yaml_autostart_loop(yaml_autostarts: [nil, 'afk', nil])
      expect(started).to eq(['afk'])
    end

    it "handles empty string script names" do
      allow(MockScript).to receive(:exists?).and_call_original
      allow(MockScript).to receive(:exists?).with('').and_return(false)
      started = run_yaml_autostart_loop(yaml_autostarts: ['', 'esp'])
      expect(started).to eq(['esp'])
    end

    it "deduplicates across UserVars and YAML when both contain the same script" do
      MockUserVars.autostart_scripts = ['esp', 'afk']
      started = run_yaml_autostart_loop(yaml_autostarts: ['afk', 'esp'])
      expect(started).to eq(['esp', 'afk'])
    end

    it "deduplicates within UserVars itself" do
      MockUserVars.autostart_scripts = ['esp', 'esp', 'esp']
      started = run_yaml_autostart_loop(yaml_autostarts: [])
      expect(started).to eq(['esp'])
    end

    it "deduplicates within YAML autostarts itself" do
      started = run_yaml_autostart_loop(yaml_autostarts: ['afk', 'afk', 'afk'])
      expect(started).to eq(['afk'])
    end

    it "handles both UserVars and YAML being nil simultaneously" do
      MockUserVars.autostart_scripts = nil
      started = run_yaml_autostart_loop(yaml_autostarts: nil)
      expect(started).to eq([])
    end

    it "starts nothing when all scripts are already running" do
      MockScript.set_running('esp', true)
      MockScript.set_running('afk', true)
      started = run_yaml_autostart_loop(yaml_autostarts: ['esp', 'afk'])
      expect(started).to eq([])
    end

    it "starts nothing when no scripts exist on disk" do
      allow(MockScript).to receive(:exists?).and_return(false)
      output = []
      started = run_yaml_autostart_loop(yaml_autostarts: ['fake1', 'fake2'], respond_output: output)
      expect(started).to eq([])
      expect(output.size).to eq(2)
    end

    it "skips dependency even when it appears in both UserVars and YAML" do
      MockUserVars.autostart_scripts = ['dependency']
      started = run_yaml_autostart_loop(yaml_autostarts: ['dependency', 'esp'])
      expect(started).to eq(['esp'])
    end
  end

  describe "missing script warnings" do
    it "warns when a YAML autostart script does not exist" do
      allow(MockScript).to receive(:exists?).and_call_original
      allow(MockScript).to receive(:exists?).with('typo-script').and_return(false)
      output = []
      started = run_yaml_autostart_loop(yaml_autostarts: ['typo-script'], respond_output: output)
      expect(started).to eq([])
      expect(output).to include(a_string_matching(/typo-script.*not found/))
    end

    it "warns when a UserVars autostart script does not exist" do
      MockUserVars.autostart_scripts = ['gone-script']
      allow(MockScript).to receive(:exists?).and_call_original
      allow(MockScript).to receive(:exists?).with('gone-script').and_return(false)
      output = []
      started = run_yaml_autostart_loop(yaml_autostarts: [], respond_output: output)
      expect(started).to eq([])
      expect(output).to include(a_string_matching(/gone-script.*not found/))
    end

    it "warns for each missing script individually" do
      allow(MockScript).to receive(:exists?).and_return(false)
      output = []
      run_yaml_autostart_loop(yaml_autostarts: ['bad1', 'bad2', 'bad3'], respond_output: output)
      expect(output.size).to eq(3)
      expect(output[0]).to match(/bad1/)
      expect(output[1]).to match(/bad2/)
      expect(output[2]).to match(/bad3/)
    end

    it "does not warn for scripts that exist and are started" do
      output = []
      started = run_yaml_autostart_loop(yaml_autostarts: ['esp'], respond_output: output)
      expect(started).to eq(['esp'])
      expect(output).to be_empty
    end

    it "does not warn for scripts that are already running" do
      MockScript.set_running('esp', true)
      output = []
      run_yaml_autostart_loop(yaml_autostarts: ['esp'], respond_output: output)
      expect(output).to be_empty
    end

    it "does not warn for dependency (skipped before exists? check)" do
      output = []
      run_yaml_autostart_loop(yaml_autostarts: ['dependency'], respond_output: output)
      expect(output).to be_empty
    end

    it "warns for missing scripts alongside successful starts" do
      allow(MockScript).to receive(:exists?).and_call_original
      allow(MockScript).to receive(:exists?).with('missing').and_return(false)
      output = []
      started = run_yaml_autostart_loop(yaml_autostarts: ['esp', 'missing', 'afk'], respond_output: output)
      expect(started).to eq(['esp', 'afk'])
      expect(output.size).to eq(1)
      expect(output.first).to match(/missing.*not found/)
    end
  end
end
