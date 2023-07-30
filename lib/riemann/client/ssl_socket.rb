# frozen_string_literal: true

require 'openssl'
require_relative 'tcp_socket'

module Riemann
  class Client
    # Socket: A specialized socket that has been configure
    class SSLSocket < TcpSocket
      def initialize(options = {})
        super(options)
        @key_file = options[:key_file]
        @cert_file = options[:cert_file]
        @ca_file = options[:ca_file]
        @ssl_verify = options[:ssl_verify]
      end

      def ssl_context
        @ssl_context ||= OpenSSL::SSL::SSLContext.new.tap do |ctx|
          ctx.key = OpenSSL::PKey::RSA.new(File.read(@key_file))
          ctx.cert = OpenSSL::X509::Certificate.new(File.read(@cert_file))
          ctx.ca_file = @ca_file if @ca_file
          ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
          ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER if @ssl_verify
        end
      end

      # Internal: Connect to the give address within the timeout.
      #
      # Make an attempt to connect to a single address within the given timeout.
      #
      # Return the ::Socket when it is connected, or raise an Error if no
      # connection was possible.
      def connect_nonblock(addr, timeout)
        sock = super(addr, timeout)
        ssl_socket = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
        ssl_socket.sync = true

        begin
          ssl_socket.connect_nonblock
        rescue IO::WaitReadable
          unless IO.select([ssl_socket], nil, nil, timeout)
            raise Timeout, "Could not read from #{host}:#{port} in #{timeout} seconds"
          end

          retry
        rescue IO::WaitWritable
          unless IO.select(nil, [ssl_socket], nil, timeout)
            raise Timeout, "Could not write to #{host}:#{port} in #{timeout} seconds"
          end

          retry
        end
        ssl_socket
      end
    end
  end
end
