# frozen_string_literal: true

require_relative '../spec_helper'

# Spec for sloot.lic's gem stockpile bookkeeping (the `stockpile` proc).
#
# sloot.lic cannot be required standalone: it needs the whole Lich runtime
# and starts looting on load. Instead the real `stockpile = proc { ... }`
# body and the real `putregex` are extracted from scripts/sloot.lic and
# evaluated inside a Runner whose game commands are answered by a small
# locker/sack model, so these examples drive production code.
#
# CharSettings is backed by StrictSettings below, which models the contract
# every lich-5 Settings version keeps: a value is stored only when it is
# written through what CharSettings returns (CharSettings[k] = v, or a write
# through the returned container). Each read returns a fresh copy, and a
# plain object handed to push is copied on the way in, so changing that
# object afterwards stores nothing. As in lich-5, a write whose path holds a
# negative Array index (CharSettings[:jars][-1]) stores nothing. lich-5
# today stores such a change to the pushed object only when a later write
# happens to save the whole array again, and not at all once reads always
# come from the database, so a script must not rely on it.
#
# GameObj and CharSettings live nested inside SlootSpec::Runner rather than
# at the top level, for the reason spec/spec_helper.rb gives: a top-level
# GameObj would corrupt lib/lich/gameobj.rb's real class for other specs.
module SlootSpec
  SOURCE_PATH = find_lic_source('sloot.lic', from: __dir__)
  SOURCE = File.read(SOURCE_PATH).gsub("\r\n", "\n")

  STOCKPILE_SRC = extract_from_source(SOURCE, /^stockpile = proc \{\n.*?^\}\n/m,
                                      label: 'stockpile proc', source_path: SOURCE_PATH)
  assert_parses!(STOCKPILE_SRC, label: 'stockpile proc', source_path: SOURCE_PATH)
  STOCKPILE_LINE = SOURCE[0...SOURCE.index(STOCKPILE_SRC)].count("\n") + 1

  PUTREGEX_SRC = extract_from_source(SOURCE, /^putregex = .*$/, label: 'putregex', source_path: SOURCE_PATH)
  PUTREGEX = eval(PUTREGEX_SRC.sub(/\Aputregex = /, ''), binding, SOURCE_PATH)

  # Settings store with the strict write-through contract described above.
  class StrictSettings
    attr_reader :store

    def initialize
      @store = {}
    end

    def self.copy(value)
      Marshal.load(Marshal.dump(value))
    end

    def self.container?(value)
      value.is_a?(Hash) || value.is_a?(Array)
    end

    def [](key)
      value = @store[key]
      self.class.container?(value) ? Proxy.new(self, [key], self.class.copy(value)) : value
    end

    def []=(key, value)
      @store[key] = self.class.copy(Proxy.unwrap(value))
    end

    # Replays an in-place operation on the stored container at path. Like
    # lich-5's save_proxy_changes, a path with a negative Array index (a
    # write through CharSettings[:jars][-1], say) saves nothing.
    def apply(path, leaf = nil)
      return if (path + [leaf]).any? { |key| key.is_a?(Integer) && key.negative? }

      yield(path.reduce(@store) { |container, key| container[key] })
    end
  end

  # What CharSettings[...] returns for a container: a copy whose writes are
  # replayed on the stored container at the same path.
  class Proxy
    def self.unwrap(value)
      value.is_a?(Proxy) ? value.target : value
    end

    attr_reader :target

    def initialize(settings, path, target)
      @settings = settings
      @path = path
      @target = target
    end

    def [](key)
      value = @target[key]
      StrictSettings.container?(value) ? Proxy.new(@settings, @path + [key], value) : value
    end

    def []=(key, value)
      value = StrictSettings.copy(Proxy.unwrap(value))
      @target[key] = value
      @settings.apply(@path, key) { |stored| stored[key] = StrictSettings.copy(value) }
    end

    def push(*values)
      values = values.map { |v| StrictSettings.copy(Proxy.unwrap(v)) }
      @target.push(*values)
      @settings.apply(@path) { |stored| stored.push(*StrictSettings.copy(values)) }
      self
    end

    def delete(value)
      value = Proxy.unwrap(value)
      @settings.apply(@path) { |stored| stored.delete(value) }
      @target.delete(value)
    end

    # Array#find hands back the element at its index, like lich-5 does.
    def find(&block)
      index = @target.index(&block)
      index && self[index]
    end

    def nil?
      @target.nil?
    end

    def ==(other)
      @target == Proxy.unwrap(other)
    end

    def method_missing(name, *args, &block)
      return super unless @target.respond_to?(name)

      StrictSettings.copy(@target).public_send(name, *args, &block)
    end

    def respond_to_missing?(name, include_private = false)
      @target.respond_to?(name, include_private) || super
    end
  end

  Item = Struct.new(:id, :noun, :name, :type, :after_name)

  # One locker and one gem sack, answering the commands the stockpile proc
  # sends. Jars hold `capacity` gems. Game text here is only what the proc's
  # own regexes require; it is not a transcript of real game output.
  class Locker
    LOCKER_ID = '9000'
    # Like GameObj#contents, contents hands back a copy of the item list.
    Container = Struct.new(:id, :items) do
      def contents
        items.dup
      end
    end

    attr_reader :locker, :sack, :in_hand, :commands, :jar_contents

    def initialize(capacity: 50)
      @capacity = capacity
      @locker = []
      @sack = Container.new('8000', [])
      @in_hand = []
      @jar_contents = {}
      @refuse = {}
      @commands = []
      @next_id = 100
    end

    # An empty jar's after_name is '' rather than nil: the proc calls gsub on
    # it, which only Lich's runtime NilClass patch makes safe for nil, and ''
    # gives the same match results.
    # refuses: a gem name the jar will not take.
    def add_jar(gem: nil, count: 0, refuses: nil)
      jar = Item.new(next_id, 'jar', 'glass jar', 'container', gem ? "containing #{gem}" : '')
      @jar_contents[jar.id] = Array.new(count, gem)
      @refuse[jar.id] = refuses
      @locker << jar
      jar
    end

    def add_gems(name, count)
      count.times { @sack.items << Item.new(next_id, name.split.last, name, 'gem', nil) }
    end

    def containers
      { LOCKER_ID => @locker }
    end

    def command(cmd)
      @commands << cmd
      case cmd
      when 'open locker' then %(You open <a exist="#{LOCKER_ID}" noun="locker">a locker</a>.)
      when 'close locker' then 'You close the locker.'
      when /\A_drag #(\d+) #(\d+)\z/ then drag(Regexp.last_match(1), Regexp.last_match(2))
      when /\Aput #(\d+) in #(\d+)\z/ then put(Regexp.last_match(1), Regexp.last_match(2))
      when /\Aget #(\d+)(?: from #\d+)?\z/ then get(Regexp.last_match(1))
      else raise "unexpected command #{cmd.inspect}"
      end
    end

    private

    def next_id
      (@next_id += 1).to_s
    end

    def drag(gem_id, jar_id)
      gem = @sack.items.find { |item| item.id == gem_id }
      raise "gem #{gem_id} is not in the sack" unless gem

      jar = @in_hand.find { |item| item.id == jar_id }
      raise "jar #{jar_id} is not in hand" unless jar
      return "The #{gem.name} does not appear to be a suitable container for that." if @refuse[jar_id] == gem.name

      contents = @jar_contents[jar_id]
      return 'The jar is full.' if contents.length >= @capacity

      @sack.items.delete(gem)
      contents << gem.name
      if contents.length == 1
        jar.after_name = "containing #{gem.name}s"
        return "You put #{gem.name} in your jar."
      end
      contents.length == @capacity ? "You add #{gem.name} to your jar, filling it." : "You add #{gem.name} to your jar."
    end

    def put(item_id, container_id)
      if (item = @in_hand.find { |i| i.id == item_id })
        @in_hand.delete(item)
        (container_id == LOCKER_ID ? @locker : @sack.items) << item
      elsif !(container_id == @sack.id && @sack.items.any? { |i| i.id == item_id })
        raise "#{item_id} is not at hand"
      end
      'You put the item in the container.'
    end

    def get(item_id)
      item = @locker.find { |i| i.id == item_id } || @sack.items.find { |i| i.id == item_id }
      raise "#{item_id} is not in the locker or sack" unless item

      @locker.delete(item)
      @sack.items.delete(item)
      @in_hand << item
      'You remove the item.'
    end
  end

  class Runner
    module CharSettings
      class << self
        attr_accessor :model

        def [](key)
          model[key]
        end

        def []=(key, value)
          model[key] = value
        end
      end
    end

    module GameObj
      class << self
        attr_accessor :game

        def containers
          game.containers
        end
      end
    end

    attr_reader :echoes

    def initialize(game)
      @game = game
      @echoes = []
    end

    def status_tags(*) = nil
    def empty_hands = nil
    def fill_hands = nil

    def dothistimeout(cmd, _timeout, _regex)
      @game.command(cmd)
    end

    def fput(cmd)
      @game.command(cmd)
    end

    def echo(msg)
      @echoes << msg
    end

    class_eval(<<~RUBY, SOURCE_PATH, STOCKPILE_LINE - 1)
      def run_stockpile(sacks, putregex)
        #{STOCKPILE_SRC}
        stockpile.call
      end
    RUBY
  end
end

RSpec.describe 'sloot.lic stockpile jar counts' do
  let(:settings) { SlootSpec::StrictSettings.new }
  let(:game) { SlootSpec::Locker.new(capacity: capacity) }
  let(:capacity) { 50 }

  before do
    SlootSpec::Runner::CharSettings.model = settings
    SlootSpec::Runner::GameObj.game = game
  end

  def run_stockpile
    SlootSpec::Runner.new(game).run_stockpile({ 'gem' => game.sack }, SlootSpec::PUTREGEX)
  end

  def stored_jars
    settings.store[:jars]
  end

  context 'when a gem type is started in an empty jar' do
    before do
      settings[:jars] = [{ gem: 'rubies', count: 3, full: false }]
      settings[:empty_jar_count] = 1
      game.add_jar(gem: 'rubies', count: 3)
      game.add_jar
    end

    it 'stores every gem added after the first one' do
      game.add_gems('opal', 4)
      run_stockpile
      expect(game.jar_contents.values.last.length).to eq(4)
      expect(stored_jars).to eq([{ gem: 'rubies', count: 3, full: false },
                                 { gem: 'opals', count: 4, full: false }])
    end

    it 'stores a lone first gem as a count of 1' do
      game.add_gems('opal', 1)
      run_stockpile
      expect(stored_jars.last).to eq({ gem: 'opals', count: 1, full: false })
    end

    context 'when the jar fills before the sack is empty' do
      let(:capacity) { 3 }

      it 'stores the count and the full flag, and keeps the leftover gem out of the jar' do
        game.add_gems('opal', 5)
        run_stockpile
        expect(stored_jars.last).to eq({ gem: 'opals', count: 3, full: true })
        expect(game.sack.items.count { |item| item.name == 'opal' }).to eq(2)
      end
    end
  end

  it 'stores the counts of two jars started in the same visit' do
    settings[:jars] = []
    settings[:empty_jar_count] = 2
    game.add_jar
    game.add_jar
    game.add_gems('opal', 3)
    game.add_gems('jade', 2)
    run_stockpile
    expect(stored_jars).to eq([{ gem: 'opals', count: 3, full: false },
                               { gem: 'jades', count: 2, full: false }])
  end

  it 'adds no jar entry when the empty jar refuses the gem' do
    settings[:jars] = [{ gem: 'rubies', count: 3, full: false }]
    settings[:empty_jar_count] = 1
    game.add_jar(refuses: 'opal')
    game.add_gems('opal', 2)
    run_stockpile
    expect(stored_jars).to eq([{ gem: 'rubies', count: 3, full: false }])
    expect(game.sack.items.count { |item| item.name == 'opal' }).to eq(2)
  end

  it 'still stores additions to a jar already in the stockpile' do
    settings[:jars] = [{ gem: 'opals', count: 2, full: false }, { gem: 'rubies', count: 3, full: false }]
    settings[:empty_jar_count] = 0
    game.add_jar(gem: 'opals', count: 2)
    game.add_jar(gem: 'rubies', count: 3)
    game.add_gems('ruby', 2)
    run_stockpile
    expect(stored_jars).to eq([{ gem: 'opals', count: 2, full: false }, { gem: 'rubies', count: 5, full: false }])
  end
end
