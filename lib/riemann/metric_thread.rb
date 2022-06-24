# frozen_string_literal: true

module Riemann
  class MetricThread
    # A metric thread is simple: it wraps some metric object which responds to <<,
    # and every interval seconds, calls #flush which replaces the object and calls
    # a user specified function.

    INTERVAL = 10

    attr_accessor :interval, :metric

    # client = Riemann::Client.new
    # m = MetricThread.new Mtrc::Rate do |rate|
    #   client << rate
    # end
    #
    # loop do
    #   sleep rand
    #   m << rand
    # end
    def initialize(klass, *klass_args, &block)
      @klass = klass
      @klass_args = klass_args
      @block = block
      @interval = INTERVAL

      @metric = new_metric

      start
    end

    def <<(value)
      @metric.<<(value)
    end

    def new_metric
      @klass.new(*@klass_args)
    end

    def flush
      old = @metric
      @metric = new_metric
      @block[old]
    end

    def start
      raise 'already running' if @runner

      @running = true
      @runner = Thread.new do
        while @running
          sleep @interval
          begin
            flush
          rescue StandardError
            # ignore
          end
        end
        @runner = nil
      end
    end

    def stop
      stop!
      @runner.join
    end

    def stop!
      @running = false
    end
  end
end
