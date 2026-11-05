# frozen_string_literal: true

require_relative '../spec_helper'
require 'rexml/document'

# Specs for cast-procs in effect-list.xml. Lich's Spell#cast evals a spell's
# cast-proc with the cast's target as a local and never passes it the cast
# options, so a cast-proc that picks an element has to read it from the target.
module EffectListSpec
  DOC = REXML::Document.new(File.read(find_lic_source('effect-list.xml', from: __dir__)))

  def self.cast_proc(num)
    REXML::XPath.first(DOC, "//spell[@number='#{num}']/cast-proc")&.text or
      raise "no cast-proc for #{num} in effect-list.xml"
  end

  module UserVars
    class << self
      attr_accessor :resist_element
    end
  end

  # Runs a cast-proc the way Spell#cast does and records the commands it sends.
  class Caster
    attr_reader :sent

    def initialize(num)
      @source = EffectListSpec.cast_proc(num)
      @sent = []
    end

    def cast(target = nil) # rubocop:disable Lint/UnusedMethodArgument -- read by the eval'd cast-proc
      eval(@source) # mirrors Lich's Spell#cast
    end

    private

    def checkprep
      'None'
    end

    def dothistimeout(cmd, *)
      @sent << cmd
    end
  end
end

RSpec.describe 'effect-list.xml Resist Nature (620) cast-proc' do
  let(:caster) { EffectListSpec::Caster.new(620) }

  before { EffectListSpec::UserVars.resist_element = 'heat' }

  it 'takes the element from the target' do
    caster.cast('cold')
    expect(caster.sent).to eq(['incant 620 cold'])
  end

  it 'uses UserVars.resist_element with no target' do
    caster.cast
    expect(caster.sent).to eq(['incant 620 heat'])
  end

  it 'treats a multicast count as no element' do
    caster.cast('2')
    expect(caster.sent).to eq(['incant 620 heat'])
  end
end
