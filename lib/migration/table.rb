require "yaml"
require "rexml/document"

module Migration
  class Table
    include REXML

    def self.normalize_key(key)
      key.to_s.downcase.to_sym
    end

    attr_reader :rules, :name, :pending
    def initialize(file)
      @name    = File.basename(file, ".yaml").to_sym
      @rules   = Hash[YAML.load_file(file).map do |(k,v)| 
        [Table.normalize_key(k), v] 
      end]
      @pending = []
    end

    def has_key?(key)
      !@rules[Table.normalize_key(key)].nil?
    end

    def has_rule?(key, rule)
      @rules[Table.normalize_key(key)].include?(rule)
    end

    def get(key, default = nil)
      @rules.fetch(Table.normalize_key(key), default)
    end

    def insert(key, *rules)
      @rules[Table.normalize_key(key)] = [*@rules[Table.normalize_key(key)], *rules]
    end

    def delete(key, *rules)
      rules.each do |rule|
        @rules[Table.normalize_key(key)].delete(rule)
      end
    end

    def to_regex()
      Hash[@rules.map do |k, ruleset|
        [k, Convert.rules_to_regex(ruleset)]
      end]
    end

    def to_xml()
      table = Element.new(%{type})
      table.add_attribute %{name}, @name.to_s.gsub("_", " ")
      to_regex.reduce(table) do |node, pair|
        element = Element.new(pair.first.to_s)
        node.add_element(element)
        element.add_text(pair.last)
        node
      end
    end
  end
end