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

# -- Helpers that mirror the game-agnostic YAML autostart path -----------
#
# The helpers below are verbatim mirrors of the same-named methods in
# scripts/autostart.lic. As documented at the top of this file, we cannot load
# the .lic (it runs heavy startup side effects), so the pure logic is duplicated
# here and exercised directly. Keep these in sync with the production methods.

# Mirror of autostart.lic#normalize_autostart_entry.
#
# @param entry [String, Hash, nil] a YAML autostart entry.
# @return [Array(String, Array<String>)] the script name and its argument list.
def normalize_autostart_entry(entry)
  if entry.is_a?(Hash)
    name = (entry[:name] || entry['name']).to_s.strip
    args = Array(entry[:args] || entry['args']).map(&:to_s)
    [name, args]
  else
    parts = entry.to_s.split
    [parts.first.to_s, parts[1..].to_a]
  end
end

# Mirror of autostart.lic#yaml_autostart_entries (with injectable source).
#
# @param yaml_autostarts [Array, nil] simulated get_settings.autostarts
# @return [Array<Array(String, Array<String>)>] normalized [name, args] pairs
def build_yaml_autostart_entries(yaml_autostarts: [])
  yaml_autostarts.to_a
                 .map { |entry| normalize_autostart_entry(entry) }
                 .reject { |name, _args| name.nil? || name.empty? }
                 .group_by { |name, _args| name }
                 .map { |_name, group| group.find { |_n, args| !args.empty? } || group.first }
end

# Mirror of autostart.lic#autostart_covered_names (with injectable sources).
#
# @param yaml_autostarts [Array, nil] simulated get_settings.autostarts
# @param settings_scripts [Array, nil] simulated Settings['scripts']
# @param char_scripts [Array, nil] simulated CharSettings['scripts']
# @return [Array<String>] unique, non-blank names already autostarted
def build_autostart_covered_names(yaml_autostarts: [], settings_scripts: nil, char_scripts: nil)
  names = yaml_autostarts.to_a.map { |entry| normalize_autostart_entry(entry).first }
  [settings_scripts, char_scripts].each do |list|
    names.concat(list.map { |info| info[:name] }) if list.is_a?(Array)
  end
  names.compact.map(&:to_s).reject(&:empty?).uniq
end

# Mirror of autostart.lic#migrate_legacy_uservars_autostarts.
#
# Compares the stale UserVars names against the covered set; pushes a quiet
# "clearing" note when all are covered or a loud "ACTION NEEDED" notice naming
# the gap otherwise, then clears the UserVar so the check runs only once. Never
# re-adds or starts anything.
#
# @param user_vars_mod [Module] mock for UserVars (autostart_scripts)
# @param covered [Array<String>] names already covered by YAML/DB autostarts
# @param respond_output [Array<String>] collects notice lines
# @return [void]
def run_legacy_uservars_migration(user_vars_mod: MockUserVars, covered: [], respond_output: [])
  legacy = user_vars_mod.autostart_scripts.to_a
  return if legacy.empty?

  gaps = legacy.map { |entry| normalize_autostart_entry(entry).first }
               .reject { |name| name.nil? || name.empty? }
               .uniq
               .reject { |name| covered.include?(name) }

  if gaps.empty?
    respond_output << "clearing legacy UserVars.autostart_scripts (no longer used; all entries already in YAML/DB)"
  else
    respond_output << "ACTION NEEDED: not in YAML 'autostarts:' or ;autostart DB: #{gaps.join(', ')}"
    respond_output << "add to the profile 'autostarts:' list or via ;autostart add <script> [args]"
  end
  user_vars_mod.autostart_scripts = nil
end

# Replicates the YAML autostart loop of autostart.lic.
#
# @param script_mod [Module] mock for Script (running?, exists?, start)
# @param map_mod [Module] mock for Map (apply_wayto_overrides)
# @param yaml_autostarts [Array, nil] simulated get_settings.autostarts
# @param has_get_settings [Boolean] whether get_settings is available (false on old GS lich)
# @param respond_output [Array<String>] collects warning messages
# @return [Array<String>, nil] list of started script names, or nil if skipped
def run_yaml_autostart_loop(script_mod: MockScript,
                            map_mod: MockMap,
                            yaml_autostarts: [],
                            has_get_settings: true,
                            respond_output: [])
  return unless has_get_settings

  entries = build_yaml_autostart_entries(yaml_autostarts: yaml_autostarts)

  map_mod.apply_wayto_overrides if map_mod.respond_to?(:apply_wayto_overrides)

  started = []
  entries.each do |script_name, args|
    next if script_name == 'dependency'
    next if defined?(DR_OBSOLETE_SCRIPTS) && DR_OBSOLETE_SCRIPTS.include?(script_name)
    next if script_mod.running?(script_name)

    unless script_mod.exists?(script_name)
      respond_output << "\n--- autostart: '#{script_name}' not found, skipping\n\n"
      next
    end

    started << script_name
    script_mod.start(script_name, args: args)
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
                               has_lich_update: true,
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
        elsif script_info[:name] == 'lich5-update' && has_lich_update
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

    it "skips lich5-update when Lich::Util::Update is available" do
      MockSettings['scripts'] = [{ name: 'lich5-update', args: [] }]

      run_generic_autostart_loop(has_lich_update: true)
      expect(MockScript.started).to be_empty
    end

    it "does not skip lich5-update on old lich without Lich::Util::Update" do
      MockSettings['scripts'] = [{ name: 'lich5-update', args: [] }]

      run_generic_autostart_loop(has_lich_update: false)
      expect(MockScript.started).to eq([{ name: 'lich5-update', args: [] }])
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

    it "does nothing when get_settings is not available (old GS lich)" do
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
      started = run_yaml_autostart_loop(yaml_autostarts: nil)
      expect(started).to eq([])
    end

    it "still applies wayto overrides even with no autostarts" do
      run_yaml_autostart_loop(yaml_autostarts: nil)
      expect(MockMap.applied).to be true
    end

    it "handles empty autostarts from base.yaml without autostarts key" do
      started = run_yaml_autostart_loop(yaml_autostarts: [])
      expect(started).to eq([])
    end
  end

  describe "adversarial inputs" do
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

    it "deduplicates within the YAML autostarts list itself" do
      started = run_yaml_autostart_loop(yaml_autostarts: ['afk', 'afk', 'afk'])
      expect(started).to eq(['afk'])
    end

    it "handles nil YAML autostarts" do
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

    it "skips dependency even when it appears twice in the YAML list" do
      started = run_yaml_autostart_loop(yaml_autostarts: ['dependency', 'dependency', 'esp'])
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

RSpec.describe "normalize_autostart_entry" do
  it "normalizes a bare script name to [name, []]" do
    expect(normalize_autostart_entry('lichbot')).to eq(['lichbot', []])
  end

  it "splits a name-with-args string on whitespace" do
    expect(normalize_autostart_entry('lichbot start')).to eq(['lichbot', ['start']])
  end

  it "handles multiple args and collapses extra whitespace" do
    expect(normalize_autostart_entry('  foo  a   b ')).to eq(['foo', ['a', 'b']])
  end

  it "normalizes a symbol-keyed hash" do
    expect(normalize_autostart_entry(name: 'lichbot', args: ['start']))
      .to eq(['lichbot', ['start']])
  end

  it "normalizes a string-keyed hash (as produced by YAML)" do
    expect(normalize_autostart_entry('name' => 'lichbot', 'args' => ['start']))
      .to eq(['lichbot', ['start']])
  end

  it "prefers symbol keys but falls back to string keys" do
    expect(normalize_autostart_entry('name' => 'foo', 'args' => %w[a b]))
      .to eq(['foo', %w[a b]])
  end

  it "coerces non-string hash args to strings" do
    expect(normalize_autostart_entry(name: 'foo', args: [1, :two]))
      .to eq(['foo', ['1', 'two']])
  end

  it "wraps a scalar (non-array) hash args value" do
    expect(normalize_autostart_entry(name: 'foo', args: 'start'))
      .to eq(['foo', ['start']])
  end

  it "returns empty args when a hash omits args" do
    expect(normalize_autostart_entry(name: 'foo')).to eq(['foo', []])
  end

  it "yields a blank name for a nil entry (caller rejects it)" do
    expect(normalize_autostart_entry(nil)).to eq(['', []])
  end

  it "yields a blank name for an empty string" do
    expect(normalize_autostart_entry('')).to eq(['', []])
  end

  it "yields a blank name for a whitespace-only string" do
    expect(normalize_autostart_entry('   ')).to eq(['', []])
  end

  it "yields a blank name for a hash with no name" do
    expect(normalize_autostart_entry(args: ['start'])).to eq(['', ['start']])
  end
end

RSpec.describe "YAML autostart args support" do
  before do
    MockScript.reset!
    MockMap.reset!
    MockUserVars.reset!
  end

  it "passes args from a name-with-args string to Script.start" do
    run_yaml_autostart_loop(yaml_autostarts: ['lichbot start'])
    expect(MockScript.started).to eq([{ name: 'lichbot', args: ['start'] }])
  end

  it "passes args from a symbol-keyed hash entry" do
    run_yaml_autostart_loop(yaml_autostarts: [{ name: 'lichbot', args: ['start'] }])
    expect(MockScript.started).to eq([{ name: 'lichbot', args: ['start'] }])
  end

  it "passes args from a string-keyed hash entry" do
    run_yaml_autostart_loop(yaml_autostarts: [{ 'name' => 'lichbot', 'args' => ['start'] }])
    expect(MockScript.started).to eq([{ name: 'lichbot', args: ['start'] }])
  end

  it "starts a bare-name entry with empty args (backward compatible)" do
    run_yaml_autostart_loop(yaml_autostarts: ['esp'])
    expect(MockScript.started).to eq([{ name: 'esp', args: [] }])
  end

  it "rejects nil-name and empty-name entries before starting" do
    started = run_yaml_autostart_loop(yaml_autostarts: [nil, '', '   ', 'esp'])
    expect(started).to eq(['esp'])
    expect(MockScript.started).to eq([{ name: 'esp', args: [] }])
  end

  it "de-dups duplicate names in the list; when both carry args the first wins" do
    started = run_yaml_autostart_loop(
      yaml_autostarts: ['lichbot start', { name: 'lichbot', args: ['stop'] }]
    )
    expect(started).to eq(['lichbot'])
    # Both carry args, so first occurrence ('start') wins over 'stop'.
    expect(MockScript.started).to eq([{ name: 'lichbot', args: ['start'] }])
  end

  it "lets an args entry win over a bare duplicate regardless of order" do
    # A bare 'lichbot' listed before 'lichbot start' must not strip the args.
    started = run_yaml_autostart_loop(yaml_autostarts: ['lichbot', 'lnet', 'lichbot start'])
    expect(started).to eq(['lichbot', 'lnet'])
    expect(MockScript.started).to eq([
                                       { name: 'lichbot', args: ['start'] },
                                       { name: 'lnet', args: [] }
                                     ])
  end

  it "lets an args entry win even when the bare duplicate comes later" do
    started = run_yaml_autostart_loop(yaml_autostarts: ['lichbot start', 'lichbot'])
    expect(started).to eq(['lichbot'])
    expect(MockScript.started).to eq([{ name: 'lichbot', args: ['start'] }])
  end

  it "applies the dependency skip-guard to normalized entries" do
    started = run_yaml_autostart_loop(yaml_autostarts: ['dependency start', 'esp'])
    expect(started).to eq(['esp'])
  end
end

RSpec.describe "autostart_covered_names" do
  it "collects names from the YAML autostarts list" do
    covered = build_autostart_covered_names(yaml_autostarts: ['lichbot start', 'lnet'])
    expect(covered).to contain_exactly('lichbot', 'lnet')
  end

  it "collects names from the global and per-character DB lists" do
    covered = build_autostart_covered_names(
      settings_scripts: [{ name: 'alias', args: [] }],
      char_scripts: [{ name: 'go2', args: [] }]
    )
    expect(covered).to contain_exactly('alias', 'go2')
  end

  it "unions and de-dups across YAML and DB, ignoring blanks" do
    covered = build_autostart_covered_names(
      yaml_autostarts: ['lichbot start', '', nil],
      settings_scripts: [{ name: 'lichbot', args: [] }, { name: 'alias', args: [] }]
    )
    expect(covered).to contain_exactly('lichbot', 'alias')
  end

  it "tolerates non-array DB lists" do
    covered = build_autostart_covered_names(yaml_autostarts: ['lnet'], settings_scripts: 'nope')
    expect(covered).to eq(['lnet'])
  end
end

RSpec.describe "legacy UserVars.autostart_scripts migration" do
  before do
    MockUserVars.reset!
  end

  it "does nothing when UserVars.autostart_scripts is nil" do
    MockUserVars.autostart_scripts = nil
    output = []
    run_legacy_uservars_migration(respond_output: output)
    expect(output).to be_empty
    expect(MockUserVars.autostart_scripts).to be_nil
  end

  it "does nothing when UserVars.autostart_scripts is empty" do
    MockUserVars.autostart_scripts = []
    output = []
    run_legacy_uservars_migration(respond_output: output)
    expect(output).to be_empty
  end

  it "quietly clears when every entry is already covered by YAML/DB" do
    # The real-world case: bare 'lichbot' in UserVars is covered by 'lichbot start'
    # in YAML; the rest are covered too. No loud warning, just a clearing note.
    MockUserVars.autostart_scripts = ['lichbot', 'lnet']
    output = []
    run_legacy_uservars_migration(covered: ['lichbot', 'lnet'], respond_output: output)

    joined = output.join("\n")
    expect(joined).to match(/clearing/i)
    expect(joined).not_to match(/ACTION NEEDED/)
    expect(MockUserVars.autostart_scripts).to be_nil
  end

  it "loudly warns about entries missing from both YAML and DB, then clears" do
    MockUserVars.autostart_scripts = ['lichbot', 'orphan1', 'orphan2']
    output = []
    run_legacy_uservars_migration(covered: ['lichbot'], respond_output: output)

    joined = output.join("\n")
    expect(joined).to match(/ACTION NEEDED/)
    expect(joined).to match(/orphan1, orphan2/)
    expect(joined).not_to match(/\blichbot\b/) # covered entry is not called out as a gap
    expect(joined).to match(/autostarts:/)
    expect(joined).to match(/autostart add/)
    expect(MockUserVars.autostart_scripts).to be_nil
  end

  it "treats every entry as a gap when nothing is covered" do
    MockUserVars.autostart_scripts = ['a', 'b']
    output = []
    run_legacy_uservars_migration(covered: [], respond_output: output)
    joined = output.join("\n")
    expect(joined).to match(/ACTION NEEDED/)
    expect(joined).to match(/a, b/)
    expect(MockUserVars.autostart_scripts).to be_nil
  end

  it "fires only once (second run is a no-op after clearing)" do
    MockUserVars.autostart_scripts = ['orphan']
    first = []
    run_legacy_uservars_migration(covered: [], respond_output: first)
    expect(first).not_to be_empty

    second = []
    run_legacy_uservars_migration(covered: [], respond_output: second)
    expect(second).to be_empty
  end
end
