# frozen_string_literal: true

# spec/spec_helper.rb - shared scaffolding for this repo's ".lic script"
# specs (spec/scripts, and any future spec that extracts a script's real
# module/method bodies and evaluates them against stubs).
#
# Modeled on lich-5's spec/spec_helper.rb, but much narrower in scope: this
# repo's specs are about individual *scripts*, not the runtime itself, so
# this file only centralizes what genuinely repeats across them --
#   1. path/extraction helpers for pulling real code out of a `.lic` file
#      (every existing spec/scripts/*_spec.rb duplicated some version of
#      this "search a few candidate paths, then regex out a def/module/
#      class body, raising loudly if either step fails" boilerplate), and
#   2. generic Lich runtime stand-ins that are safe to share process-wide
#      (UserVars, Char, Script, Spell, Group, Lich::Util,
#      Lich::Common::Frontend) plus the handful of bare game-command
#      methods (waitrt?, waitcastrt?, fput, put, pause, checkstance) that
#      extracted module_function methods call with an implicit receiver.
#
# What this deliberately does NOT provide: a shared GameObj stub.
# lib/lich/gameobj.rb defines a real, TOP-LEVEL `GameObj` class that
# spec/gameobj-data loads and exercises directly; defining another
# top-level `GameObj` here -- even a stub -- would reopen and corrupt that
# class for every other spec file loaded in the same rspec process (Ruby
# happily merges reopened class bodies, silently overwriting methods like
# `GameObj.npcs`). Existing specs already avoid this by nesting their own
# GameObj stub inside a private Harness namespace instead of defining it at
# top level (see spec/bigshot/priority_spec.rb's comment on the same
# constraint); do the same in yours if you need one.
#
# Usage: `require_relative '../spec_helper'` (adjust the relative depth to
# your file's location under spec/), then reference LichStub::UserVars,
# LichStub::Char, etc. directly, or alias them into your own Harness
# namespace -- the same way spec/scripts/ledger_spec.rb already aliases its
# extracted Window module into Harness::Ledger::Window -- if your extracted
# code needs to find them via lexical constant lookup rather than an
# explicit `LichStub::` prefix.

require 'rspec'

SPEC_ROOT = File.expand_path(__dir__) unless defined?(SPEC_ROOT)
REPO_ROOT = File.expand_path('..', SPEC_ROOT) unless defined?(REPO_ROOT)

# -- .lic extraction helpers -------------------------------------------

# Locates a `.lic` file by name, checking a few likely locations relative to
# the calling spec's own directory. Mirrors the multi-candidate search list
# every existing extraction-style spec in this repo already duplicated.
#
# @param lic_name [String] e.g. "treim.lic"
# @param from [String] the calling spec file's own `__dir__`
# @return [String] absolute path to the found file
# @raise [RuntimeError] if lic_name isn't found anywhere in the search path
def find_lic_source(lic_name, from:)
  path = [
    File.expand_path(lic_name, from),
    File.expand_path("../#{lic_name}", from),
    File.expand_path("../../#{lic_name}", from),
    File.expand_path("../scripts/#{lic_name}", from),
    File.expand_path("../../scripts/#{lic_name}", from)
  ].find { |p| File.exist?(p) }
  raise "#{lic_name} not found (searched relative to #{from})" unless path

  path
end

# Pulls the first substring of source matching pattern, raising loudly
# instead of silently testing against a stale/absent extraction if the
# source no longer contains what the spec expects.
#
# @param source [String] full file contents to search
# @param pattern [Regexp] must be anchored precisely enough to match once
# @param label [String] used only in the raised error message
# @param source_path [String, nil] used only in the raised error message
# @return [String] the matched substring
# @raise [RuntimeError] if pattern does not match anywhere in source
def extract_from_source(source, pattern, label:, source_path: nil)
  found = source[pattern]
  raise "could not extract #{label} from #{source_path || 'source'}" unless found

  found
end

# Extracts one `module Name ... end` / `class Name ... end` body, indented
# two spaces (i.e. nested exactly one level under a script's outer
# namespace module), for module_eval'ing into a spec's own harness.
#
# @param source [String] full `.lic` file contents
# @param name [String] the module/class name, e.g. "Geography"
# @param kind ["module", "class"]
# @param source_path [String, nil] used only in the raised error message
# @return [String] the extracted source, including the module/class wrapper
# @raise [RuntimeError] if no matching, two-space-indented body is found
def extract_lic_module(source, name, kind: 'module', source_path: nil)
  extract_from_source(source, /^  #{kind} #{name}\n.*?\n  end\n/m, label: "#{kind} #{name}", source_path: source_path)
end

# -- Generic Lich runtime stand-ins --------------------------------------
#
# Every constant here is a bare-bones stand-in for a real Lich global,
# reset between examples by the RSpec.configure block below. They're
# namespaced under LichStub rather than defined at top level so a spec can
# choose exactly which ones it needs (aliasing them into its own Harness)
# instead of silently inheriting all of them.

module LichStub
  FakeNpc = Struct.new(:id, :noun, :name, :status)

  # Stand-in for Lich's UserVars: any character variable name works as a
  # getter/setter (`UserVars.treim`, `UserVars.treim = {}`, ...), backed by
  # a plain Hash, the same way the real thing is backed by a settings store.
  module UserVars
    class << self
      def reset!
        @store = {}
      end

      def method_missing(name, *args)
        key = name.to_s.delete_suffix('=').to_sym
        name.to_s.end_with?('=') ? (store[key] = args.first) : store[key]
      end

      def respond_to_missing?(*) = true

      private

      def store
        @store ||= {}
      end
    end
  end

  module Char
    class << self
      attr_accessor :name
    end
  end

  module Script
    class << self
      def reset!
        @started = []
        @running = []
      end

      attr_reader :started

      def start(name, args = nil)
        @started << [name, args]
      end

      def running?(name)
        @running.include?(name)
      end

      def mark_running!(name)
        @running << name
      end

      def kill(name)
        @running.delete(name)
      end

      def pause(_name) = nil
      def unpause(_name) = nil
      def exists?(_name) = true
    end
  end

  class Spell
    class << self
      attr_accessor :affordable

      def [](number)
        new(number)
      end
    end

    def initialize(number)
      @number = number
    end

    def affordable?
      Spell.affordable.nil? || Spell.affordable
    end
  end

  module Lich
    module Util
      class << self
        attr_accessor :issue_command_result

        def issue_command(*)
          issue_command_result || []
        end
      end
    end

    module Common
      module Frontend
        class << self
          attr_accessor :xml_supported

          def supports_xml?
            !!xml_supported
          end
        end
      end
    end
  end

  # Records of/controls for the bare game-command calls extracted
  # module_function methods make with an implicit receiver (see the
  # top-level waitrt?/fput/put/pause/checkstance stubs below).
  module GameStub
    class << self
      attr_accessor :stance, :on_pause

      def calls
        @calls ||= []
      end

      def reset!
        @calls = []
        @stance = 'defensive'
        @on_pause = nil
      end
    end
  end

  def self.reset_all!
    UserVars.reset!
    Script.reset!
    Spell.affordable = nil
    ::Group.leader = nil
    ::Group.members = []
    Lich::Util.issue_command_result = nil
    Lich::Common::Frontend.xml_supported = nil
    GameStub.reset!
  end
end

# Defined at the true top level (not nested, and not inside an RSpec.describe
# block, whose body is class_eval'd into an example-group subclass) so
# implicit-receiver calls from eval'd module_function methods -- whatever
# namespace they were module_eval'd into -- can find them. Ruby resolves an
# implicit-receiver call via the *receiver's* method lookup chain, not
# lexical nesting, and every object's chain bottoms out at Object/Kernel;
# that's also exactly why Lich's own equivalents are defined at the top
# level of lib/global_defs.rb, making them callable unqualified from
# arbitrarily-nested .lic script code in the first place.
def waitrt?
  LichStub::GameStub.calls << [:waitrt?]
  false
end

def waitcastrt?
  LichStub::GameStub.calls << [:waitcastrt?]
  false
end

def fput(command)
  LichStub::GameStub.calls << [:fput, command]
  LichStub::GameStub.stance = 'offensive' if command == 'stance offensive'
  LichStub::GameStub.stance = 'defensive' if command == 'stance defensive'
  command
end

def put(command)
  LichStub::GameStub.calls << [:put, command]
  command
end

def pause(seconds = 1)
  LichStub::GameStub.calls << [:pause, seconds]
  LichStub::GameStub.on_pause&.call
end

def checkstance
  LichStub::GameStub.stance
end

# Also defined at the true top level, but for a different reason than the
# game-command methods above: production script code reaches for the native
# Group API via an explicitly absolute `::Group` (see treim.lic), not a bare
# `Group`, specifically so it always resolves to the real top-level class
# regardless of what namespace the calling code is nested in. That means a
# nested LichStub::Group would never be found here -- only a genuine
# top-level one satisfies `::Group`. Confirmed safe: nothing else in this
# repo's lib/ defines a top-level Group.
module Group
  class << self
    attr_accessor :leader, :members

    def leader?
      leader == :self
    end
  end
end

# -- RSpec configuration --------------------------------------------------

RSpec.configure do |config|
  config.example_status_persistence_file_path = File.join(SPEC_ROOT, '.rspec_status')
  config.default_formatter = 'doc' if config.files_to_run.one?

  # Reset shared LichStub state before each example so specs that use it
  # can't leak configuration or call logs into one another.
  config.before do
    LichStub.reset_all!
  end
end
