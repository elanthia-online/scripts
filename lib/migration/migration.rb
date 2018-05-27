require "yaml"
require "rexml/document"
require "fileutils"

module Migration
  include REXML
  # creates a raw xml element that does not escape
  # html entities, so regexp can properly be serialized
  def self.raw_element(name, parent = nil)
    Element.new(name, parent, context = {raw: :all, attribute_quote: :quote})
  end
  ##
  ## lookup from cwd
  ##
  def self.cwd(*parts)
    File.join(Dir.pwd, *parts)
  end

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
    root = raw_element(%{data})
    @tables.values.map(&:to_xml).each do |child|
      root.add_element(child)
    end
    root
  end

  def self.run(**opts)
    FileUtils.mkdir_p opts.fetch(:dist)
    @tables     = Migration.load_tables opts.fetch(:tables)
    @migrations = Migration.load_migrations(opts.fetch(:migrations), @tables)
    @migrations.each(&:build).each(&:validate).each(&:apply)
    asset = File.join(opts.fetch(:dist), "gameobj-data.xml")
    puts %{[migration] writing #{asset}}
    File.open(asset, %{w+}) do |file|
      formatter = REXML::Formatters::Pretty.new
      formatter.compact = true
      formatter.write(Migration.to_xml(@tables), file)
    end
  end
end