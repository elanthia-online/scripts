# frozen_string_literal: true

require 'openssl'
require 'rexml/document'
require 'socket'
require 'timeout'
require 'ostruct'
require 'set'
require_relative '../../../spec_helper'

# Shared harness for the lnet.lic specs.
#
# lnet.lic connects to the LNet server as soon as it runs, so it can't be
# required. Its LNet class (everything the script defines lives inside it) is
# extracted verbatim and evaluated inside LnetSpec::Harness, where bare
# references such as Script resolve to the stubs below instead of Lich's.
# Nothing is copied or re-implemented: every example drives the real code.
#
# Output the script would show the user or send to other scripts is recorded
# in LnetSpec::OUTPUT as [kind, *args] pairs; use LnetSpec.capture to read
# what one block produced.
module LnetSpec
  SOURCE_PATH = find_lic_source('lnet.lic', from: File.expand_path('../..', __dir__))
  SOURCE = File.read(SOURCE_PATH)

  OUTPUT = []

  # @return [Array<Array>] everything recorded while the block ran
  def self.capture
    OUTPUT.clear
    yield
    OUTPUT.dup
  end

  # Game state the stubs below read. Reset before every example; set only
  # what an example needs.
  module Game
    class << self
      attr_accessor :infomon, :status, :bounty, :active_spells, :pcs, :npcs, :loot, :room, :scripts, :running, :started,
                    :spell_book, :map_rooms, :running_scripts, :removed_hooks

      def reset!
        @infomon = {}
        @status = []
        @bounty = nil
        @active_spells = []
        @pcs = []
        @npcs = []
        @loot = []
        @room = nil
        @scripts = []
        @running = []
        @started = []
        @spell_book = {}
        @map_rooms = []
        @running_scripts = []
        @removed_hooks = []
      end
    end
  end

  Obj = Struct.new(:name, :status)
  ActiveSpell = Struct.new(:num, :timeleft)
  MapRoom = Struct.new(:id, :title, :desc, :paths)
  RunningScript = Struct.new(:name, :unique_buffer)
  SpellInfo = Struct.new(:circlename, :name)

  # lich-5's real Numeric#as_time (and nothing else from that file), which
  # the spells display calls.
  AS_TIME = read_lich5_source('lib/common/class_exts/numeric.rb').to_s[/^  def as_time\n.*?^  end\n/m]
  Numeric.class_eval(AS_TIME) if AS_TIME && !0.respond_to?(:as_time)

  # Lich's bare status checks, and what in LnetSpec::Game.status makes each true.
  STATUS_CHECKS = {
    hidden?: :hidden, invisible?: :invisible, dead?: :dead, webbed?: :webbed, stunned?: :stunned,
    kneeling?: :kneeling, sitting?: :sitting
  }.freeze

  # Defines the Lich calls the script makes without a receiver (output,
  # status checks, checkbounty) on mod and every class or module nested in
  # it, so whichever one the script calls is recorded or answered from Game.
  def self.install_globals!(mod, seen = Set.new)
    return unless seen.add?(mod)

    [mod, mod.singleton_class].each do |target|
      target.class_eval do
        define_method(:echo) { |*args| OUTPUT << [:echo, *args] }
        define_method(:respond) { |*args| OUTPUT << [:respond, *args] }
        define_method(:_respond) { |*args| OUTPUT << [:_respond, *args] }
        STATUS_CHECKS.each { |check, flag| define_method(check) { Game.status.include?(flag) } }
        define_method(:standing?) { !Game.status.intersect?(%i[kneeling sitting lying]) }
        define_method(:checkbounty) { Game.bounty }
      end
    end
    mod.constants(false).each do |name|
      value = mod.const_get(name, false)
      install_globals!(value, seen) if value.is_a?(Module) && value.name&.start_with?(mod.name)
    end
  end

  # lich-5's real GemStone Skills, Spells and Stats, backed by a fake
  # Infomon, so the responders are checked against the method names Lich
  # actually has. Empty when no lich-5 checkout is available.
  GEMSTONE = Module.new
  ATTRIBUTE_SOURCES = %w[skills spells stats].to_h { |name| [name, read_lich5_source("lib/attributes/#{name}.rb")] }

  # @return [Boolean] whether lich-5's attribute modules could be loaded
  def self.lich5_attributes? = ATTRIBUTE_SOURCES.values.all?

  module Harness
    module Script
      def self.new_downstream(line) = OUTPUT << [:downstream, line]
      def self.new_downstream_xml(line) = OUTPUT << [:downstream_xml, line]
      def self.exists?(name) = Game.scripts.include?(name)
      def self.running?(name) = Game.running.include?(name)
      def self.start(name, *args) = Game.started << [name, *args]
      def self.running = Game.running_scripts
      def self.hidden = []
    end

    module UpstreamHook
      def self.remove(name) = Game.removed_hooks << name
    end

    # Game state the script reads; set what an example needs.
    module XMLData
      class << self
        attr_accessor :name, :game, :level, :exp, :mana, :room_title, :room_description, :room_exits_string,
                      :injuries, :health, :max_health, :spirit, :max_spirit, :stamina, :max_stamina
      end
    end

    module Char
      def self.name = XMLData.name
    end

    module Spell
      def self.active = Game.active_spells
      def self.[](num) = Game.spell_book[num.to_s]
    end

    module Map
      def self.list = Game.map_rooms
      def self.[](id) = Game.map_rooms.find { |room| room.id == id }
    end

    module GameObj
      def self.pcs = Game.pcs
      def self.npcs = Game.npcs
      def self.loot = Game.loot
    end

    module Room
      def self.current = Game.room
    end

    if LnetSpec.lich5_attributes?
      GEMSTONE.const_set(:XMLData, XMLData)
      GEMSTONE.module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
        module Lich
          module Gemstone
            module Infomon
              def self.get(key) = LnetSpec::Game.infomon[key]
            end
          end
        end
      RUBY
      ATTRIBUTE_SOURCES.each { |name, source| GEMSTONE.module_eval(source, "lich-5/lib/attributes/#{name}.rb") }
      Skills = GEMSTONE::Lich::Gemstone::Skills
      Spells = GEMSTONE::Lich::Gemstone::Spells
      Stats = GEMSTONE::Lich::Gemstone::Stats
    end

    body = extract_from_source(LnetSpec::SOURCE, /^class LNet\n.*?^end\n/m, label: 'class LNet', source_path: LnetSpec::SOURCE_PATH)
    assert_parses!(body, label: 'class LNet', source_path: LnetSpec::SOURCE_PATH)
    module_eval(body, LnetSpec::SOURCE_PATH, LnetSpec::SOURCE[0...LnetSpec::SOURCE.index(body)].count("\n") + 1)
  end
  install_globals!(Harness::LNet)

  # Evaluates the LNet class again, as running lnet a second time in one
  # Lich session does: class variables survive, constants are defined anew.
  def self.reload!
    body = extract_from_source(SOURCE, /^class LNet\n.*?^end\n/m, label: 'class LNet', source_path: SOURCE_PATH)
    Harness.module_eval(body, SOURCE_PATH, SOURCE[0...SOURCE.index(body)].count("\n") + 1)
    respond_to?(:install_globals!) ? install_globals!(Harness::LNet) : record_output!(Harness::LNet)
  end

  # Records what the script writes straight to the game client.
  class FakeClient
    def puts(line) = OUTPUT << [:client, line]
  end

  # Records what the script writes; can be told to fail, or to write slowly
  # one character at a time so unsynchronised writers would interleave.
  class FakeServer
    attr_reader :lines, :written

    def initialize(fail_with: nil, slow: false, incoming: [])
      @fail_with = fail_with
      @slow = slow
      @incoming = incoming.dup
      @lines = []
      @written = +''
      @closed = false
    end

    def puts(text)
      raise @fail_with if @fail_with

      if @slow
        "#{text}\n".each_char do |char|
          @written << char
          Thread.pass
        end
      else
        @lines << text
      end
    end

    def readpartial(_max)
      raise IOError, 'closed stream' if @closed
      raise EOFError if @incoming.empty?

      item = @incoming.shift
      item.is_a?(Exception) ? raise(item) : item
    end

    def closed? = @closed
    def close = @closed = true
  end


  # A stream listener that records the events it is given.
  class EventLog
    attr_reader :events

    def initialize = @events = []
    def tag_start(name, attributes) = @events << [:start, name, attributes]
    def text(text) = @events << [:text, text]
    def tag_end(name) = @events << [:end, name]

    # @return [Array<String>] the names of the top-level elements delivered
    def roots
      depth = 0
      @events.each_with_object([]) do |(kind, name), names|
        names << name if kind == :start && depth.zero?
        depth += { start: 1, end: -1 }.fetch(kind, 0)
      end
    end
  end

  # Stand-in for any class with a load hook that happens to be loaded in the
  # Lich process.
  class Gadget
    @loaded = 0
    class << self
      attr_accessor :loaded
    end

    def marshal_dump = 'payload'
    def marshal_load(_) = (Gadget.loaded += 1)
  end

  # non-ASCII test data is built at runtime (Custom/AsciiOnlySource)
  E_ACUTE = [0xe9].pack('U').freeze

  def self.bytes(*list) = list.pack('C*')

  Pair = Struct.new(:a)
  module Mixin; end

  # every shape lnet.lic itself sends, plus what the server sends back
  REAL_PAYLOADS = {
    'info'         => { 'Race' => 'Elf', 'Profession' => 'Wizard', 'Age' => 33, 'Expr' => '1234567', 'Level' => 100,
                'Strength' => [80, 15], 'Discipline' => [nil, nil], 'Mana' => 412 },
    'spells'       => { '101' => 12.508333333333333, '401' => 250.0, '1035' => 0.5 },
    'skills'       => { 'Two Weapon Combat' => 201, 'Minor Elemental' => 102 },
    'locate'       => { 'title' => '[Wehnimer\'s Landing, Town Square]', 'description' => "This is the #{E_ACUTE} square.",
                  'exits' => 'Obvious paths: north, south', 'loot' => ['a sword'],
                  'pcs' => [{ 'name' => 'Bob', 'status' => nil }, { 'name' => 'Ann', 'status' => 'lying down' }],
                  'npcs' => [] },
    'health'       => { 'injuries' => { 'head' => { 'scar' => 0, 'wound' => 1 } }, 'health' => 100, 'max_health' => 120 },
    'bounty'       => 'You are not currently assigned a task.',
    'connected'    => ['GSIV:Bob', 'GSIV:Ann^', 'DR:Cid*', 'loner'],
    'channels'     => [{ 'name' => 'General', 'tuned' => 1234, 'status' => 'default', 'description' => 'chat' }],
    'server stats' => { 'uptime' => 864_000, 'character connections' => [[86_400, 1500]],
                        'own_channels' => { 'Mine' => { 'moderators' => [], 'invited' => nil,
                                                        'banned' => [['Eve', nil], ['Mal', 3600]], 'gagged' => [] } },
                        'mod_channels' => {} },
    'spell-ranks'  => { '_format_' => %w[minorspiritual majorspiritual], '_timestamp_' => 1_647_565_036,
                       'GSIV:Bob' => [25, 3] },
    'declined'     => nil,
    'no such user' => false
  }.freeze

  SAFE_CLASSES = [NilClass, TrueClass, FalseClass, Integer, Float, String, Symbol, Array, Hash].freeze

  # @return [Boolean] whether obj is a tree of plain values only
  def self.plain?(obj, depth = 0)
    return false if depth > 64
    return false unless SAFE_CLASSES.include?(obj.class)

    case obj
    when Array then obj.all? { |o| plain?(o, depth + 1) }
    when Hash then plain?(obj.default, depth + 1) && obj.all? { |k, v| plain?(k, depth + 1) && plain?(v, depth + 1) }
    when String, Symbol then obj.instance_variables.empty?
    else true
    end
  end

  # Helpers mixed into every lnet example group.
  module Helpers
    def lnet = LnetSpec::Harness::LNet

    # Runs xml through the real StreamParser into a real LNet listener, the
    # way the script's socket loop does, and returns what it produced.
    def feed(*chunks)
      LnetSpec.capture do
        parser = lnet::StreamParser.new(lnet::Listener.new)
        chunks.each { |chunk| parser.feed(chunk) }
      end
    end

    # @return [String] a <data> element carrying obj the way LNet sends it
    def data_element(obj, from: 'Bob', type: 'info')
      %(<data type="#{type}" from="#{from}">#{[Marshal.dump(obj)].pack('m').strip}</data>)
    end
  end
end

module LnetSpec
  # Puts the script's class-level state back to how a fresh run starts, so no
  # example sees a connection, password or option another one left behind.
  def self.reset!
    lnet = Harness::LNet
    { server: nil, server_restart: false, last_send: Time.now, last_recv: Time.now, last_priv: nil,
      secret: [], waiting: [], alias: {}, callbacks: {}, last_safe_send: nil, options: { 'ignore' => [], 'friends' => [], 'enemies' => [], 'permission' => {} } }
      .each { |name, value| lnet.class_variable_set(:"@@#{name}", value) }
    Game.reset!
    Harness::XMLData.name = 'Tester'
    Harness::XMLData.game = 'GSIV'
    $clean_lich_char = ';'
    $lich_char = ';'
    OUTPUT.clear
  end
end

RSpec.configure do |config|
  config.include LnetSpec::Helpers, file_path: %r{spec/scripts/lnet/}
  config.before(file_path: %r{spec/scripts/lnet/}) { LnetSpec.reset! }
  # reset! sets these Lich globals; put them back for every other spec
  config.around(file_path: %r{spec/scripts/lnet/}) do |example|
    saved = [$clean_lich_char, $lich_char, $frontend]
    $frontend = nil
    example.run
  ensure
    $clean_lich_char, $lich_char, $frontend = saved
  end
end
