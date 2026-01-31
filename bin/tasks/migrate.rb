##
## load all assets
##
require_relative("../../lib/migration.rb")
puts '1'
##
## do eeet
##
Migration.run(
  migrations: Dir[Migration.cwd("type_data", "migrations", "**", "*.rb")],
  tables: Dir[Migration.cwd("type_data", "tables", "**", "*.yaml")],
  dist: Migration.cwd("dist")
)
puts '2'
