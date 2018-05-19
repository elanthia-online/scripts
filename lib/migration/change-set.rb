require "pathname"

module Migration
  class PrettyError < Exception 
    def initialize(changeset, msg)
      super <<~ERROR
        \n\t#{changeset.file.split("../").last} >> Table[#{changeset.table.name}] #{msg}
        ERROR
    end
  end
  class KeyError < PrettyError; end
  class RuleError < PrettyError; end

  class ChangeSet
    def self.run(table, file, &block)
      changeset = ChangeSet.new(table, file)
      changeset.instance_eval(&block)
      changeset
    end

    attr_reader :table, :file, :inserts, :deletes
    def initialize(table, file)
      @table   = table
      @file    = file
      @inserts = {}
      @deletes = {}
      @table.pending << self
    end

    def assert_key_missing(key)
      @table.has_key?(key) and
        fail KeyError.new(self, %{should not have key :#{key}})
    end

    def assert_key_exists(key)
      @table.has_key?(key) or
        fail KeyError.new(self, %{should have key :#{key}})
    end

    def assert_rule_missing(key, rule)
      @table.has_rule?(key, rule) and
        fail RuleError.new(self, %{:#{key} already has Rule<#{rule}>})
    end

    def assert_rule_exists(key, rule)
      @table.has_rule?(key, rule) or
        fail RuleError.new(self, %{:#{key} does not have Rule<#{rule}>})
    end

    def insert(key, *rules)
      assert_key_exists(key)
      key = Table.normalize_key(key)
      rules.each do |rule| assert_rule_missing(key, rule) end
      @inserts[key] = [*@inserts[key], *rules]
      self
    end

    def delete(key, *rules)
      assert_key_exists(key)
      key = Table.normalize_key(key)
      rules.each do |rule| assert_rule_exists(key, rule) end
      @deletes[key] = [*@deletes[key], *rules]
      self
    end

    def create_key(key)
      assert_key_missing(key)
      fail Exception, "create_key() not implemented yet"
    end
  end
end