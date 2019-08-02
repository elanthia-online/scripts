require "yaml"
require "rexml/document"

module Migration
  class Table
    include REXML
    #
    # metadata keys used by migration tool
    # to understand more details about a table
    #
    METADATA_KEYS     = %i[kind prefix suffix]
    #
    # keys that gameobj-data.xml expects
    #
    GAMEOBJ_DATA_KEYS = %i[name noun exclude]
    ##
    ## whitelist of keys a table is allowed to export
    ##
    ALLOWED_KEYS = ([] + METADATA_KEYS + GAMEOBJ_DATA_KEYS)
    #
    # Empty Ruleset Error
    #
    def self.raise_empty_ruleset(table)
      fail Exception, <<~ERROR
       Table[#{table.name}] exported an empty RuleSet and that is not allowed
      ERROR
    end
    #
    # Error for bad key validation
    #
    def self.raise_bad_rule_kind(table, key)
      fail Exception, <<~ERROR
        Key[#{key}] in Table[#{table.name}] not a valid Key

            allowed metadata keys: #{METADATA_KEYS}
        allowed game-obj.xml keys: #{GAMEOBJ_DATA_KEYS}
      ERROR
    end
    ##
    ## normalizes a key to what gameobj-data format expects
    ##
    def self.normalize_key(key)
      key.to_s.downcase.to_sym
    end
    #
    # validate that a ruleset only contains
    # whitelisted keys
    #
    def self.validate_ruleset(table, ruleset)
      # validate all keys
      ruleset.keys.each do |key| ALLOWED_KEYS.include?(key) or raise_bad_rule_kind(table, key) end
      # validate existance of at least one valid RuleSet on the table
      (ruleset.keys & GAMEOBJ_DATA_KEYS).size > 0 or raise_empty_ruleset(table)
    end
    #
    # Table Attributes
    #
    attr_reader :name,     # the name of the table in gameob-data.xml
                           #
                :rules,    # the set of rules that will be applied
                           # on encoding the table to gameobj-data.xml
                           #
                :pending,  # you can mark a table pending 
                           # and it will not compile
                           # 
                :kind,     # sellable | type
                :basename, # the basename of the table
                :log_name  # name to appear in logs
    ##
    ## reads a .yaml definition into memory
    ## so that migrations may be layered ontop
    ##
    def initialize(name:, kind:, rules:)
      @name     = name.to_sym
      @log_name = %[Table(:#{@name})]
      @rules    = rules
      @kind     = kind
      @pending = []
    end

    def self.from_yaml(file)
      name     = File.basename(file, ".yaml").to_sym
      log_name = %[Table(:#{name})]
      # output something useful
      # about how we are loading this data
      Migration.log(%{decoding #{log_name} from #{file}},
        label: %i[table],
        color: :blue)

      rules = Hash[YAML.load_file(file).map do |(k,v)|
        [Table.normalize_key(k), v]
      end]
      kind = rules.fetch(:kind, "type")
      Table.validate_ruleset(self, rules)
      # this should not be compiled to the XML output
      rules.delete(:kind)
      self.new(
        name: name,
        kind: kind,
        rules: rules
      )
    end
    #
    # check for existance of a key
    #
    def has_key?(key)
      !@rules[Table.normalize_key(key)].nil?
    end
    #
    # check if a given key has a rule
    #
    def has_rule?(key, rule)
      @rules[Table.normalize_key(key)].include?(rule)
    end
    #
    # fetches the current matcher expression 
    # from  the table by key
    #
    def get(key, default = nil)
      @rules.fetch(Table.normalize_key(key), default)
    end
    #
    # inserts a new rule into a table on
    # the appropriate key
    #
    def insert(key, *rules)
      @rules[Table.normalize_key(key)] = [*@rules[Table.normalize_key(key)], *rules]
    end
    #
    # deletes a rule from a table on a key
    # since we are doing migrations over time
    # it is important to have "rollbacks"
    #
    def delete(key, *rules)
      rules.each do |rule|
        @rules[Table.normalize_key(key)].delete(rule)
      end
    end
    #
    # creates a new key with an empty ruleset
    #
    def create_key(key)
      insert(key)
    end
    #
    # dumps the table key/ruleset pairs to 
    # a Map(Key, Regexp) that can be used
    #
    def to_regex()
      Table.validate_ruleset(self, @rules)
      regex_map = Hash.new
      prefix = Convert.maybe_pattern_to_regex(@rules.fetch(:prefix, nil), space: :right)
      suffix = Convert.maybe_pattern_to_regex(@rules.fetch(:suffix, nil))
      name_rules = @rules.fetch(:name, false)
      # name rules are different, as they can be quite convoluted
      regex_map[:name] = Convert.ruleset_to_regex(name_rules, prefix, suffix) unless name_rules.eql?(false)
      @rules.select do |kind| (%i[name prefix] & [kind]).empty? end.each do |kind, ruleset|
        next if ruleset.empty?
        regex_map[kind] = Validate.regexp(self, kind,
          Convert.ruleset_to_regex(ruleset))
      end
      regex_map
    end
    #
    # compiles the table key/ruleset pairs to
    # an XML document
    #
    def to_xml()
      ## create a new xml type def
      xml = Migration.raw_element(@kind)
      ## create the name that will be used for the type data
      xml.add_attribute %{name}, @name.to_s.gsub("_", " ")
      ## add all definitions to this xml table
      to_regex.each do |kind, pattern|
        element = Migration.raw_element(kind.to_s)
        xml.add_element(element)
        element.add_text(
          Convert.to_safe_xml(pattern))
      end
      ## return the created document
      return xml
    end
  end
end
