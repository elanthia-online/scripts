# frozen_string_literal: true

require_relative 'support/harness'
require_relative 'support/tls'

# The connection layer: connecting and logging in over TLS (against a real
# local TLS server and a throwaway CA pinned in place of LNet's), writing to
# the server from several threads, keepalives and the reconnect loop.
RSpec.describe 'lnet.lic connection' do
  # Records what the script writes; can be told to fail, or to write slowly
  # one character at a time so unsynchronised writers would interleave.
  class FakeServer
    attr_reader :lines, :written

    def initialize(fail_with: nil, slow: false, incoming: [])
      @fail_with = fail_with
      @slow = slow
      @incoming = incoming.dup
      @lines = []
      @written = +''
      @closed = false
    end

    def puts(text)
      raise @fail_with if @fail_with

      if @slow
        "#{text}\n".each_char do |char|
          @written << char
          Thread.pass
        end
      else
        @lines << text
      end
    end

    def readpartial(_max)
      raise IOError, 'closed stream' if @closed
      raise EOFError if @incoming.empty?

      item = @incoming.shift
      item.is_a?(Exception) ? raise(item) : item
    end

    def closed? = @closed
    def close = @closed = true
  end

  let(:authority) { LnetSpec::TLS.authority }

  def serve(common_name, replies: [], handshake: true, authority: self.authority)
    key, cert = LnetSpec::TLS.issue(authority, common_name)
    server = LnetSpec::TLS::Server.new(key, cert, replies: replies, handshake: handshake)
    stub_const("#{lnet}::HOSTNAME", '127.0.0.1')
    stub_const("#{lnet}::PORT", server.port)
    stub_const("#{lnet}::CA_CERTIFICATE", self.authority[1].to_pem)
    @servers = (@servers || []) << server
    server
  end

  after do
    lnet.disconnect
    (@servers || []).each(&:close)
  end

  describe 'LNet.connect' do
    around do |example|
      saved = $version
      $version = '5.99.0'
      example.run
    ensure
      $version = saved
    end

    it 'logs in over TLS to a server whose certificate the pinned CA signed' do
      server = serve('LichNet')
      lnet.secret = 'pa"ss<&>'
      expect(lnet.connect).to be(true)
      expect(lnet.connected?).to be(true)
      login = REXML::Document.new(server.received.pop(timeout: 5)).root
      expect(login.name).to eq('login')
      expect(login.attributes.to_h { |name, attribute| [name, attribute.value] })
        .to eq('name' => 'Tester', 'game' => 'GSIV', 'client' => '1.6', 'lich' => '5.99.0', 'password' => 'pa"ss<&>')
    end

    it 'leaves the password out when none is saved' do
      server = serve('lichproject.org')
      expect(lnet.connect).to be(true)
      expect(server.received.pop(timeout: 5)).not_to include('password')
    end

    it 'refuses a certificate naming another host without ending the process' do
      serve('evil.example')
      result = :unset
      expect { result = lnet.connect }.not_to raise_error
      expect(result).to be(false)
      expect(lnet.connected?).to be(false)
      expect(lnet.connected?).to be(false)
      expect(LnetSpec::OUTPUT).to include([:echo, 'error: server certificate hostname mismatch'])
    end

    it 'refuses a certificate with no common name' do
      serve(nil)
      expect(lnet.connect).to be(false)
      expect(lnet.connected?).to be(false)
    end

    it 'refuses a server whose certificate another CA signed' do
      serve('LichNet', authority: LnetSpec::TLS.authority('Impostor CA'))
      expect(lnet.connect).to be(false)
      expect(lnet.connected?).to be(false)
      expect(LnetSpec::OUTPUT.last[1]).to start_with('error: LNet connection failed:')
    end

    it 'gives up on a server that never answers the TLS handshake' do
      serve('LichNet', handshake: false)
      stub_const("#{lnet}::CONNECT_TIMEOUT", 0.3)
      expect(lnet.connect).to be(false)
      expect(LnetSpec::OUTPUT).to include([:echo, 'error: LNet connection timed out during TCP connect or SSL handshake'])
    end

    it 'closes the socket when lnet is killed mid-handshake' do
      serve('LichNet', handshake: false)
      opened = []
      allow(TCPSocket).to receive(:open).and_wrap_original { |original, *args| original.call(*args).tap { |socket| opened << socket } }
      attempt = Thread.new { lnet.connect }
      sleep 0.05 until opened.any? || !attempt.alive?
      sleep 0.1
      attempt.kill
      attempt.join
      expect(opened.size).to eq(1)
      expect(opened.first.closed?).to be(true)
    end

    it 'reports a refused TCP connection and stays disconnected' do
      allow(lnet).to receive(:open_tls).and_raise(Errno::ECONNREFUSED)
      expect(lnet.connect).to be(false)
      expect(lnet.connected?).to be(false)
    end

    it 'closes the socket when the login cannot be written' do
      socket = FakeServer.new(fail_with: Errno::EPIPE)
      allow(socket).to receive(:peer_cert).and_return(LnetSpec::TLS.issue(authority, 'LichNet')[1])
      allow(lnet).to receive(:open_tls).and_return(socket)
      expect(lnet.connect).to be(false)
      expect(socket.closed?).to be(true)
      expect(lnet.connected?).to be(false)
    end

    it 'closes the previous connection first' do
      old = FakeServer.new
      lnet.server = old
      allow(lnet).to receive(:open_tls).and_raise(Errno::ECONNREFUSED)
      lnet.connect
      expect(old.closed?).to be(true)
    end
  end

  describe 'LNet.trusted_peer?' do
    it 'accepts only the LNet common names' do
      expect(lnet.trusted_peer?(LnetSpec::TLS.issue(authority, 'LichNet')[1])).to be(true)
      expect(lnet.trusted_peer?(LnetSpec::TLS.issue(authority, 'lichproject.org')[1])).to be(true)
      expect(lnet.trusted_peer?(LnetSpec::TLS.issue(authority, 'lichproject.org.evil')[1])).to be(false)
      expect(lnet.trusted_peer?(LnetSpec::TLS.issue(authority, nil)[1])).to be(false)
      expect(lnet.trusted_peer?(nil)).to be(false)
    end
  end

  describe 'LNet.certificate_date_warning' do
    let(:cert) { lnet.ca_certificate }

    it 'warns before the certificate is valid and after it expires, and not in between' do
      expect(lnet.certificate_date_warning(cert, cert.not_before - 1)).to include('date is set incorrectly')
      expect(lnet.certificate_date_warning(cert, cert.not_after + 1)).to include('need an updated version of this script')
      expect(lnet.certificate_date_warning(cert, cert.not_before + 1)).to be_nil
    end
  end

  describe 'sending' do
    it 'returns false without raising before the first connection' do
      sent = :unset
      expect { sent = lnet.send_message({ 'type' => 'channel' }, 'hi') }.not_to raise_error
      expect(sent).to be(false)
    end

    it 'returns false on a closed connection and does not count it as sent' do
      lnet.server = FakeServer.new.tap(&:close)
      before = lnet.last_send
      expect(lnet.send_query({ 'type' => 'connected' })).to be(false)
      expect(lnet.last_send).to eq(before)
    end

    [Errno::EPIPE, Errno::ECONNRESET, IOError.new('closed stream'), OpenSSL::SSL::SSLError.new('bad record')].each do |error|
      it "drops the connection instead of raising when a write fails with #{error.inspect}" do
        socket = FakeServer.new(fail_with: error)
        lnet.server = socket
        expect(lnet.send_request({ 'type' => 'info', 'to' => 'Bob' })).to be(false)
        expect(socket.closed?).to be(true)
        expect(lnet.connected?).to be(false)
      end
    end

    it 'does not close a newer connection when a write on an older one fails' do
      old = FakeServer.new(fail_with: Errno::EPIPE)
      newer = FakeServer.new
      allow(old).to receive(:puts) do
        lnet.server = newer # the connection thread reconnected mid-write
        raise Errno::EPIPE
      end
      lnet.server = old
      expect(lnet.send_ping).to be(false)
      expect(lnet.server).to be(newer)
      expect(newer.closed?).to be(false)
    end

    it 'keeps the closed socket, so LNet.server.closed? shows the disconnect to other scripts' do
      socket = FakeServer.new(fail_with: Errno::EPIPE)
      lnet.server = socket
      lnet.send_ping
      expect(lnet.server).to be(socket)
      expect(lnet.server.closed?).to be(true)
    end

    it 'never interleaves writes from different threads' do
      socket = FakeServer.new(slow: true)
      lnet.server = socket
      threads = Array.new(6) do |t|
        Thread.new { 25.times { |i| lnet.send_message({ 'type' => 'channel' }, "thread #{t} message #{i}") } }
      end
      threads.each(&:join)
      lines = socket.written.split("\n")
      expect(lines.size).to eq(150)
      lines.each { |line| expect(line).to match(%r{\A<message type='channel'>thread \d message \d+</message>\z}) }
    end

    it 'leaves out nil attributes and writes other values as text' do
      socket = FakeServer.new
      lnet.server = socket
      lnet.send_element('admin', { 'action' => 'create poll', 'length' => 3600, 'skip' => nil }, 'a < b')
      expect(socket.lines).to eq([%(<admin action='create poll' length='3600'>a &lt; b</admin>)])
    end
  end

  describe 'LNet.keepalive_tick' do
    let(:now) { Time.now }

    it 'pings after 50 quiet seconds and checks again in 50' do
      socket = FakeServer.new
      lnet.server = socket
      lnet.class_variable_set(:@@last_send, now - 50)
      expect(lnet.keepalive_tick(now)).to eq(50)
      expect(socket.lines).to eq([''])
    end

    it 'waits out the rest of the interval when something was sent recently' do
      lnet.server = FakeServer.new
      lnet.class_variable_set(:@@last_send, now - 10)
      expect(lnet.keepalive_tick(now)).to eq(40)
    end

    it 'checks again in 5 seconds, not in a tight loop, while disconnected' do
      lnet.class_variable_set(:@@last_send, now - 500)
      expect(lnet.keepalive_tick(now)).to eq(5)
    end
  end

  describe 'LNet.reconnect_delay' do
    let(:now) { Time.now }

    it 'waits 30 seconds after a restart notice, once' do
      lnet.server_restart = true
      expect(lnet.reconnect_delay(now - 1000, now)).to eq(30)
      expect(lnet.server_restart).to be(false)
      expect(lnet.reconnect_delay(now - 1000, now)).to eq(1)
    end

    it 'spaces attempts 300 seconds apart after a quick failure' do
      out = LnetSpec.capture { expect(lnet.reconnect_delay(now - 20, now)).to eq(280) }
      expect(out).to eq([[:echo, 'connection lost'], [:echo, 'waiting 280 seconds before trying to reconnect...']])
    end

    it 'reconnects after 1 second when the session lasted longer than the interval' do
      out = LnetSpec.capture { expect(lnet.reconnect_delay(now - 3600, now)).to eq(1) }
      expect(out).to eq([[:echo, 'connection lost']])
    end
  end

  describe 'LNet.connection_loop' do
    it 'survives a LoadError from a session and waits before trying again' do
      stop = Class.new(StandardError)
      allow(lnet).to receive(:connection_cycle).and_raise(LoadError, 'cannot load such file')
      allow(lnet).to receive(:reconnect_delay).and_return(7)
      allow(lnet).to receive(:sleep).with(7).and_raise(stop)
      expect { lnet.connection_loop }.to raise_error(stop)
    end
  end

  describe 'LNet.connection_cycle' do
    it 'does not try to read after a failed connection' do
      allow(lnet).to receive(:connect).and_return(false)
      expect(lnet).not_to receive(:read_session)
      expect(lnet.connection_cycle(Time.now)).to be > 1
    end

    it 'hands everything the server sends to the listener until it hangs up, then disconnects' do
      socket = FakeServer.new(incoming: ['<pi', "ng/>\n<ping/>"])
      allow(lnet).to receive(:connect) do
        lnet.server = socket
        true
      end
      lnet.connection_cycle(Time.now)
      expect(socket.lines).to eq(['<pong/>', '<pong/>']) # each ping reached the listener, which answered
      expect(socket.closed?).to be(true)
      expect(lnet.connected?).to be(false)
    end

    it 'ends the session quietly when the connection is reset' do
      socket = FakeServer.new(incoming: ['<ping/>', Errno::ECONNRESET.new])
      allow(lnet).to receive(:connect) do
        lnet.server = socket
        true
      end
      expect { lnet.connection_cycle(Time.now) }.not_to raise_error
      expect(socket.lines).to eq(['<pong/>'])
    end
  end
end
