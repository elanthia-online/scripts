##
## load all assets
##
Dir[File.join(__dir__, "..", "lib", "migration", "**", "*.rb")].each do |file| require(file) end
##
## do eeet
##
Migration.run(
  migrations: Dir[Migration.cwd("type_data", "migrations", "**", "*.rb")],
  tables:     Dir[Migration.cwd("type_data", "tables", "**", "*.yaml")],
  dist:       Migration.cwd("dist"))