# frozen_string_literal: true

require 'tmpdir'
require_relative '../spec_helper'

# Spec for briefcombat.lic 2.x. The script hooks the live game stream when it
# runs, so only its BriefCombat module is evaluated here, into a spec-local
# namespace that stubs the few Lich globals it touches. Combat recognition
# uses the REAL lich-5 GemStone combat definitions from the local or
# CI-pinned checkout (5.25.0, the minimum the script requires) (see lich5_path in spec_helper.rb), since "does Lich
# recognize this line" is the point; without a checkout the examples skip.
#
# Line shapes are copied from real GS4 XML logs, with player names replaced.
module BriefCombatSpec
  SOURCE_PATH = find_lic_source('briefcombat.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH)
  MODULE_SRC = extract_from_source(SOURCE, /^module BriefCombat\n.*?^end\n/m, label: 'module BriefCombat', source_path: SOURCE_PATH)

  def self.load_lich5_defs
    root = lich5_path
    return false unless root && File.exist?(File.join(root, 'lib/gemstone/combat/parser.rb'))

    lib = File.join(root, 'lib')
    Lich.const_set(:DATA_DIR, Dir.mktmpdir('briefcombat_spec')) unless Lich.const_defined?(:DATA_DIR, false)
    Lich.const_set(:LIB_DIR, lib) unless Lich.const_defined?(:LIB_DIR, false)
    require File.join(lib, 'gemstone/combat/parser')
    require File.join(lib, 'gemstone/critranks')
    true
  end

  module ::Lich; module Gemstone; end; end
  LICH5_DEFS = load_lich5_defs

  # Stubs resolved lexically from inside BriefCombat.
  GameObj = Class.new { def self.[](_id) = nil }
  module_eval(MODULE_SRC, SOURCE_PATH) if LICH5_DEFS

  ADVENTURER = '<a exist="-10000001" noun="Adventurer">Adventurer</a>'
  HEALER = '<a exist="-10000002" noun="Healer">Healer</a>'
  RAVAGER = '<pushBold/>a <a exist="26632189" noun="ravager">corpulent kresh ravager</a><popBold/>'
  THE_RAVAGER = '<pushBold/>The <a exist="26632189" noun="ravager">kresh ravager</a><popBold/>'
  WARDEN = '<pushBold/>a <a exist="203915763" noun="warden">triton warden</a><popBold/>'
  PROMPT = %(<prompt time="1794798195">&gt;</prompt>\r\n)
  ATTACK = %(#{ADVENTURER} swings an adamantine handaxe at #{RAVAGER}!\r\n)
  ROLL = "  AS: +547 vs DS: +296 with AvD: +30 + d100 roll: +23 = +304\r\n"
  HIT = "   ... and hit for 136 points of damage!\r\n"
  CRIT = "   Surgical strike to the left eye removes the top of the head!\r\n"
  ROOM = %(<resource picture="0"/><style id="roomName" />[Zul Logoth, Crystalline Cavern] (13006020)\r\n)
  VITALS = "<dialogData id='minivitals'><progressBar id='stamina' value='63' text='stamina 113/178'/></dialogData>"
  COMPASS = '<compass><dir value="n"/><dir value="s"/></compass>'
end

RSpec.describe 'briefcombat.lic' do
  before { skip 'needs a lich-5 checkout (LICH5_PATH)' unless BriefCombatSpec::LICH5_DEFS }

  let(:bc) { BriefCombatSpec::BriefCombat }
  let(:store) { {} }
  let(:args) { [] }
  let(:dead_ids) { [] }
  let(:settings) { bc::Settings.new(args, args.join(' '), store) }
  let(:engine) { bc::Engine.new(settings, bc::Classifier.new, dead: ->(id) { dead_ids.include?(id) }) }
  let(:client) { bc::Client.new(engine) }

  def feed(*lines) = lines.map { |line| client.call(line.dup) }

  describe 'other players\' combat' do
    it 'becomes one summary at the prompt: damage, crit and roll' do
      outputs = feed(BriefCombatSpec::ATTACK, BriefCombatSpec::ROLL, BriefCombatSpec::HIT, BriefCombatSpec::CRIT)
      expect(outputs).to all(be_nil)
      summary = client.call(BriefCombatSpec::PROMPT.dup)
      expect(summary).to start_with(BriefCombatSpec::ATTACK.chomp)
      expect(summary).to include('AS: +547', '.. 136 damage!  Surgical strike to the left eye')
      expect(summary).to end_with(BriefCombatSpec::PROMPT)
    end

    it 'says KILLED when the game reports the creature dead' do
      dead_ids << 26_632_189
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::HIT)
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('ravager</a><popBold/> is <pushBold/>KILLED<popBold/>!')
    end

    it 'falls back to death text without creature data' do
      death = "#{BriefCombatSpec::THE_RAVAGER} rolls over on the floor and goes still.\r\n"
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::HIT, death)
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('KILLED')
    end

    it 'shows status changes per creature' do
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::HIT, "   #{BriefCombatSpec::THE_RAVAGER} is stunned!\r\n")
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('is stunned!')
    end

    it 'falls back to 1.x status wordings Lich misses' do
      fall = "#{BriefCombatSpec::RAVAGER.sub('a <a', 'A <a')} loses her balance and falls over!\r\n"
      feed(BriefCombatSpec::ATTACK, fall)
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('is knocked down!')
    end

    it 'names the spell from Lich\'s spell definitions' do
      feed(%(#{BriefCombatSpec::ADVENTURER} gestures at #{BriefCombatSpec::RAVAGER}.\r\n),
           "Fiery debris explodes from the ground beneath #{BriefCombatSpec::RAVAGER}!\r\n", "   ... 45 points of damage!\r\n")
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to start_with("#{BriefCombatSpec::ADVENTURER} casts Earthen Fury at")
    end

    it 'uses the caster\'s action line over a bare gesture' do
      bolt = %(#{BriefCombatSpec::ADVENTURER} hurls a seething blast of steam at #{BriefCombatSpec::RAVAGER}!\r\n)
      feed(%(#{BriefCombatSpec::ADVENTURER} gestures at #{BriefCombatSpec::RAVAGER}.\r\n), bolt, BriefCombatSpec::HIT)
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to start_with(bolt.chomp)
    end

    it 'keeps a chant and the cast that follows in the caster\'s round' do
      chant = %(#{BriefCombatSpec::ADVENTURER} chants a reverent litany and clasps his hands while tightly focusing his thoughts...\r\n)
      gesture = %(#{BriefCombatSpec::ADVENTURER} gestures at #{BriefCombatSpec::RAVAGER}.\r\n)
      expect(feed(chant, gesture, "White light flickers around #{BriefCombatSpec::RAVAGER}, but nothing comes of it.\r\n")).to all(be_nil)
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to start_with(chant.chomp)
    end

    it 'counts a groupmate bleeding as its own round' do
      bleed = "#{BriefCombatSpec::HEALER.sub('Healer</a>', "Healer's</a>")} neck drips as he continues to bleed.\r\n"
      expect(feed(bleed, "   ... 4 points of damage!\r\n")).to all(be_nil)
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('.. 4 damage!')
    end

    it 'ends one player\'s round when another starts acting' do
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::HIT)
      second = %(#{BriefCombatSpec::HEALER} swings a mace at #{BriefCombatSpec::RAVAGER}!\r\n)
      expect(client.call(second.dup)).to include('.. 136 damage!')
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to start_with(second.chomp)
    end

    it 'adds up damage with no creature link (MonsterBold off)' do
      feed("#{BriefCombatSpec::ADVENTURER} gestures.\r\n", "Fiery debris explodes from the ground beneath a triton assassin!\r\n",
           "   ... 70 points of damage!\r\n")
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('.. 70 damage!')
    end

    it 'gives one line per round in extreme mode' do
      args.replace(['-x'])
      dead_ids << 26_632_189
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::ROLL, BriefCombatSpec::HIT, BriefCombatSpec::CRIT)
      summary = client.call(BriefCombatSpec::PROMPT.dup)
      expect(summary).to include('... 1 targets <pushBold/>KILLED<popBold/>, 136 damage dealt!')
      expect(summary).not_to include('AS: +547')
    end

    it 'hides rolls with --no-numbers and keeps the rest' do
      args.replace(['--no-numbers'])
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::ROLL, BriefCombatSpec::HIT)
      summary = client.call(BriefCombatSpec::PROMPT.dup)
      expect(summary).not_to include('AS: +547')
      expect(summary).to include('.. 136 damage!')
    end

    it 'leaves excluded players alone' do
      args.replace(['--exclude=Adventurer'])
      expect(client.call(BriefCombatSpec::ATTACK.dup)).to eq(BriefCombatSpec::ATTACK)
    end
  end

  describe 'excluded players' do
    it 'are left alone even when they act during someone else\'s round' do
      args.replace(['--exclude=Healer'])
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::HIT)
      healer = %(#{BriefCombatSpec::HEALER} swings a mace at #{BriefCombatSpec::RAVAGER}!\r\n)
      out = client.call(healer.dup)
      expect(out).to include('.. 136 damage!')
      expect(out).to end_with(healer)
      expect(client.call("   ... 12 points of damage!\r\n")).to eq("   ... 12 points of damage!\r\n")
    end
  end

  describe 'you' do
    let(:yours) { "You swing a perfect mithril war-hammer at #{BriefCombatSpec::RAVAGER}!\r\n" }

    it 'leaves your own combat alone by default' do
      expect(feed(yours, BriefCombatSpec::HIT)).to eq([yours, BriefCombatSpec::HIT])
    end

    it 'shortens your own combat with all' do
      args.replace(['all'])
      expect(feed(yours, BriefCombatSpec::HIT)).to all(be_nil)
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('.. 136 damage!')
    end

    it 'leaves your own spell effects alone by default' do
      debris = "Fiery debris explodes from the ground beneath #{BriefCombatSpec::RAVAGER}!\r\n"
      expect(feed("You gesture.\r\n", debris)).to eq(["You gesture.\r\n", debris])
    end

    it 'leaves later cycles of your own lasting spell alone' do
      debris = "Fiery debris explodes from the ground beneath #{BriefCombatSpec::RAVAGER}!\r\n"
      feed("You gesture at #{BriefCombatSpec::RAVAGER}.\r\n", debris, BriefCombatSpec::PROMPT)
      expect(feed(debris, "   ... 45 points of damage!\r\n")).to eq([debris, "   ... 45 points of damage!\r\n"])
    end

    it 'leaves your own spell alone when its effect names no creature link' do
      debris = "Fiery debris explodes from the ground beneath a triton brawler!\r\n"
      expect(feed("You gesture at #{BriefCombatSpec::RAVAGER}.\r\n", debris)).to eq(["You gesture at #{BriefCombatSpec::RAVAGER}.\r\n", debris])
    end

    it 'never hides an attack aimed at you' do
      jab = "#{BriefCombatSpec::WARDEN.sub('a <a', 'The <a')} attempts to jab you!\r\n"
      expect(client.call(jab.dup)).to eq(jab)
    end

    it 'shows lines about you inside someone else\'s round' do
      feed(BriefCombatSpec::ATTACK)
      expect(client.call("You are stunned for 5 rounds!\r\n")).to eq("You are stunned for 5 rounds!\r\n")
      expect(client.call("You seem to blend into the surroundings better.\r\n")).to eq("You seem to blend into the surroundings better.\r\n")
    end

    it 'shows a change to your state even inside your own round' do
      args.replace(['all'])
      feed("You gesture.\r\n")
      expect(client.call("You are surrounded by a white light.\r\n")).to eq("You are surrounded by a white light.\r\n")
    end
  end

  # Review of 2.0.0 (scripts#2643): an attack on you inside an open round
  # used to show its line but fold its roll and damage into the round,
  # credited to whoever acted.
  describe 'an attack on you during an open round' do
    let(:jab) { "#{BriefCombatSpec::WARDEN.sub('a <a', 'The <a')} attempts to jab you!\r\n" }
    let(:roll) { "  UAF: 414 vs UDF: 1048 = 0.395 * MM: 90 + d100: 11 = 46\r\n" }
    let(:hit18) { "   ... and hit for 18 points of damage!\r\n" }

    it 'ends another player\'s round, and its roll and damage stay yours' do
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::HIT)
      out = client.call(jab.dup)
      expect(out).to include('.. 136 damage!')
      expect(out).not_to include('154')
      expect(out).to end_with(jab)
      expect(feed(roll, hit18)).to eq([roll, hit18])
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to eq(BriefCombatSpec::PROMPT)
    end

    it 'ends your own round with all, and is never folded into it' do
      args.replace(['all'])
      feed("You swing a perfect mithril war-hammer at #{BriefCombatSpec::RAVAGER}!\r\n", BriefCombatSpec::HIT)
      out = client.call(jab.dup)
      expect(out).to include('.. 136 damage!')
      expect(out).not_to include('and 1 other')
      expect(out).to end_with(jab)
      expect(feed(roll, hit18)).to eq([roll, hit18])
    end

    it 'is still summarized with --you' do
      args.replace(['--you'])
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::HIT)
      expect(client.call(jab.dup)).to include('.. 136 damage!')
      expect(feed(roll, hit18)).to all(be_nil)
    end
  end

  describe 'lasting spells with two casters' do
    let(:debris) { ->(creature) { "Fiery debris explodes from the ground beneath #{creature}!\r\n" } }

    it 'keeps your cycles yours when another player casts the same spell on another creature' do
      feed("You gesture at #{BriefCombatSpec::RAVAGER}.\r\n", debris.(BriefCombatSpec::RAVAGER), BriefCombatSpec::PROMPT)
      feed(%(#{BriefCombatSpec::ADVENTURER} gestures at #{BriefCombatSpec::WARDEN}.\r\n), debris.(BriefCombatSpec::WARDEN), BriefCombatSpec::PROMPT)
      # later cycles, nobody named
      expect(client.call(debris.(BriefCombatSpec::RAVAGER))).to eq(debris.(BriefCombatSpec::RAVAGER))
      client.call(BriefCombatSpec::PROMPT.dup)
      expect(client.call(debris.(BriefCombatSpec::WARDEN))).to be_nil
    end
  end

  describe 'inherited 1.x matching' do
    it 'excludes whole player names only' do
      args.replace(['--exclude=Advent'])
      expect(client.call(BriefCombatSpec::ATTACK.dup)).to be_nil
    end

    it 'squelches arrow nocking but not "knocks a"' do
      expect(client.call("<a exist=\"-1\" noun=\"Bob\">Bob</a> nocks an arrow.\r\n")).to be_nil
      line = "<a exist=\"-1\" noun=\"Bob\">Bob</a> knocks a pebble off the ledge.\r\n"
      expect(client.call(line.dup)).to eq(line)
    end

    it 'shows an attack on you during a shortened search, with its roll and damage' do
      args.replace(['-x'])
      feed(%(#{BriefCombatSpec::ADVENTURER} searches #{BriefCombatSpec::WARDEN}.\r\n))
      jab = "#{BriefCombatSpec::WARDEN.sub('a <a', 'The <a')} attempts to jab you!\r\n"
      roll = "  UAF: 414 vs UDF: 1048 = 0.395 * MM: 90 + d100: 11 = 46\r\n"
      hit = "   ... and hit for 18 points of damage!\r\n"
      expect(feed(jab, roll, hit)).to eq([jab, roll, hit])
    end

    it 'shows an attack on you Lich does not recognize during a shortened search' do
      args.replace(['-x'])
      feed(%(#{BriefCombatSpec::ADVENTURER} searches #{BriefCombatSpec::WARDEN}.\r\n))
      myrmidon = '<pushBold/>a <a exist="26006044" noun="myrmidon">chitinous kiramon myrmidon</a><popBold/>'
      its = '<pushBold/><a exist="26006044" noun="myrmidon">its</a><popBold/>'
      slash = "Surging forward powerfully, #{myrmidon} slashes at you with #{its} bladed foreleg!\r\n"
      roll = "  AS: +534 vs DS: +1001 with AvD: +23 + d100 roll: +40 = -404\r\n"
      expect(feed(slash, roll, "   A clean miss.\r\n")).to eq([slash, roll, "   A clean miss.\r\n"])
    end

    it 'shows lines about you while another player\'s search is shortened' do
      args.replace(['-x'])
      feed(%(#{BriefCombatSpec::ADVENTURER} searches #{BriefCombatSpec::WARDEN}.\r\n))
      expect(client.call("A few coins fall out.\r\n")).to be_nil
      expect(client.call("You are stunned for 3 rounds!\r\n")).to eq("You are stunned for 3 rounds!\r\n")
    end
  end

  describe 'creatures attacking players' do
    let(:claw) { "#{BriefCombatSpec::WARDEN} swings a claw at #{BriefCombatSpec::HEALER}!\r\n" }

    it 'are left alone by default' do
      expect(client.call(claw.dup)).to eq(claw)
    end

    it 'are shortened with --creatures, crediting the player, not the creature' do
      args.replace(['--creatures'])
      dead_ids << 203_915_763
      expect(feed(claw, "   ... 12 points of damage!\r\n")).to all(be_nil)
      summary = client.call(BriefCombatSpec::PROMPT.dup)
      expect(summary).to include('.. 12 damage!')
      expect(summary).not_to include('KILLED')
    end
  end

  describe '--you' do
    let(:jab) { "#{BriefCombatSpec::WARDEN.sub('a <a', 'The <a')} attempts to jab you!\r\n" }

    it 'shortens an attack on you, crediting you, not the attacker' do
      args.replace(['--you'])
      dead_ids << 203_915_763
      expect(feed(jab, "   ... 9 points of damage!\r\n", "You are stunned for 3 rounds!\r\n")).to all(be_nil)
      summary = client.call(BriefCombatSpec::PROMPT.dup)
      expect(summary).to start_with(jab.chomp)
      expect(summary).to include('.. 9 damage!', 'You are stunned!')
      expect(summary).not_to include('KILLED')
    end

    it 'shortens creature attacks on you that Lich\'s definitions don\'t know' do
      args.replace(['--you'])
      myrmidon = '<pushBold/>a <a exist="26006044" noun="myrmidon">chitinous kiramon myrmidon</a><popBold/>'
      its = '<pushBold/><a exist="26006044" noun="myrmidon">its</a><popBold/>'
      slash = "Surging forward powerfully, #{myrmidon} slashes at you with #{its} bladed foreleg!\r\n"
      roll = "  AS: +534 vs DS: +1001 with AvD: +23 + d100 roll: +40 = -404\r\n"
      expect(feed(slash, roll, "   A clean miss.\r\n")).to all(be_nil)
      summary = client.call(BriefCombatSpec::PROMPT.dup)
      expect(summary).to start_with(slash.chomp)
      expect(summary).to include('AS: +534', 'A clean miss.')
    end

    it 'sends a line aimed at you as it came when no combat follows' do
      args.replace(['--you'])
      terror = "#{BriefCombatSpec::WARDEN.sub('a <a', 'A <a')} looks at you in utter terror!\r\n"
      expect(client.call(terror.dup)).to be_nil
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to eq("#{terror}#{BriefCombatSpec::PROMPT}")
    end

    it 'folds lines about you into someone else\'s round' do
      args.replace(['--you'])
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::HIT)
      expect(client.call("You are stunned for 5 rounds!\r\n")).to be_nil
      summary = client.call(BriefCombatSpec::PROMPT.dup)
      expect(summary).to include('.. 136 damage!', 'You are stunned!')
      expect(summary).to start_with(BriefCombatSpec::ATTACK.chomp)
      expect(summary).not_to include('and 1 other')
    end

    it 'reports you on your own line in extreme mode' do
      args.replace(['--you', '-x'])
      feed(jab, "   ... 9 points of damage!\r\n", "You are stunned for 3 rounds!\r\n")
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('... you: stunned, 9 damage taken!')
    end

    it 'still shows awards, found silver and your death' do
      args.replace(['--you', 'all'])
      feed(BriefCombatSpec::ATTACK)
      award = "<pushBold/>You have been awarded 1 Long-Term Experience Boost!\r\n"
      expect(client.call(award.dup)).to eq(award)
      silver = "You rifle her pockets and discover 706 silvers!\r\n"
      expect(client.call(silver.dup)).to eq(silver)
    end

    it 'is turned on, with all and --creatures, by everything' do
      args.replace(['everything'])
      expect(settings).to be_compress_you
      expect(settings).to be_compress_self
      expect(settings).to be_creature_attacks
      expect(client.call(jab.dup)).to be_nil
    end
  end

  describe 'settings' do
    it 'loads 1.x settings and saves under the same keys' do
      store['briefcombat'] = { 'extreme_mode' => true, 'compress_self' => true, 'excluded_players' => ['Bob'] }
      expect(settings).to be_extreme
      expect(settings).to be_compress_self
      expect(settings.excluded).to eq(['Bob'])
      expect(store['briefcombat']['show_numbers']).to be(true)
    end

    it 'treats you/self in the exclude list as leaving your combat alone' do
      store['briefcombat'] = { 'compress_self' => true, 'excluded_players' => ['self'] }
      expect(settings).not_to be_compress_self
      expect(settings.excluded).to be_empty
    end
  end

  describe 'searching' do
    it 'shortens another player\'s search in extreme mode' do
      args.replace(['-x'])
      search = %(#{BriefCombatSpec::ADVENTURER} searches #{BriefCombatSpec::WARDEN}.\r\n)
      expect(feed(search, "A few coins fall out.\r\n")).to all(be_nil)
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to eq(BriefCombatSpec::PROMPT)
    end
  end

  describe 'client XML' do
    it 'carries a compass from a hidden Roundtime line onto the next line' do
      expect(client.call("#{BriefCombatSpec::COMPASS}Roundtime: 3 sec.\r\n")).to be_nil
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to eq("#{BriefCombatSpec::COMPASS}#{BriefCombatSpec::PROMPT}")
    end

    it 'keeps only the newest compass' do
      newer = '<compass><dir value="e"/></compass>'
      feed("#{BriefCombatSpec::COMPASS}Roundtime: 3 sec.\r\n", "#{newer}Roundtime: 2 sec.\r\n")
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to eq("#{newer}#{BriefCombatSpec::PROMPT}")
    end

    it 'carries panel XML from a line folded into a summary' do
      expect(client.call("#{BriefCombatSpec::VITALS}#{BriefCombatSpec::ATTACK}")).to be_nil
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to start_with(BriefCombatSpec::VITALS)
    end

    it 'sends a line holding only XML as is, even inside a round' do
      feed(BriefCombatSpec::ATTACK)
      line = "<indicator id='IconSTUNNED' visible='y'/><roundTime value='1794798200'/>\r\n"
      expect(client.call(line.dup)).to eq(line)
    end

    it 'lets a Bounties window update through while a round is open' do
      feed(BriefCombatSpec::ATTACK, BriefCombatSpec::HIT)
      push = "<clearStream id='bounty'/><pushStream id='bounty'/>\r\n"
      task = "You have been tasked to suppress corpulent kresh ravager activity.\r\n"
      expect(feed(push, task, "<popStream id='bounty'/>\r\n")).to eq([push, task, "<popStream id='bounty'/>\r\n"])
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('.. 136 damage!')
    end

    it 'still summarizes combat after a side window the server left open' do
      feed(BriefCombatSpec::ATTACK, "<clearStream id='bounty'/><pushStream id='bounty'/>\r\n", "Task text.\r\n")
      expect(client.call(BriefCombatSpec::HIT.dup)).to be_nil
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to include('.. 136 damage!')
    end

    it 'ends a round at a room change and gives the room title its own chunk' do
      feed(%(#{BriefCombatSpec::ADVENTURER} gestures.\r\n), "Your surroundings blur for a moment . . .\r\n")
      expect(client.call(BriefCombatSpec::ROOM.dup)).to start_with(%(#{BriefCombatSpec::ADVENTURER} gestures.))
      desc = %(<style id=""/><style id="roomDesc"/>The stone avenues give way to humus and dirt.\r\n)
      expect(client.call(desc.dup)).to eq("#{BriefCombatSpec::ROOM}#{desc}")
    end

    it 'never puts carried XML in front of a room title' do
      expect(client.call("#{BriefCombatSpec::VITALS}Roundtime: 3 sec.\r\n")).to be_nil
      expect(client.call(BriefCombatSpec::ROOM.dup)).to eq(BriefCombatSpec::ROOM)
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to eq("#{BriefCombatSpec::VITALS}#{BriefCombatSpec::PROMPT}")
    end

    it 'carries an unbalanced bold tag but not a balanced pair' do
      feed("<pushBold/>Roundtime: 3 sec.\r\n", "Roundtime: 1 sec.<popBold/>\r\n")
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to eq("<pushBold/><popBold/>#{BriefCombatSpec::PROMPT}")
      client.call("#{BriefCombatSpec::WARDEN} Roundtime: 3 sec.\r\n")
      expect(client.call(BriefCombatSpec::PROMPT.dup)).to eq(BriefCombatSpec::PROMPT)
    end

    it 'recognizes combat behind a leading crtrStatus tag' do
      status = '<crtrStatus exist="26632189" health="720" maxhealth="750" hostile="1" stunned="1"/>'
      expect(client.call("#{status}#{BriefCombatSpec::ATTACK}")).to be_nil
    end
  end

  describe 'loading' do
    it 'reloads without already-initialized constant warnings' do
      expect { BriefCombatSpec.module_eval(BriefCombatSpec::MODULE_SRC, BriefCombatSpec::SOURCE_PATH) }
        .not_to output(/already initialized/).to_stderr
    end

    it 'needs Lich 5.25.0 or newer, pre-releases of later versions included' do
      expect(bc.supported?('5.25.0')).to be(true)
      expect(bc.supported?('5.26.0.beta.1')).to be(true)
      expect(bc.supported?('5.24.2')).to be(false)
      expect(bc.supported?('not a version')).to be(false)
    end
  end
end
