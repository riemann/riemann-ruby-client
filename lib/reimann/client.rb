require 'reimann'

class Reimann::Client
  class Error < RuntimeError; end
  class InvalidResponse < Error; end
  class ServerError < Error; end
  
  require 'thread'
  require 'socket'
  require 'time'

  HOST = '127.0.0.1'
  PORT = 5555

  TYPE_STATE = 1

  attr_accessor :host, :port, :socket

  def initialize(opts = {})
    @host = opts[:host] || HOST
    @port = opts[:port] || PORT
    @locket = Mutex.new
  end

  # Send a state
  def <<(event_opts)
    # Create state
    case event_opts
    when Reimann::State
      event = event_opts
    else
      unless event_opts.include? :host
        event_opts[:host] = Socket.gethostname
      end
      event = Reimann::Event.new(event_opts)
    end

    message = Reimann::Message.new :events => [event]

    # Transmit
    with_connection do |s|
      s << message.encode_with_length
      read_message s
    end
  end

  # Returns an array of states matching query.
  def [](query)
    response = query(query)
    (response.events || []) |
      (response.states || [])
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

  # Ask for states
  def query(string = nil)
    message = Reimann::Message.new query: Reimann::Query.new(string: string)
    with_connection do |s|
      s << message.encode_with_length
      read_message s
    end
  end

  # Read a message from a stream
  def read_message(s)
    if buffer = s.read(4) and buffer.size == 4
      length = buffer.unpack('N').first
      begin
        str = s.read length
        message = Reimann::Message.decode str
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

  # Yields a connection in the block.
  def with_connection
    tries = 0
    
    @locket.synchronize do
      begin
        tries += 1
          yield (@socket || connect)
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
