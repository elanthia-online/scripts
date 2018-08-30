module Migration
  class ValidationError < Exception; end

  module Validate
    def self.regexp(table, key, body)
      begin
        Regexp.new(body)
      rescue => err
        fail ValidationError, <<~ERROR
          
          Table[#{table.name}:#{key}] -> Error
            #{err.message}

        ERROR
      end
      body
    end
  end
end