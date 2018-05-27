module Migration
  module Convert
    # (?:seasoned |grizzled |battle\-scarred |ancient |veteran )?  
    def self.prefix_to_regex(prefixes = nil)
      return %{} if prefixes.nil?
      with_whitespace = prefixes.map do |prefix| prefix + " " end.join("|")
      %{(?:#{with_whitespace})?}
    end

    def self.ruleset_to_regex(ruleset, prefix = nil)
      pattern = ruleset.join("|")
      pattern = prefix + pattern unless prefix.nil?
      %{^(#{pattern})$}
    end
  end
end