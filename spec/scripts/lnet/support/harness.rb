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

  # Defines the Lich output calls on mod and every class or module nested in
  # it, so whichever one the script calls is recorded.
  def self.record_output!(mod, seen = Set.new)
    return unless seen.add?(mod)

    [mod, mod.singleton_class].each do |target|
      target.class_eval do
        define_method(:echo) { |*args| OUTPUT << [:echo, *args] }
        define_method(:respond) { |*args| OUTPUT << [:respond, *args] }
        define_method(:_respond) { |*args| OUTPUT << [:_respond, *args] }
      end
    end
    mod.constants(false).each do |name|
      value = mod.const_get(name, false)
      record_output!(value, seen) if value.is_a?(Module) && value.name&.start_with?(mod.name)
    end
  end

  module Harness
    module Script
      def self.new_downstream(line) = OUTPUT << [:downstream, line]
      def self.new_downstream_xml(line) = OUTPUT << [:downstream_xml, line]
    end

    # Game state the script reads; set what an example needs.
    module XMLData
      class << self
        attr_accessor :name, :game
      end
    end

    body = extract_from_source(LnetSpec::SOURCE, /^class LNet\n.*?^end\n/m, label: 'class LNet', source_path: LnetSpec::SOURCE_PATH)
    assert_parses!(body, label: 'class LNet', source_path: LnetSpec::SOURCE_PATH)
    module_eval(body, LnetSpec::SOURCE_PATH, LnetSpec::SOURCE[0...LnetSpec::SOURCE.index(body)].count("\n") + 1)
  end
  record_output!(Harness::LNet)

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
        parser = lnet::StreamParser.new(lnet.new)
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
      secret: [], waiting: [], alias: {}, options: { 'ignore' => [], 'friends' => [], 'enemies' => [], 'permission' => {} } }
      .each { |name, value| lnet.class_variable_set(:"@@#{name}", value) }
    Harness::XMLData.name = 'Tester'
    Harness::XMLData.game = 'GSIV'
    OUTPUT.clear
  end
end

RSpec.configure do |config|
  config.include LnetSpec::Helpers, file_path: %r{spec/scripts/lnet/}
  config.before(file_path: %r{spec/scripts/lnet/}) { LnetSpec.reset! }
end
