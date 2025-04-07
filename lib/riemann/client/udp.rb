# frozen_string_literal: true

module Riemann
  class Client
    class UDP < Client
      DEFAULT_MAX_SIZE = 16_384

      attr_accessor :host, :port, :max_size

      def initialize(opts = {}) # rubocop:disable Lint/MissingSuper
        @host     = opts[:host] || DEFAULT_HOST
        @port     = opts[:port] || DEFAULT_PORT
        @max_size = opts[:max_size] || DEFAULT_MAX_SIZE
        @socket   = nil
      end

      def socket
        return @socket if connected?

        @socket = UDPSocket.new
      end

      def close
        @socket.close if connected?
        @socket = nil
      end

      def connected?
        @socket && !@socket.closed?
      end

      # Read a message from a stream
      def read_message(_socket)
        raise Unsupported
      end

      def send_recv(_message)
        raise Unsupported
      end

      def send_maybe_recv(message)
        encoded_string = message.encode.to_s
        raise TooBig unless encoded_string.length < @max_size

        socket.send(encoded_string, 0, @host, @port)
        nil
      end
    end
  end
end
