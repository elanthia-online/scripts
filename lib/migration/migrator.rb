module Migration
  class TableNotFound < Exception; end
  class DuplicateTable < Exception; end
  ##
  ## loads a migration Ruby instance and executes it
  ## within a ChangeSet context, storing the result
  ## of the evaluation to be analyzed/applied later
  ## down the compilation line
  ##
  class Migrator
    attr_reader :file, :tables, :basename
    def initialize(file, tables)
      @file       = file
      @tables     = tables
      @basename   = File.basename(@file)
      @changesets = []
    end
    ##
    ## read the file into this binding
    ##
    def build()
      self.instance_eval(File.read(@file), @file)
    end

    def validate()
    end

    def apply()
      apply_creations()
      apply_insertions()
      apply_deletions()
    end

    def apply_creations()
      @changesets.each do |changeset|
        changeset.creates.each do |key|
          Migration.log(%[#{changeset.table.log_name} CREATE key "#{key}"],
            label: %i[changeset],
            color: :light_blue)
          changeset.table.create_key(key)
        end
      end
    end

    def apply_insertions()
      @changesets.each do |changeset| 
        changeset.inserts.each do |key, rules|
          rules.each do |rule|
            Migration.log(%[#{changeset.table.log_name} INSERT #{key} "#{rule}"],
              label: %i[changeset],
              color: :green)
          end
          changeset.table.insert(key, *rules)
        end
      end
    end

    def apply_deletions()
      @changesets.each do |changeset| 
        changeset.deletes.each do |key, rules|
          rules.each do |rule|
            Migration.log(%[#{changeset.table.log_name} DELETE #{key} "#{rule}"],
              label: %i[changeset],
              color: :yellow)
          end

          changeset.table.delete(key, *rules)
        end
      end
    end

    def assert_table_exists(table_name)
      table = @tables[Table.normalize_key(table_name)] or
        fail TableNotFound, Color.red("Table[:#{table_name}] does not exist")
    end

    def assert_table_does_not_exist(table_name)
      table = @tables[Table.normalize_key(table_name)] and
        fail DuplicateTable, Color.red("Table[:#{table_name}] already exists")
    end

    def migrate(*table_names, &migration)
      table_names.each do |table_name|
        table = assert_table_exists(table_name)
        @changesets << ChangeSet.run(table, @file, &migration)
      end
      self
    end

    def create_table(table_name, kind: 'type', keys:[])
      assert_table_does_not_exist(table_name)
      normalized_name = Table.normalize_key(table_name)
      @tables[normalized_name] = Table.new(
        name: normalized_name,
        kind: kind,
        rules: Hash[keys.map { |k| [k, []] }]
      )
      self
    end
  end
end
