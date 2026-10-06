# frozen_string_literal: true

require_relative '../spec_helper'

# Specs for resource.lic's `;resource max` FIXSKILLS planner. The Resource class
# body is extracted from the script and evaluated inside ResourceHarness so its
# lexical lookups of Stats / Lich::Util resolve to the stubs below.
module ResourceHarness
  module Stats
    class << self
      attr_accessor :prof
    end
  end

  module Char
    def self.name
      "Ilten"
    end
  end

  # Replays a captured command, checking the caller's start/end patterns
  # really bound the capture the way Lich::Util.issue_command would.
  module Lich
    module Util
      class << self
        attr_accessor :responses

        def quiet_command_xml(command, start_pattern, end_pattern = /<prompt/, *_rest)
          lines = responses.fetch(command)
          raise "#{command}: start #{start_pattern.inspect} misses #{lines.first.inspect}" unless lines.first =~ start_pattern
          raise "#{command}: end #{end_pattern.inspect} misses #{lines.last.inspect}" unless lines.last =~ end_pattern
          lines
        end
      end
    end
  end

  FIXTURES = File.join(__dir__, 'fixtures', 'resource')

  # Real XML captures: a level 100 Dark Elf Wizard, plus GLD from a Rogue guild master.
  def self.fixture_responses
    {
      "info start"  => File.readlines(File.join(FIXTURES, 'info_start.xml'), chomp: true),
      "exp"         => File.readlines(File.join(FIXTURES, 'exp.xml'), chomp: true),
      "info"        => File.readlines(File.join(FIXTURES, 'info.xml'), chomp: true),
      "skills full" => File.readlines(File.join(FIXTURES, 'skills_full.xml'), chomp: true),
      "gld"         => File.readlines(File.join(FIXTURES, 'gld.xml'), chomp: true)
    }
  end

  lic_path = find_lic_source('resource.lic', from: __dir__)
  source = File.read(lic_path).gsub("\r\n", "\n")
  class_body = extract_from_source(source, /^class Resource\n.*?^end\n/m, label: 'class Resource', source_path: lic_path)
  assert_parses!(class_body, label: 'class Resource', source_path: lic_path)
  module_eval(class_body, lic_path)

  Resource.singleton_class.class_eval do
    attr_accessor :output, :outdoors

    def respond(message = "")
      (self.output ||= []) << message.to_s
    end

    def outside?
      outdoors
    end
  end
end

RSpec.describe 'resource.lic FIXSKILLS planner' do
  let(:resource) { ResourceHarness::Resource }
  let(:points) { ResourceHarness::Resource::TrainingPoints }
  let(:stats) { { str: 20, con: 20, dex: 20, agi: 20, dis: 20, aur: 20, log: 20, int: 20, wis: 20, inf: 20 } }

  describe '.skill_bonus' do
    it 'follows the 5/4/3/2/1 per-rank breakpoints' do
      expect([0, 10, 20, 30, 40, 45].map { |ranks| resource.skill_bonus(ranks) }).to eq([0, 50, 90, 120, 140, 145])
    end
  end

  describe '.rank_cost' do
    it 'doubles each further rank in a level and stops at the per-level cap' do
      costs = (1..4).map { |rank| resource.rank_cost("Wizard", "Wizard", rank, 1)&.to_a }
      expect(costs).to eq([[0, 8], [0, 16], [0, 32], nil])
    end
  end

  describe '.affordable? and .max_mtp_spend' do
    let(:budget) { points.new(10, 10) }

    it 'allows converting either pool 2:1 into the other' do
      expect(resource.affordable?(budget, points.new(0, 15))).to be true
      expect(resource.affordable?(budget, points.new(0, 16))).to be false
      expect(resource.affordable?(budget, points.new(15, 0))).to be true
      expect(resource.affordable?(budget, points.new(16, 0))).to be false
      expect(resource.affordable?(budget, points.new(12, 9))).to be false
    end

    it 'reports the most MTP left to spend after a PTP spend' do
      expect([0, 4, 10, 12, 15].map { |ptp| resource.max_mtp_spend(budget, ptp) }).to eq([15, 13, 10, 6, 0])
      expect(resource.max_mtp_spend(budget, 16)).to be < 0
    end
  end

  describe '.conversion_summary' do
    let(:budget) { points.new(100, 50) }

    it 'reports PTP converted to cover an MTP overspend' do
      summary = resource.conversion_summary(budget, points.new(20, 70))
      expect(summary.slice(:from, :to, :converted)).to eq(from: "PTP", to: "MTP", converted: 40)
      expect(summary[:unspent].to_a).to eq([40, 0])
    end

    it 'reports MTP converted to cover a PTP overspend' do
      summary = resource.conversion_summary(budget, points.new(110, 10))
      expect(summary.slice(:from, :to, :converted)).to eq(from: "MTP", to: "PTP", converted: 20)
      expect(summary[:unspent].to_a).to eq([0, 20])
    end

    it 'reports no conversion when both pools cover the spend' do
      summary = resource.conversion_summary(budget, points.new(30, 20))
      expect(summary[:from]).to be_nil
      expect(summary[:unspent].to_a).to eq([70, 30])
    end
  end

  describe '.replay_training_points' do
    let(:fifties) { resource::STAT_KEYS.to_h { |stat| [stat, 50] } }

    it 'weights prime stats double and splits AUR/DIS across both pools' do
      # Wizard primes are AUR and LOG: physical 200 + (100 + 50) / 2 = 275, mental 250 + 75 = 325.
      expect(resource.replay_training_points("Wizard", "Human", 0, fifties).to_a).to eq([25 + 275 / 20, 25 + 325 / 20])
    end

    it 'adds a cycle of points per level' do
      level_zero = resource.replay_training_points("Cleric", "Elf", 0, fifties)
      level_ten = resource.replay_training_points("Cleric", "Elf", 10, fifties)
      expect(level_ten.ptp).to be >= level_zero.ptp * 11
      expect(level_ten.mtp).to be >= level_zero.mtp * 11
    end

    it 'does not mutate the starting stats' do
      expect { resource.replay_training_points("Wizard", "Human", 100, fifties) }.not_to(change { fifties.dup })
    end

    it 'returns nil for an unknown race or missing stat' do
      expect(resource.replay_training_points("Wizard", "Merfolk", 10, fifties)).to be_nil
      expect(resource.replay_training_points("Wizard", "Human", 10, fifties.except(:wis))).to be_nil
    end
  end

  describe '.service_totals' do
    it 'keeps Monk tattoos separate and every other service as one total' do
      ranks = Hash.new(0).merge("Mental Lore - Transformation" => 10, "Mental Lore - Telepathy" => 5)
      monk = resource.service_totals("Monk", level: 10, stats: stats, ranks: ranks)
      expect(monk.keys).to eq(["Self Tattoo", "Other Tattoo"])
      expect(monk["Self Tattoo"] - monk["Other Tattoo"]).to eq(25)
      expect(resource.service_totals("Wizard", level: 10, stats: stats, ranks: Hash.new(0), location_bonus: 50)).to eq("Enchanting" => 10 + 20 + 20 + 25 + 50)
    end
  end

  describe '.service_option_sets' do
    let(:base_ranks) { Hash.new(0).merge("Harness Power" => 6) }

    it 'values paired mana controls together: larger / 2 plus smaller / 4' do
      sets = resource.service_option_sets("Sorcerer", { level: 5, stats: stats, location_bonus: 20 }, base_ranks)
      paired = sets.find { |options| options.any? { |option| option.ranks.keys.sort == ["Elemental Mana Control", "Spirit Mana Control"] } }
      expect(paired).not_to be_nil
      expect(paired.map(&:value)).to eq(paired.map { |option| larger, smaller = option.ranks.values.minmax.reverse; larger / 2 + smaller / 4 })
      expect(paired.any? { |option| option.ranks.values.min.positive? }).to be true
    end

    it 'splits Monk lore ranks evenly with the odd rank on Transformation' do
      sets = resource.service_option_sets("Monk", { level: 5, stats: stats }, base_ranks)
      lores = sets.find { |options| options.any? { |option| option.ranks.key?("Mental Lore - Telepathy") } }
      lores.each { |option|
        transformation, telepathy = option.ranks.values_at("Mental Lore - Transformation", "Mental Lore - Telepathy")
        expect(transformation - telepathy).to be_between(0, 1)
      }
    end
  end

  describe '.optimize_service' do
    let(:plan_data) { { stats: stats, location_bonus: 20, guild_ranks: 7, weapons: ["Edged Weapons", "Two-Handed Weapons", "Brawling"] } }

    # Exhaustive search over every rank combination of `skills` that fits, pruned only by cost.
    def brute_force_objective(profession, level, budget, reserve_cost, target: nil, skills: resource::SERVICE_SKILLS[profession])
      cycles = level + 1
      base_ranks = Hash.new(0).merge("Harness Power" => 6)
      units = []
      shared_groups = profession == "Monk" ? [resource::MONK_LORES, resource::MONK_MINOR_CIRCLES] : []
      shared_groups.each { |first, second|
        costs = resource.cumulative_costs(profession, first, cycles)
        units << (0...costs.length).flat_map { |a| (0...(costs.length - a)).map { |b| [{ first => a, second => b }, costs[a + b]] } }
      }
      (skills - shared_groups.flatten).each { |skill|
        start = base_ranks[skill]
        units << resource.cumulative_costs(profession, skill, cycles, start).each_with_index.map { |cost, added| [{ skill => start + added }, cost] }
      }
      data = plan_data.merge(level: level)
      best = nil
      search = lambda { |index, ranks, spent|
        if index == units.length
          objective = objective_of(resource.service_totals(profession, data.merge(ranks: ranks)), target)
          best = objective if best.nil? || (objective <=> best) == 1
          return
        end
        units[index].each { |unit_ranks, cost|
          total = spent + cost
          next unless resource.affordable?(budget, total)
          search.call(index + 1, ranks.merge(unit_ranks), total)
        }
      }
      search.call(0, base_ranks, reserve_cost)
      best
    end

    # The planner's ranking: the target title alone when given; otherwise weaker tattoo, then
    # combined tattoos, then Self Tattoo.
    def objective_of(totals, target = nil)
      return [totals.fetch(target)] if target
      return [totals.values.first] if totals.size == 1
      [totals.values.min, totals.values.sum, totals["Self Tattoo"]]
    end

    def expect_exact_plan(profession, ptp, mtp, target: nil, skills: resource::SERVICE_SKILLS[profession])
      level = 5
      budget = points.new(ptp, mtp)
      reserve_cost = resource.cumulative_costs(profession, "Harness Power", level + 1)[6]
      plan = resource.optimize_service(profession, plan_data.merge(level: level), budget, { "Harness Power" => 6 }, reserve_cost, target)
      expect(resource.affordable?(budget, plan.spent)).to be true
      expect(objective_of(plan.score, target)).to eq(brute_force_objective(profession, level, budget, reserve_cost, target: target, skills: skills))
    end

    {
      "Wizard"   => [[5, 40], [60, 10], [0, 120]],
      "Sorcerer" => [[5, 60], [80, 30]],
      "Cleric"   => [[5, 40], [60, 10]],
      "Empath"   => [[10, 40], [25, 50], [80, 5]],
      "Bard"     => [[5, 60], [90, 20]],
      "Paladin"  => [[5, 60], [90, 20]],
      "Monk"     => [[10, 70], [40, 60], [90, 30], [12, 44]],
      "Ranger"   => [[10, 50], [40, 60], [90, 20], [8, 46], [8, 70]]
    }.each { |profession, budgets|
      budgets.each { |ptp, mtp|
        it "finds the exact best #{profession} plan for #{ptp} PTP / #{mtp} MTP" do
          expect_exact_plan(profession, ptp, mtp)
        end
      }
    }

    # Only the skills in a title's formula can change it, so the brute force searches just those.
    # Budgets include the 6 reserved Harness Power ranks (60 MTP for Warriors, 54 for Rogues).
    {
      ["Warrior", "Weapon"]       => [["Physical Fitness", "Edged Weapons", "Two-Handed Weapons", "Brawling"], [[30, 70], [10, 100]]],
      ["Warrior", "Armor"]        => [["Physical Fitness", "Armor Use", "Shield Use"], [[40, 70], [10, 110], [300, 300]]],
      ["Rogue", "Sidestep"]       => [["Ambush", "Pickpocketing", "Dodging"], [[20, 64], [5, 84], [28, 62], [200, 300]]],
      ["Rogue", "Keen Eye"]       => [["Ambush", "Pickpocketing", "Perception"], [[20, 64], [5, 84]]],
      ["Rogue", "Escape Artist"]  => [["Ambush", "Pickpocketing", "Combat Maneuvers"], [[20, 64], [5, 94], [20, 58]]],
      ["Rogue", "Swift Recovery"] => [["Ambush", "Pickpocketing", "Physical Fitness"], [[20, 64], [5, 84]]],
      ["Rogue", "Poisoncraft"]    => [["Ambush", "Pickpocketing", "Survival"], [[20, 64], [5, 84], [24, 62]]],
      ["Rogue", "Recharge"]       => [["Ambush", "Pickpocketing", "Dodging", "Perception", "Combat Maneuvers", "Physical Fitness", "Survival"], [[12, 62], [4, 74], [20, 62], [28, 66]]]
    }.each { |(profession, target), (skills, budgets)|
      budgets.each { |ptp, mtp|
        it "finds the exact best #{profession} #{target} plan for #{ptp} PTP / #{mtp} MTP" do
          expect_exact_plan(profession, ptp, mtp, target: target, skills: skills)
        end
      }
    }

    it 'returns nil when the reserved ranks do not fit' do
      reserve_cost = points.new(0, 100)
      expect(resource.optimize_service("Wizard", { level: 5, stats: stats }, points.new(0, 50), { "Harness Power" => 6 }, reserve_cost)).to be_nil
    end

    it 'converts surplus PTP into service training' do
      reserve_cost = resource.cumulative_costs("Wizard", "Harness Power", 101)[6]
      plan = resource.optimize_service("Wizard", { level: 100, stats: stats, location_bonus: 50 }, points.new(4000, 1000), { "Harness Power" => 6 }, reserve_cost)
      expect(plan.spent.mtp).to be > 1000
    end
  end

  describe '.parse_snapshot' do
    let(:responses) { ResourceHarness.fixture_responses }
    let(:snapshot) { resource.parse_snapshot(*responses.values_at("exp", "info", "info start", "skills full")) }

    it 'reads race, level, and level-0 stats' do
      expect(snapshot.values_at(:race, :level)).to eq(["Dark Elf", 100])
      expect(snapshot[:starting_stats]).to eq(str: 88, con: 85, dex: 49, agi: 73, dis: 77, aur: 49, log: 62, int: 62, wis: 70, inf: 45)
    end

    it 'reads the Enhanced stat bonuses, the same column ;resource bonus uses' do
      expect(snapshot[:stats]).to eq(str: 45, con: 40, dex: 55, agi: 50, dis: 35, aur: 55, log: 45, int: 50, wis: 49, inf: 31)
    end

    it 'takes Enhanced over Ascended when they differ' do
      lines = ["    Strength (STR):   100 (25)    ...  110 (30)"]
      expect(resource.parse_snapshot([], lines, [], [])[:stats][:str]).to eq(30)
    end

    it 'reads experience without Ascension' do
      expect(snapshot[:normal_experience]).to eq(90_017_202)
    end

    it 'reads ranks, not bonus, for skills and ranks for spell circles' do
      expect(snapshot[:ranks].slice("Magic Item Use", "Elemental Mana Control", "Spiritual Lore - Blessings", "Wizard"))
        .to eq("Magic Item Use" => 252, "Elemental Mana Control" => 353, "Spiritual Lore - Blessings" => 151, "Wizard" => 101)
    end

    it 'parses the plain-text form of the same output identically' do
      plain = responses.transform_values { |lines| lines.map { |line| resource.clean_xml(line) } }
      expect(resource.parse_snapshot(*plain.values_at("exp", "info", "info start", "skills full"))).to eq(snapshot)
    end

    it 'falls back to total minus Ascension experience' do
      fallback = resource.parse_snapshot(responses["exp"].reject { |line| line.include?(" Experience:") }, [], [], [])
      expect(fallback[:normal_experience]).to eq(1_738_617_202 - 1_648_600_000)
    end
  end

  describe '.maximum' do
    before do
      resource.output = []
      ResourceHarness::Lich::Util.responses = ResourceHarness.fixture_responses
      allow(resource).to receive(:save_bonuses)
    end

    def current_bonus(output, title)
      output[/Current service bonus:\n(?:  .*\n)*?  #{title}: (\d+)/, 1].to_i
    end

    it 'refuses a profession it has no model for without querying the game' do
      ResourceHarness::Stats.prof = ""
      ResourceHarness::Lich::Util.responses = {}
      resource.maximum
      expect(resource.output.join("\n")).to include("not yet supported for this profession")
    end

    it 'prints a plan from real game output' do
      ResourceHarness::Stats.prof = "Wizard"
      resource.maximum
      output = resource.output.join("\n")
      expect(output).to include("Current service bonus:\n  Enchanting: 698")
      expect(output).to include("Post-cap PTP/MTP earned: 32977 / 32977")
      expect(output).to match(/FIXSKILLS maximum:\n  Enchanting: \d+/)
      expect(output).to include("FIXSKILLS maximum formula:")
    end

    it 'reports the same current bonus as ;resource bonus' do
      ResourceHarness::Stats.prof = "Wizard"
      resource.maximum
      expect(resource.bonus(false)).to eq(current_bonus(resource.output.join("\n"), "Enchanting"))
    end

    it 'prints a Weapon and an Armor plan for Warriors, matching ;resource bonus' do
      ResourceHarness::Stats.prof = "Warrior"
      resource.maximum
      output = resource.output.join("\n")
      expect(output.scan(/^== (.+) plan ==$/).flatten).to eq(["Weapon", "Armor"])
      armor, weapon = resource.bonus(false)
      expect([current_bonus(output, "Weapon"), current_bonus(output, "Armor")]).to eq([weapon, armor])
    end

    it 'prints one plan per Covert Art for Rogues, matching ;resource bonus' do
      ResourceHarness::Stats.prof = "Rogue"
      resource.maximum
      output = resource.output.join("\n")
      arts = ["Sidestep", "Keen Eye", "Escape Artist", "Swift Recovery", "Poisoncraft", "Recharge"]
      expect(output.scan(/^== (.+) plan ==$/).flatten).to eq(arts)
      expect(output).to include("Guild ranks: 124")
      expect(arts.map { |art| current_bonus(output, art) }).to eq(resource.bonus(false))
    end
  end
end
