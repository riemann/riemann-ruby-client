# frozen_string_literal: true

require 'riemann'

module Riemann
  class Client
    class Error < RuntimeError; end
    class InvalidResponse < Error; end
    class ServerError < Error; end
    class Unsupported < Error; end
    class TooBig < Unsupported; end

    require 'socket'
    require 'time'

    HOST = '127.0.0.1'
    PORT = 5555
    TIMEOUT = 5

    require 'riemann/client/tcp'
    require 'riemann/client/udp'

    attr_reader :tcp, :udp

    def initialize(opts = {})
      @options = opts.dup
      @options[:host] ||= HOST
      @options[:port] ||= PORT
      @options[:timeout] ||= TIMEOUT

      @udp = UDP.new(@options)
      @tcp = TCP.new(@options)
      return unless block_given?

      begin
        yield self
      ensure
        close
      end
    end

    def host
      @options[:host]
    end

    def port
      @options[:port]
    end

    def timeout
      @options[:timeout]
    end

    # Send a state
    def <<(event)
      # Create state
      case event
      when Riemann::State, Riemann::Event, Hash
        # Noop
      else
        raise(ArgumentError, "Unsupported event class: #{event.class.name}")
      end

      bulk_send([event])
    end

    def bulk_send(events)
      raise ArgumentError unless events.is_a?(Array)

      message = Riemann::Message.new(events: normalize_events(events))

      send_maybe_recv(message)
    end

    def normalize_events(events)
      events.map do |event|
        case event
        when Riemann::State, Riemann::Event
          event
        when Hash
          e = if event.include?(:host)
                event
              else
                event.dup.merge(host: Socket.gethostname)
              end
          Riemann::Event.new(e)
        else
          raise(ArgumentError, "Unsupported event class: #{event.class.name}")
        end
      end
    end

    # Returns an array of states matching query.
    def [](query)
      response = query(query)
      (response.events || []) |
        (response.states || [])
    end

    def connect
      # NOTE: connections are made automatically on send
      warn 'Riemann client#connect is deprecated'
    end

    # Close both UDP and TCP sockets.
    def close
      @udp.close
      @tcp.close
    end

    def connected?
      tcp.connected? and udp.connected?
    end

    # Ask for states
    def query(string = 'true')
      send_recv Riemann::Message.new(query: Riemann::Query.new(string: string))
    end

    def send_recv(message)
      @tcp.send_recv(message)
    end

    def send_maybe_recv(message)
      @udp.send_maybe_recv(message)
    rescue TooBig
      @tcp.send_maybe_recv(message)
    end
  end
end
