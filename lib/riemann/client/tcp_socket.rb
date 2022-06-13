require 'socket'
require 'fcntl'

module Riemann
  class Client
  # Socket: A specialized socket that has been configure
    class TcpSocket
      class Error < Riemann::Client::Error; end
      class Timeout < Error; end

      # Internal:
      # The timeout for reading in seconds. Defaults to 2
      attr_accessor :read_timeout

      # Internal:
      # The timeout for connecting in seconds. Defaults to 2
      attr_reader :connect_timeout

      # Internal:
      # The timeout for writing in seconds. Defaults to 2
      attr_reader :write_timeout

      # Internal:
      # The host this socket is connected to
      attr_reader :host

      # Internal:
      # The port this socket is connected to
      attr_reader :port

      # Internal
      #
      # Used for setting TCP_KEEPIDLE: overrides tcp_keepalive_time for a single
      # socket.
      #
      # http://tldp.org/HOWTO/TCP-Keepalive-HOWTO/usingkeepalive.html
      #
      # tcp_keepalive_time:
      #
      #  The interval between the last data packet sent (simple ACKs are not
      #  considered data) and the first keepalive probe; after the connection is
      #  marked to need keepalive, this counter is not used any further.
      attr_reader :keepalive_idle

      # Internal
      #
      # Used for setting TCP_KEEPINTVL: overrides tcp_keepalive_intvl for a single
      # socket.
      #
      # http://tldp.org/HOWTO/TCP-Keepalive-HOWTO/usingkeepalive.html
      #
      # tcp_keepalive_intvl:
      #
      #   The interval between subsequential keepalive probes, regardless of what
      #   the connection has exchanged in the meantime.
      attr_reader :keepalive_interval

      # Internal
      #
      # Used for setting TCP_KEEPCNT: overrides tcp_keepalive_probes for a single
      # socket.
      #
      # http://tldp.org/HOWTO/TCP-Keepalive-HOWTO/usingkeepalive.html
      #
      # tcp_keepalive_probes:
      #
      #   The number of unacknowledged probes to send before considering the
      #   connection dead and notifying the application layer.
      attr_reader :keepalive_count


      # Internal: Create and connect to the given location.
      #
      # options, same as Constructor
      #
      # Returns an instance of KJess::Socket
      def self.connect(options = {})
        s = new(options)
        s.connect
        return s
      end

      # Internal: Creates a new KJess::Socket
      def initialize( options = {} )
        @host = options[:host]
        @port = options[:port]

        @connect_timeout = options[:connect_timeout] || options[:timeout] || 2
        @read_timeout    = options[:read_timeout]    || options[:timeout] || 2
        @write_timeout   = options[:write_timeout]   || options[:timeout] || 2

        @keepalive_active   = options.fetch(:keepalive_active, true)
        @keepalive_idle     = options[:keepalive_idle]     || 60
        @keepalive_interval = options[:keepalive_interval] || 30
        @keepalive_count    = options[:keepalive_count]    || 5

        @socket             = nil
      end

      # Internal: Return whether or not the keepalive_active flag is set.
      def keepalive_active?
        @keepalive_active
      end

      # Internal: Low level socket allocation and option configuration
      #
      # Using the options from the initializer, a new ::Socket is created that
      # is:
      #
      #   TCP, autoclosing on exit, nagle's algorithm is disabled and has
      #   TCP Keepalive options set if keepalive is supported.
      #
      # Returns a new ::Socket instance for

      def socket_factory(type)
         sock = ::Socket.new(type, ::Socket::SOCK_STREAM, 0)

        # close file descriptors if we exec
        if Fcntl.constants.include?(:F_SETFD) && Fcntl.constants.include?(:FD_CLOEXEC)
          sock.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
        end
        # Disable Nagle's algorithm
        sock.setsockopt(::Socket::IPPROTO_TCP, ::Socket::TCP_NODELAY, 1)

        if using_keepalive? then
          sock.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_KEEPALIVE , true)
          sock.setsockopt(::Socket::SOL_TCP,    ::Socket::TCP_KEEPIDLE , keepalive_idle)
          sock.setsockopt(::Socket::SOL_TCP,    ::Socket::TCP_KEEPINTVL, keepalive_interval)
          sock.setsockopt(::Socket::SOL_TCP,    ::Socket::TCP_KEEPCNT  , keepalive_count)
        end

        return sock
      end

      # Internal: Return the connected raw Socket.
      #
      # If the socket is closed or non-existent it will create and connect again.
      #
      # Returns a ::Socket
      def socket
        return @socket unless closed?
        @socket ||= connect()
      end

      # Internal: Closes the internal ::Socket
      #
      # Returns nothing
      def close
        @socket.close unless closed?
        @socket = nil
      end

      # Internal: Return true the socket is closed.
      def closed?
        return true if @socket.nil?
        return true if @socket.closed?
        return false
      end

      # Internal:
      #
      # Connect to the remote host in a non-blocking fashion.
      #
      # Raise Error if there is a failure connecting.
      #
      # Return the ::Socket on success
      def connect
        # Calculate our timeout deadline
        deadline = Time.now.to_f + connect_timeout

        # Lookup destination address, we only want TCP.
        addrs      = ::Socket.getaddrinfo(host, port, nil, ::Socket::SOCK_STREAM )
        errors     = []
        conn_error = lambda { raise errors.first }
        sock       = nil

        # Sort it so we get AF_INET, IPv4
        addrs.sort.find( conn_error ) do |addr|
          sock = connect_or_error( addr, deadline, errors )
        end
        return sock
      end

      # Internal: Connect to the destination or raise an error.
      #
      # Connect to the address or capture the error of the connection
      #
      # addr     - An address returned from Socket.getaddrinfo()
      # deadline - the after which we should raise a timeout error
      # errors   - a collection of errors to append an error too should we have one.
      #
      # Make an attempt to connect to the given address. If it is successful,
      # return the socket.
      #
      # Should the connection fail, append the exception to the errors array and
      # return false.
      #
      def connect_or_error( addr, deadline, errors )
        timeout = deadline - Time.now.to_f
        raise Timeout, "Could not connect to #{host}:#{port}" if timeout <= 0
        return connect_nonblock( addr, timeout )
      rescue Error => e
        errors << e
        return false
      end

      # Internal: Connect to the give address within the timeout.
      #
      # Make an attempt to connect to a single address within the given timeout.
      #
      # Return the ::Socket when it is connected, or raise an Error if no
      # connection was possible.
      def connect_nonblock( addr, timeout )
        sockaddr = ::Socket.pack_sockaddr_in(addr[1], addr[3])
        sock     = self.socket_factory( addr[4] )
        sock.connect_nonblock( sockaddr )
        return sock
      rescue Errno::EINPROGRESS
        if IO.select(nil, [sock], nil, timeout).nil?
          sock.close rescue nil
          raise Timeout, "Could not connect to #{host}:#{port} within #{timeout} seconds"
        end
        return connect_nonblock_finalize( sock, sockaddr )
      rescue => ex
        sock.close rescue nil
        raise Error, "Could not connect to #{host}:#{port}: #{ex.class}: #{ex.message}", ex.backtrace
      end


      # Internal: Make sure that a non-blocking connect has truely connected.
      #
      # Ensure that the given socket is actually connected to the given adddress.
      #
      # Returning the socket if it is and raising an Error if it isn't.
      def connect_nonblock_finalize( sock, sockaddr )
        sock.connect_nonblock( sockaddr )
        return sock
      rescue Errno::EISCONN
        return sock
      rescue => ex
        sock.close rescue nil
        raise Error, "Could not connect to #{host}:#{port}: #{ex.class}: #{ex.message}", ex.backtrace
      end

      # Internal: say if we are using TCP Keep Alive or not
      #
      # We will return true if the initialization options :keepalive_active is
      # set to true, and if all the constants that are necessary to use TCP keep
      # alive are defined.
      #
      # It may be the case that on some operating systems that the constants are
      # not defined, so in that case we do not want to attempt to use tcp keep
      # alive if we are unable to do so in any case.
      #
      # Returns true or false
      def using_keepalive?
        using = false
        if keepalive_active? then
          using = [ :SOL_SOCKET, :SO_KEEPALIVE, :SOL_TCP, :TCP_KEEPIDLE, :TCP_KEEPINTVL, :TCP_KEEPCNT].all? do |c|
            ::Socket.const_defined? c
          end
        end
        return using
      end

      # Reads length bytes from the socket
      #
      # length - the number of bytes to read from the socket
      # outbuf - an optional buffer to store the bytes in
      #
      # Returns the bytes read if no outbuf is specified
      def read(length, outbuf = nil)
        if outbuf
          outbuf.replace('')
          buf = outbuf
        else
          buf = ''
        end

        while buf.length < length
          unless rb = readpartial(length - buf.length)
            break
          end

          buf << rb
        end

        return buf
      end

      # Internal: Read up to a maxlen of data from the socket and store it in outbuf
      #
      # maxlen - the maximum number of bytes to read from the socket
      # outbuf - the buffer in which to store the bytes.
      #
      # Returns the bytes read
      def readpartial(maxlen, outbuf = nil)
        return socket.read_nonblock(maxlen, outbuf)
      rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::ECONNRESET
        if wait_readable(read_timeout)
          retry
        else
          raise Timeout, "Could not read from #{host}:#{port} in #{read_timeout} seconds"
        end
      end

      # Internal: Write the given data to the socket
      #
      # buf - the data to write to the socket.
      #
      # Raises an error if it is unable to write the data to the socket within the
      # write_timeout.
      #
      # returns nothing
      def write(buf)
        until buf.nil? or (buf.length == 0) do
          written = socket.write_nonblock(buf)
          buf = buf[written, buf.length]
        end
      rescue Errno::EWOULDBLOCK, Errno::EINTR, Errno::EAGAIN, Errno::ECONNRESET
        if wait_writable(write_timeout)
          retry
        else
          raise Timeout, "Could not write to #{host}:#{port} in #{write_timeout} seconds"
        end
      end

      def wait_writable(timeout = nil)
        IO.select(nil, [@socket], nil, timeout || write_timeout)
      end

      def wait_readable(timeout = nil)
        IO.select([@socket], nil, nil, timeout || read_timeout)
      end
    end
  end
end
