module Migration
  module Convert
    def self.rules_to_regex(rules)
      %{^(#{rules.join("|")})$}
    end
  end
end