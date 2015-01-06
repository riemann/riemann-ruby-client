module Riemann
  class Client
    class UDP < Client
      MAX_SIZE = 16384

      attr_accessor :host, :port, :max_size

      def initialize(opts = {})
        @host     = opts[:host] || HOST
        @port     = opts[:port] || PORT
        @max_size = opts[:max_size] || MAX_SIZE
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
      def read_message(s)
        raise Unsupported
      end

      def send_recv(*a)
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
