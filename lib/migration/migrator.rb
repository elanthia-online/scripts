module Migration
  class TableNotFound < Exception; end

  class Migrator
    attr_reader :file, :tables
    def initialize(file, tables)
      @file       = file
      @tables     = tables
      @changesets = []
    end

    def build()
      self.instance_eval(File.read(@file), @file)
    end

    def validate()
    end

    def apply()
      apply_insertions()
      apply_deletions()
    end

    def apply_insertions()
      @changesets.each do |changeset| 
        changeset.inserts.each do |key, rules|
          changeset.table.insert(key, *rules)
        end
      end
    end

    def apply_deletions()
      @changesets.each do |changeset| 
        changeset.deletes.each do |key, rules|
          changeset.table.delete(key, *rules)
        end
      end
    end

    def assert_table_exists(table_name)
      table = @tables[Table.normalize_key(table_name)] or
        fail TableNotFound, "Table[:#{table_name}] does not exist"
    end

    def migrate(table_name, &migration)
      table = assert_table_exists(table_name)
      @changesets << ChangeSet.run(table, @file, &migration)
      self
    end
  end
end
