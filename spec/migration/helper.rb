# load all files for this subtest
Dir[File.join("lib", "migration", "**", "*.rb")].each do |file| 
  load(file) 
end

module Helper
  module Mocks
    def self.table_path(name)
      File.join(__dir__, "data", "#{name.to_s}.yaml")
    end
  end
end