module Riemann
  class Client
    class UDP < Client
      MAX_SIZE = 16384

      attr_accessor :host, :port, :socket, :max_size

      def initialize(opts = {})
        @host = opts[:host] || HOST
        @port = opts[:port] || PORT
        @max_size = opts[:max_size] || MAX_SIZE
        @locket = Mutex.new
      end

      def connect
        @socket = UDPSocket.new
      end

      def close
        @locket.synchronize do
          @socket.close
        end
      end

      def connected?
        not @socket.closed?
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
          x = message.encode ''
          unless x.length < @max_size
            raise TooBig
          end

          s.send(x, 0, @host, @port)
          nil
        end
      end

      # Yields a connection in the block.
      def with_connection
        tries = 0
        
        @locket.synchronize do
          begin
            tries += 1
              yield(@socket || connect)
          rescue IOError => e
            raise if tries > 3
            connect and retry
          rescue Errno::EPIPE => e
            raise if tries > 3
            connect and retry
          rescue Errno::ECONNREFUSED => e
            raise if tries > 3
            connect and retry
          rescue Errno::ECONNRESET => e
            raise if tries > 3
            connect and retry
          rescue InvalidResponse => e
            raise if tries > 3
            connect and retry
          end
        end
      end
    end
  end
end
