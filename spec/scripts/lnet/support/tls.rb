# frozen_string_literal: true

require 'openssl'
require 'socket'

module LnetSpec
  # A throwaway certificate authority and a local TLS server, so the
  # connection specs run lnet's real handshake, CA pinning and certificate
  # name check instead of stubbing them.
  module TLS
    # @return [Array(OpenSSL::PKey::EC, OpenSSL::X509::Certificate)]
    def self.authority(name = 'Spec CA')
      key = OpenSSL::PKey::EC.generate('prime256v1')
      cert = build(key, key, OpenSSL::X509::Name.parse("/CN=#{name}"), nil, ca: true)
      [key, cert]
    end

    # @param common_name [String, nil] nil issues a certificate with no CN
    # @return [Array(OpenSSL::PKey::EC, OpenSSL::X509::Certificate)]
    def self.issue(authority, common_name)
      ca_key, ca_cert = authority
      key = OpenSSL::PKey::EC.generate('prime256v1')
      subject = common_name ? OpenSSL::X509::Name.parse("/CN=#{common_name}") : OpenSSL::X509::Name.parse('/O=No Common Name')
      [key, build(key, ca_key, subject, ca_cert, ca: false)]
    end

    def self.build(key, signing_key, subject, issuer, ca:, not_before: Time.now - 60, not_after: Time.now + 3600)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = rand(1..(2**31))
      cert.subject = subject
      cert.issuer = issuer ? issuer.subject : subject
      cert.public_key = key
      cert.not_before = not_before
      cert.not_after = not_after
      extensions = OpenSSL::X509::ExtensionFactory.new
      extensions.subject_certificate = cert
      extensions.issuer_certificate = issuer || cert
      cert.add_extension(extensions.create_extension('basicConstraints', ca ? 'CA:TRUE' : 'CA:FALSE', true))
      cert.sign(signing_key, OpenSSL::Digest.new('SHA256'))
      cert
    end

    # A one-connection TLS server on 127.0.0.1. It records the first line the
    # client sends, then writes `replies` and closes.
    class Server
      attr_reader :port, :received

      # @param key [OpenSSL::PKey]
      # @param cert [OpenSSL::X509::Certificate]
      # @param handshake [Boolean] false accepts TCP but never answers TLS
      def initialize(key, cert, replies: [], handshake: true)
        @tcp = TCPServer.new('127.0.0.1', 0)
        @port = @tcp.addr[1]
        @received = Queue.new
        context = OpenSSL::SSL::SSLContext.new
        context.cert = cert
        context.key = key
        @thread = Thread.new do
          Thread.current.report_on_exception = false
          client = @tcp.accept
          if handshake
            tls = OpenSSL::SSL::SSLSocket.new(client, context)
            tls.sync_close = true
            tls.accept
            @received << tls.gets
            replies.each { |reply| tls.write(reply) }
            tls.close
          else
            sleep 5
            client.close
          end
        rescue StandardError => e
          @received << e
        end
      end

      def close
        @thread.kill
        @tcp.close
      end
    end
  end
end
