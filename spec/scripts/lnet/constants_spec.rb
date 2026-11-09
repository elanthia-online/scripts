# frozen_string_literal: true

require_relative 'support/harness'

# Running lnet again in one Lich session reopens class LNet. lnet drops the
# constants its own file defines, so each comes from the newer file, and
# leaves the ones other scripts add (inbox.lic defines LNet::Inbox) alone.
RSpec.describe 'lnet.lic constants when lnet runs again' do
  let(:body) { LnetSpec::SOURCE[/^class LNet\n.*?^end\n/m] }
  let(:removed) { body[/^  %i\[([^\]]*)\]\.each \{ \|name\| remove_const/, 1].to_s.split }

  it 'drops every constant the class defines' do
    defined_here = body.scan(/^  ([A-Z][A-Z0-9_]*) = /).flatten + body.scan(/^  (?:class|module) ([A-Z]\w*)/).flatten
    expect(defined_here).not_to be_empty
    expect(defined_here - removed).to eq([])
  end

  it "keeps a constant another script added to LNet, such as inbox.lic's LNet::Inbox" do
    inbox = Module.new
    lnet.const_set(:Inbox, inbox)
    LnetSpec.reload!
    expect(lnet.const_get(:Inbox, false)).to be(inbox)
  ensure
    lnet.send(:remove_const, :Inbox) if lnet.const_defined?(:Inbox, false)
  end

  it 'defines its own constants afresh' do
    old_parser = lnet::StreamParser
    LnetSpec.reload!
    expect(lnet::StreamParser).not_to be(old_parser)
  end
end
