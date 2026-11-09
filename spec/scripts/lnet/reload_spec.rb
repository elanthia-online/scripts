# frozen_string_literal: true

require_relative 'support/harness'

# Running lnet again in the same Lich session reopens the LNet class: its
# class variables survive and its constants are defined anew.
RSpec.describe 'lnet.lic run again in the same Lich session' do
  after { LnetSpec.reload! }

  it 'keeps its state and defines fresh constants' do
    old_parser = lnet::StreamParser
    lnet.options['friends'] = ['Bob']
    LnetSpec.reload!
    expect(lnet::StreamParser).not_to be(old_parser)
    expect(lnet.options['friends']).to eq(['Bob'])
  end

  it 'keeps the handlers scripts registered' do
    lnet.add_callback('roundtime') { 3 }
    LnetSpec.reload!
    expect(lnet.callbacks.keys).to eq(['roundtime'])
  end

  it 'drops what another script left in the callbacks, so stock requests still get answered' do
    zero_net_callbacks = Class.new { def registered = {} }.new # what 0net stored per request type
    lnet.class_variable_set(:@@callbacks, { 'locate' => zero_net_callbacks, 'mine' => proc { 1 } })
    LnetSpec.reload!
    expect(lnet.callbacks.keys).to eq(['mine'])
    server = LnetSpec::FakeServer.new
    lnet.server = server
    lnet.options['permission']['locate'] = 'all'
    allow(lnet::Responders).to receive(:locate).and_return({ 'here' => true })
    feed(%(<request type="locate" from="Bob"/>))
    expect(lnet::SafeMarshal.decode(REXML::Document.new(server.lines.last).root.text)).to eq('here' => true)
  end

  it 'starts over when the callbacks store is not a hash' do
    lnet.class_variable_set(:@@callbacks, [:junk])
    LnetSpec.reload!
    expect(lnet.callbacks).to eq({})
  end
end
