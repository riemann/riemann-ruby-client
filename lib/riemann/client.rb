require 'riemann'

class Riemann::Client
  class Error < RuntimeError; end
  class InvalidResponse < Error; end
  class ServerError < Error; end
  class Unsupported < Error; end
  class TooBig < Unsupported; end

  require 'thread'
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
  def <<(event_opts)
    # Create state
    case event_opts
    when Riemann::State
      event = event_opts
    when Riemann::Event
      event = event_opts
    else
      unless event_opts.include? :host
        event_opts[:host] = Socket.gethostname
      end
      event = Riemann::Event.new(event_opts)
    end

    message = Riemann::Message.new :events => [event]

    # Transmit
    send_maybe_recv message
  end

  # Returns an array of states matching query.
  def [](query)
    response = query(query)
    (response.events || []) |
      (response.states || [])
  end

  def connect
    # NOTE: connections are made automatically on send
    puts "Riemann client#connect is deprecated"
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
  def query(string = "true")
    send_recv Riemann::Message.new(:query => Riemann::Query.new(:string => string))
  end

  def send_recv(*a)
    @tcp.send_recv *a
  end

  def send_maybe_recv(*a)
    begin
      @udp.send_maybe_recv *a
    rescue TooBig
      @tcp.send_maybe_recv *a
    end
  end
end
