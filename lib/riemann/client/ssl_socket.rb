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
      end

      def ssl_context
        @ssl_context ||= OpenSSL::SSL::SSLContext.new.tap do |ctx|
            ctx.key = OpenSSL::PKey::RSA.new(open(@key_file) {|f| f.read})
            ctx.cert = OpenSSL::X509::Certificate.new(open(@cert_file) {|f| f.read})
            ctx.ca_file = @ca_file if @ca_file
            ctx.ssl_version = :TLSv1_2
        end
      end

      # Internal: Connect to the give address within the timeout.
      #
      # Make an attempt to connect to a single address within the given timeout.
      #
      # Return the ::Socket when it is connected, or raise an Error if no
      # connection was possible.
      def connect_nonblock( addr, timeout )
        sock = super(addr, timeout)
        ssl_socket = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
        ssl_socket.sync = true

        begin
          ssl_socket.connect_nonblock
        rescue IO::WaitReadable
          if IO.select([ssl_socket], nil, nil, timeout)
            retry
          else
            raise Timeout, "Could not read from #{host}:#{port} in #{timeout} seconds"
          end
        rescue IO::WaitWritable
          if IO.select(nil, [ssl_socket], nil, timeout)
            retry
          else
            raise Timeout, "Could not write to #{host}:#{port} in #{timeout} seconds"
          end
        end
        ssl_socket
      end
    end
  end
end
