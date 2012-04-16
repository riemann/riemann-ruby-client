module Riemann
  class Client
    class TCP < Client
      attr_accessor :host, :port, :socket

      def initialize(opts = {})
        @host = opts[:host] || HOST
        @port = opts[:port] || PORT
        @locket = Mutex.new
      end

      def connect
        @socket = TCPSocket.new(@host, @port)
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
        if buffer = s.read(4) and buffer.size == 4
          length = buffer.unpack('N').first
          begin
            str = s.read length
            message = Riemann::Message.decode str
          rescue => e
            puts "Message was #{str.inspect}"
            raise
          end
          
          unless message.ok
            puts "Failed"
            raise ServerError, message.error
          end
          
          message
        else
          raise InvalidResponse, "unexpected EOF"
        end
      end

      def send_recv(message)
        with_connection do |s|
          s << message.encode_with_length
          read_message s
        end
      end

      alias send_maybe_recv send_recv

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
