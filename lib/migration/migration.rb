require "yaml"
require "rexml/document"

module Migration
  include REXML

  def self.load_tables(tables)
    Hash[tables.map do |table| 
      table = Table.new(table)
      [table.name, table]
    end]
  end

  def self.load_migrations(migrations, tables)
    migrations.sort.map do |migration| 
      Migrator.new(migration, tables) 
    end
  end

  def self.to_xml(tables)
    @tables.values.map(&:to_xml).reduce(Element.new(%{data})) do |root, child|
      root.add_element(child)
      root
    end
  end

  def self.run(**opts)
    @tables     = Migration.load_tables(opts[:tables])
    @migrations = Migration.load_migrations(opts[:migrations], @tables)
    @migrations.each(&:build).each(&:validate).each(&:apply)
    p Migration.to_xml(@tables).to_s
  end
end