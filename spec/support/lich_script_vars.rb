# Script.current.vars as lich-5 v5.21.0 builds them (lib/common/script.rb,
# Script#initialize, lines 1734-1750), for the specs that start a script
# with arguments: log_spec.rb and logxml_spec.rb.
module LichScriptVars
  # A String (typed, ;log ...) is vars[0] whole, then split on spaces with
  # quotes honoured and removed (an escaped quote stays as a quote); an
  # Array (autostart's saved :args) is vars[0] joined with spaces, then the
  # items as they are, quotes and all. An empty String or Array, or nil,
  # gives [] (so vars[1..] is nil, not []).
  #
  # @param args [String, Array<String>, nil]
  # @return [Array<String>]
  def self.build(args)
    case args
    when String
      return [] if args.empty?

      [args] + args.scan(/[^\s"]*(?<!\\)"(?:\\"|[^"])+(?<!\\)"[^\s]*|(?:\\"|[^"\s])+/).collect { |s| s.gsub(/(?<!\\)"/, '').gsub('\\"', '"') }
    when Array
      args.empty? ? [] : [args.join(' '), *args]
    else
      []
    end
  end
end
