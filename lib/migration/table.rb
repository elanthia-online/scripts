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
      Migration.log(%{loading #{file}}, label: %i[table])
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
      regex_map = Hash.new
      prefix = Convert.prefix_to_regex(@rules.fetch(:prefix, nil))
      name_rules = @rules.fetch(:name, false)
      # name rules are different, as they can be quite convoluted
      regex_map[:name] = Convert.ruleset_to_regex(name_rules, prefix) unless name_rules.eql?(false)
      @rules.select do |kind| (%i[name prefix] & [kind]).empty? end.each do |kind, ruleset|
        regex_map[kind] = Convert.ruleset_to_regex(ruleset)
      end

      regex_map
    end

    def to_xml()
      ## create a new xml type def
      xml = Migration.raw_element(%{type})
      ## create the name that will be used for the type data
      xml.add_attribute %{name}, @name.to_s.gsub("_", " ")
      ## add all definitions to this xml table
      to_regex.each do |kind, pattern|
        element = Migration.raw_element(kind.to_s)
        xml.add_element(element)
        element.add_text(pattern)
      end
      ## return the created document
      return xml
    end
  end
end