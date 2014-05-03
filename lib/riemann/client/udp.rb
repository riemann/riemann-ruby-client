module Riemann
  class Client
    class UDP < Client
      MAX_SIZE = 16384

      attr_accessor :host, :port, :socket, :max_size

      def initialize(opts = {})
        @host = opts[:host] || HOST
        @port = opts[:port] || PORT
        @max_size = opts[:max_size] || MAX_SIZE
      end

      def connect
        @socket = UDPSocket.new
      end

      def close
        @socket.close if connected?
        @socket = nil
      end

      def connected?
        @socket.nil? ? false : true
      end

      # Read a message from a stream
      def read_message(s)
        raise Unsupported
      end

      def send_recv(*a)
        raise Unsupported
      end

      def send_maybe_recv(message)
        with_connection do |s|
          encoded_string = message.encode.to_s
          unless encoded_string.length < @max_size
            raise TooBig
          end

          s.send(encoded_string, 0, @host, @port)
          nil
        end
      end

      # Yields a connection in the block.
      def with_connection
        tries = 0
        begin
          tries += 1
          yield(@socket || connect)
        rescue IOError, Errno::EPIPE, Errno::ECONNREFUSED, Errno::ECONNRESET, InvalidResponse, SocketError
          close # force a reconnect
          raise if tries > 3
          retry
        end
      end
    end
  end
end
