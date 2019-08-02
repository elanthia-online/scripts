##
## load all assets
##
require_relative("../../lib/migration.rb")
##
## do eeet
##
Migration.run(
  migrations: Dir[Migration.cwd("type_data", "migrations", "**", "*.rb")],
  tables:     Dir[Migration.cwd("type_data", "tables", "**", "*.yaml")],
  dist:       Migration.cwd("dist"))