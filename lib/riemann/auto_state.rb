module Riemann
  class AutoState
    # Binds together a state hash and a Client. Any change made here
    # sends the state to the client. Useful when updates to a state are made
    # decoherently, e.g. across many methods. Combine with MetricThread (or
    # just Thread.new { loop { autostate.flush; sleep n } }) to ensure regular
    # updates.
    #
    # example:
    #
    # class Job
    #   def initialize
    #     @state = AutoState.new
    #     @state.service = 'job'
    #     @state.state = 'starting up'
    #
    #     run
    #   end
    #
    #   def run
    #     loop do
    #       begin
    #         a
    #         b
    #       rescue Exception => e
    #         @state.once(
    #           state: 'error',
    #           description: e.to_s
    #         )
    #       end
    #     end
    #   end
    #
    #   def a
    #     @state.state = 'heavy lifting a'
    #     ...
    #   end
    #
    #   def b
    #     @state.state = 'heavy lifting b'
    #     ...
    #   end
    
    def initialize(client = Client.new, state = {})
      @client = client
      @state = state
    end

    def description=(description)
      @state[:description] = description
      flush
    end

    def description
      @state[:description]
    end

    # Send state to client
    def flush
      @state[:time] = Time.now.to_i
      @client << @state
    end

    def host=(host)
      @state[:host] = host
      flush
    end

    def host
      @state[:host]
    end

    def metric=(metric)
      @state[:metric] = metric
      flush
    end
    alias metric_f= metric=

    def metric
      @state[:metric]
    end
    alias metric_f metric

    # Performs multiple updates, followed by flush.
    # Example: merge state: critical, metric_f: 10235.3
    def merge(opts)
      @state.merge! opts
      flush
    end
    alias << merge

    # Issues an immediate update of the state with tag "once"
    # set, but does not update the local state. Useful for transient errors.
    # Opts are merged with the state.
    def once(opts)
      o = @state.merge opts
      o[:time] = Time.now.to_i
      o[:tags] = ((o[:tags] | ["once"]) rescue ["once"])
      @client << o
    end

    def state=(state)
      @state[:state] = state
      flush
    end

    def state
      @state[:state]
    end

    def service=(service)
      @state[:service] = service
      flush
    end 

    def service
      @state[:service]
    end
  end
end
