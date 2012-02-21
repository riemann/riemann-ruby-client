require 'reimann'

class Reimann::Client
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

  require 'reimann/client/tcp'
  require 'reimann/client/udp'

  attr_accessor :host, :port, :tcp, :udp

  def initialize(opts = {})
    @host = opts[:host] || HOST
    @port = opts[:port] || PORT
    @udp = UDP.new opts
    @tcp = TCP.new opts
  end

  # Send a state
  def <<(event_opts)
    # Create state
    case event_opts
    when Reimann::State
      event = event_opts
    when Reimann::Event
      event = event_opts
    else
      unless event_opts.include? :host
        event_opts[:host] = Socket.gethostname
      end
      event = Reimann::Event.new(event_opts)
    end

    message = Reimann::Message.new :events => [event]

    # Transmit
    send_maybe_recv message
  end

  # Returns an array of states matching query.
  def [](query)
    response = query(query)
    (response.events || []) |
      (response.states || [])
  end

  # Close both UDP and TCP sockets.
  def close
    @udp.close
    @tcp.close
  end

  # Connect both UDP and TCP sockets.
  def connect
    udp.connect
    tcp.connect
  end

  def connected?
    tcp.connected? and udp.connected?
  end

  # Ask for states
  def query(string = "true")
    send_recv Reimann::Message.new(query: Reimann::Query.new(string: string))
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
