# frozen_string_literal: true

require_relative 'support/harness'

RSpec.describe 'lnet.lic' do
  describe '<data> from the server' do
    it 'never runs a load hook from an unsolicited payload, and says it ignored it' do
      LnetSpec::Gadget.loaded = 0
      out = feed(data_element({ 'k' => LnetSpec::Gadget.new }))
      expect(LnetSpec::Gadget.loaded).to eq(0)
      expect(out.size).to eq(1)
      expect(out.first[0]).to eq(:echo)
      expect(out.first[1]).to start_with('ignored info data from Bob that contained something other than plain values')
    end

    it 'still renders the server connected list' do
      out = feed(data_element(['GSIV:Bob', 'GSIV:Ann'], from: 'server', type: 'connected'))
      expect(out.last[0]).to eq(:respond)
      expect(out.last[1]).to include('GSIV (2):', 'Bob', 'Ann', 'Total connected: 2')
    end
  end
end
