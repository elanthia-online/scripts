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

    it 'hands a plain reply to the waiting request' do
      waiter = { 'type' => 'info', 'name' => 'Bob', 'data' => :waiting }
      lnet.class_variable_get(:@@waiting).push(waiter)
      feed(data_element(LnetSpec::REAL_PAYLOADS['info']))
      expect(waiter['data']).to eq(LnetSpec::REAL_PAYLOADS['info'])
    ensure
      lnet.class_variable_get(:@@waiting).delete(waiter)
    end

    it 'fails the waiting request at once when the reply is refused' do
      waiter = { 'type' => 'info', 'name' => 'Bob', 'data' => :waiting }
      other = { 'type' => 'skills', 'name' => 'Bob', 'data' => :waiting }
      lnet.class_variable_get(:@@waiting).push(waiter, other)
      out = feed(data_element([LnetSpec::Gadget.new]))
      expect(waiter['data']).to be(false)
      expect(other['data']).to eq(:waiting)
      expect(out.map(&:first)).to eq([:echo])
    ensure
      lnet.class_variable_get(:@@waiting).delete(waiter)
      lnet.class_variable_get(:@@waiting).delete(other)
    end

    # drives the real LNet.get_data against a stub server, so this covers the
    # request -> refused reply -> return path rather than the waiter alone
    it 'returns false from get_data without waiting out the 8 second timeout' do
      server = Class.new do
        attr_reader :sent

        def initialize = @sent = Queue.new
        def closed? = false
        def puts(xml) = @sent << xml.to_s
      end.new
      saved = lnet.server
      lnet.server = server
      requester = Thread.new { lnet.get_data(+'bob', 'info') } # get_data capitalizes its argument in place
      expect(server.sent.pop(timeout: 2)).to match(/<request (?=.*type=.info.)(?=.*to=.Bob.)/)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      feed(data_element(LnetSpec::Gadget.new))
      expect(requester.join(3)&.value).to be(false)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    ensure
      requester&.kill
      lnet.server = saved
    end

    it 'still renders the server connected list' do
      out = feed(data_element(['GSIV:Bob', 'GSIV:Ann'], from: 'server', type: 'connected'))
      expect(out.last[0]).to eq(:respond)
      expect(out.last[1]).to include('GSIV (2):', 'Bob', 'Ann', 'Total connected: 2')
    end
  end
end
