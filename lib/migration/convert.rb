module Migration
  module Convert
    # (?:seasoned |grizzled |battle\-scarred |ancient |veteran )?  
    def self.maybe_pattern_to_regex(maybes = nil, space: nil)
      return %{} if maybes.nil?
      #Migration.log(maybes, label: %i[maybes])
      with_whitespace = maybes.map do |maybe|
        if space.eql?(:left)
          " " + maybe
        elsif space.eql?(:right)
          maybe + " " 
        else
          maybe
        end 
      end.join("|")
      %{(?:#{with_whitespace})?}
    end

    def self.ruleset_to_regex(ruleset, prefix = nil, suffix = nil)
      pattern = %[(] + ruleset.join("|") + %[)]
      pattern = prefix + pattern unless prefix.nil?
      pattern = pattern + suffix unless suffix.nil?
      %{^#{pattern}$}
    end

    def self.to_safe_xml(str)
      str.gsub(%[&], %[&amp;])
    end
  end
end