# load all files for this subtest
load("lib/migration.rb")

module Helper
  module Mocks
    def self.table_path(name)
      File.join(__dir__, "data", "#{name.to_s}.yaml")
    end
  end
end