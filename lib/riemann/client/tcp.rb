# frozen_string_literal: true

require 'monitor'
require 'riemann/client/tcp_socket'
require 'riemann/client/ssl_socket'

module Riemann
  class Client
    class TCP < Client
      attr_accessor :host, :port

      # Public: Set a socket factory -- an object responding
      # to #call(options) that returns a Socket object
      class << self
        attr_writer :socket_factory
      end

      # Public: Return a socket factory
      def self.socket_factory
        @socket_factory ||= proc { |options|
          if options[:ssl]
            SSLSocket.connect(options)
          else
            TcpSocket.connect(options)
          end
        }
      end

      def initialize(options = {}) # rubocop:disable Lint/MissingSuper
        @options = options
        @locket  = Monitor.new
        @socket  = nil
        @pid     = nil
      end

      def socket
        @locket.synchronize do
          close if @pid && @pid != Process.pid

          return @socket if connected?

          @socket = self.class.socket_factory.call(@options)
          @pid    = Process.pid

          return @socket
        end
      end

      def close
        @locket.synchronize do
          @socket.close if connected?
          @socket = nil
        end
      end

      def connected?
        @locket.synchronize do
          !@socket.nil? && !@socket.closed?
        end
      end

      # Read a message from a stream
      def read_message(socket)
        unless (buffer = socket.read(4)) && (buffer.size == 4)
          raise InvalidResponse, 'unexpected EOF'
        end

        length = buffer.unpack1('N')
        begin
          str = socket.read length
          message = Riemann::Message.decode str
        rescue StandardError
          puts "Message was #{str.inspect}"
          raise
        end

        unless message.ok
          puts 'Failed'
          raise ServerError, message.error
        end

        message
      end

      def send_recv(message)
        with_connection do |socket|
          socket.write(message.encode_with_length)
          read_message(socket)
        end
      end

      alias send_maybe_recv send_recv

      # Yields a connection in the block.
      def with_connection
        tries = 0

        @locket.synchronize do
          tries += 1
          yield(socket)
        rescue IOError, Errno::EPIPE, Errno::ECONNREFUSED, InvalidResponse, Timeout::Error,
               Riemann::Client::TcpSocket::Error
          close
          raise if tries > 3

          retry
        rescue StandardError
          close
          raise
        end
      end
    end
  end
end
