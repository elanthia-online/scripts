# frozen_string_literal: true

require_relative 'support/harness'

# lnet.lic says "required: Lich > 5.0.1", and Lich before 5.20 runs on Ruby
# 2.6, so the script has to parse and run there.
RSpec.describe 'lnet.lic on the oldest Ruby Lich supports' do
  let(:code) { LnetSpec::SOURCE.lines.grep_v(/\A\s*#/).join }

  it 'parses as Ruby 2.6' do
    begin
      require 'parser/ruby26'
    rescue LoadError
      skip 'needs the parser gem'
    end
    parser = Parser::Ruby26.new
    parser.diagnostics.all_errors_are_fatal = true
    parser.diagnostics.consumer = ->(_diagnostic) {}
    buffer = Parser::Source::Buffer.new(LnetSpec::SOURCE_PATH, source: LnetSpec::SOURCE)
    expect { parser.parse(buffer) }.not_to raise_error
  end

  { 'filter_map' => '2.7', 'pop(timeout:' => '3.2', '.tally' => '2.7', '.intersect?' => '3.1', '.except(' => '3.0' }.each do |call, version|
    it "does not call #{call} (Ruby #{version})" do
      expect(code).not_to include(call)
    end
  end
end
