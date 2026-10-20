# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# boon.lic's gem stockpile keeps a count per locker jar in CharSettings[:jars].
# These specs run the script's real stockpile and raid_stockpile procs against
# lich-5's real Settings stack and a real lich.db3, in a worker process of their
# own (see stockpile_worker.rb), then check the row as stored, which is what the
# script reads after a restart. They need a lich-5 checkout (LICH5_PATH, or a
# sibling ../lich-5) and skip without one, as the other lich-5-backed specs do.
module BoonStockpileSpec
  LICH5_PATH = lich5_path
  BOON_PATH = File.join(REPO_ROOT, 'scripts', 'boon.lic')
  WORKER_PATH = File.expand_path('stockpile_worker.rb', __dir__)

  def self.run(scenario)
    Dir.mktmpdir('boon-stockpile') do |dir|
      out, err, status = Open3.capture3(
        RbConfig.ruby, WORKER_PATH, LICH5_PATH, BOON_PATH, dir,
        stdin_data: JSON.generate(scenario)
      )
      raise "worker failed (#{status.exitstatus}):\n#{err}\n#{out}" unless status.success?

      JSON.parse(out.lines.last)
    end
  end

  def self.jar(gem, count, full)
    { 'gem' => gem, 'count' => count, 'full' => full }
  end

  BOUNTY = 'The gem dealer in town has received orders from multiple customers ' \
           'requesting an emerald.  You have been tasked to retrieve %d more of them.'
end

RSpec.describe 'boon.lic gem stockpile counts' do
  before { skip 'no lich-5 checkout (set LICH5_PATH)' unless BoonStockpileSpec::LICH5_PATH }

  def run(scenario)
    BoonStockpileSpec.run(scenario)
  end

  def jar(gem, count, full)
    BoonStockpileSpec.jar(gem, count, full)
  end

  describe 'starting a new jar' do
    it 'stores every gem added, not just the first' do
      result = run(
        'locker' => [{ 'capacity' => 10 }],
        'sack'   => ['emerald'] * 4,
        'steps'  => ['stockpile']
      )

      expect(result['jars']).to eq([jar('emeralds', 4, false)])
      expect(result['commands'].grep(/\A_drag /).size).to eq(4)
    end

    it 'stores the jar as full when it fills, and keeps the gems that did not fit' do
      result = run(
        'locker' => [{ 'capacity' => 3 }],
        'sack'   => ['emerald'] * 5,
        'steps'  => ['stockpile']
      )

      expect(result['jars']).to eq([jar('emeralds', 3, true)])
      # the fourth gem is refused and put back; the loop stops there
      expect(result['commands'].grep(/\A_drag /).size).to eq(4)
      expect(result['commands'].grep(/\Aput #\d+ in #800\z/).size).to eq(2) # the jar while naming it, then the refused gem
    end

    it 'stores a jar that only ever gets one gem' do
      result = run(
        'locker' => [{ 'capacity' => 10 }],
        'sack'   => ['emerald'],
        'steps'  => ['stockpile']
      )

      expect(result['jars']).to eq([jar('emeralds', 1, false)])
    end

    it 'keeps each count when two new jars are started on one trip' do
      result = run(
        'locker' => [{ 'capacity' => 10 }, { 'capacity' => 10 }],
        'sack'   => ['emerald'] * 3 + ['sapphire'] * 2,
        'steps'  => ['stockpile']
      )

      expect(result['jars']).to eq([jar('emeralds', 3, false), jar('sapphires', 2, false)])
    end

    it 'counts into the entry it just added, not an older entry for the same gem' do
      # A stored entry with no matching jar in the locker (the list is out of
      # step with the locker), so the script starts a new jar for that gem.
      result = run(
        'jars'            => [jar('emeralds', 7, true)],
        'empty_jar_count' => 1,
        'locker'          => [{ 'capacity' => 10 }],
        'sack'            => ['emerald'] * 3,
        'steps'           => ['stockpile']
      )

      expect(result['jars']).to eq([jar('emeralds', 7, true), jar('emeralds', 3, false)])
    end
  end

  describe 'adding to a jar the script already knows' do
    it 'stores the new count' do
      result = run(
        'locker' => [{ 'capacity' => 10, 'gem' => 'emerald', 'count' => 2 }],
        'sack'   => ['emerald'] * 3,
        'steps'  => ['stockpile']
      )

      expect(result['jars']).to eq([jar('emeralds', 5, false)])
    end
  end

  describe 'raiding the stockpile for a gem bounty' do
    it 'can use the gems stockpiled into a new jar on the same trip' do
      result = run(
        'locker' => [{ 'capacity' => 10 }],
        'sack'   => ['emerald'] * 4,
        'bounty' => format(BoonStockpileSpec::BOUNTY, 3),
        'steps'  => %w[stockpile raid]
      )

      expect(result['raided']).to be(true)
      expect(result['commands'].grep(/\Ashake /).size).to eq(3)
      expect(result['jars']).to eq([jar('emeralds', 1, false)])
    end

    it 'drops the entry once the jar is emptied' do
      result = run(
        'locker' => [{ 'capacity' => 10 }],
        'sack'   => ['emerald'] * 4,
        'bounty' => format(BoonStockpileSpec::BOUNTY, 4),
        'steps'  => %w[stockpile raid]
      )

      expect(result['raided']).to be(true)
      expect(result['jars']).to eq([])
    end

    it 'leaves the stockpile alone when it holds fewer gems than the bounty asks for' do
      result = run(
        'locker' => [{ 'capacity' => 10 }],
        'sack'   => ['emerald'] * 2,
        'bounty' => format(BoonStockpileSpec::BOUNTY, 3),
        'steps'  => %w[stockpile raid]
      )

      expect(result['raided']).to be(false)
      expect(result['commands'].grep(/\Ashake /)).to be_empty
      expect(result['jars']).to eq([jar('emeralds', 2, false)])
    end
  end
end
