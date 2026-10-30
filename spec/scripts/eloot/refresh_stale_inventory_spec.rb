# frozen_string_literal: true

require_relative '../../spec_helper'

# eloot stays loaded between runs, so its stow and ready lists were only checked on its
# first start. Reported: a gem satchel's id changed (1149885643 cached, 1150702446 worn),
# and every later ;eloot sell failed to find it.
RSpec.describe 'ELoot stale stow list' do
  let(:eloot_path) { find_lic_source('eloot.lic', from: File.expand_path('..', __dir__)) }
  let(:source) { File.read(eloot_path) }

  # A stand-in for Lich's StowList/ReadyList: valid? flips checked off when a stored
  # object is no longer worn, and check re-reads the list.
  let(:list_class) do
    Class.new do
      attr_reader :checks
      attr_accessor :fixed_by_check

      def initialize(checked:, valid:)
        @checked = checked
        @valid = valid
        @checks = 0
        @fixed_by_check = true
      end

      def stow_list = { default: Struct.new(:id).new('1149885643') }

      def checked? = @checked

      def valid?
        @checked = false unless @valid
        @checked && @valid
      end

      def check(**)
        @checks += 1
        @checked = true
        @valid = fixed_by_check
      end
    end
  end

  describe 'ELoot.refresh_stale_inventory' do
    let(:inventory_runs) { [] }
    let(:eloot) do
      runs = inventory_runs
      Module.new do
        define_singleton_method(:msg) { |**| nil }
        define_singleton_method(:set_inventory) do
          runs << :set_inventory
          StowList.check
        end
      end
    end

    before do
      stub_const('ELoot', eloot)
      eloot.module_eval(extract_lic_method(source, 'refresh_stale_inventory', source_path: eloot_path))
    end

    it 'sets up the inventory again when a stow container is gone' do
      stub_const('StowList', list_class.new(checked: true, valid: false))

      eloot.refresh_stale_inventory

      expect(inventory_runs).to eq([:set_inventory])
    end

    it 'leaves the inventory alone when the stow list still matches' do
      stub_const('StowList', list_class.new(checked: true, valid: true))

      eloot.refresh_stale_inventory

      expect(inventory_runs).to be_empty
    end

    # stow targets must be worn, but one taken off can still be listed
    it 'refreshes once, not every run, for a stow container that was taken off' do
      stow = list_class.new(checked: true, valid: false)
      stow.fixed_by_check = false
      stub_const('StowList', stow)

      3.times { eloot.refresh_stale_inventory }

      expect(inventory_runs).to eq([:set_inventory])
    end
  end

  describe 'the main start-up gate' do
    # eloot.lic's top-level "Initialize/Load settings" block, run against stubs
    let(:gate) do
      start = source.index("  # Initialize/Load settings\n")
      finish = source.index("\n  end\n", start) + "\n  end\n".length
      source[start...finish]
    end

    let(:calls) { [] }

    def run_gate(loaded_version)
      calls = self.calls
      data = loaded_version && Struct.new(:version).new(loaded_version)
      stub_const('ELoot', Module.new do
        define_singleton_method(:data) { data }
        define_singleton_method(:get_script_version) { '2.14.2' }
        %i[refresh_stale_inventory set_inventory disk_usage].each do |m|
          define_singleton_method(m) { calls << m }
        end
        define_singleton_method(:load) { |_| calls << :load }
        define_singleton_method(:load_profile) { {} }
      end)
      stub_const('Script', Struct.new(:vars).new(['sell']).tap { |s| s.define_singleton_method(:current) { s } })
      Object.new.tap { |o| o.define_singleton_method(:waitrt?) { nil } }.instance_eval(gate)
    end

    it 'checks the stow list on a run after eloot is loaded' do
      run_gate('2.14.2')

      expect(calls).to eq([:refresh_stale_inventory])
    end

    it 'loads everything on the first run' do
      run_gate(nil)

      expect(calls).to eq(%i[load set_inventory disk_usage])
    end
  end

  describe 'ELoot.set_inventory list checks' do
    # Only the two lines that decide whether to re-read the lists; the rest of
    # set_inventory drives the game.
    let(:check_lines) do
      body = extract_lic_method(source, 'set_inventory', source_path: eloot_path)
      body.lines.grep(/(ReadyList|StowList)\.check\(/).join
    end

    def run_checks(stow, ready)
      stub_const('StowList', stow)
      stub_const('ReadyList', ready)
      Object.new.instance_eval(check_lines)
    end

    it 'checks a list again when something it holds is gone' do
      stow = list_class.new(checked: true, valid: false)
      ready = list_class.new(checked: true, valid: true)

      run_checks(stow, ready)

      expect(stow.checks).to eq(1)
      expect(ready.checks).to eq(0)
    end

    it 'checks a list that was never checked' do
      ready = list_class.new(checked: false, valid: true)

      run_checks(list_class.new(checked: true, valid: true), ready)

      expect(ready.checks).to eq(1)
    end
  end
end
