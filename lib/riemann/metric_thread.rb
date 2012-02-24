class Riemann::MetricThread
  # A metric thread is simple: it wraps some metric object which responds to <<,
  # and every interval seconds, calls #flush which replaces the object and calls
  # a user specified function.
 
  INTERVAL = 10
  
  attr_accessor :interval
  attr_accessor :metric

  # client = Riemann::Client.new
  # m = MetricThread.new Mtrc::Rate do |rate|
  #   client << rate
  # end
  #
  # loop do
  #   sleep rand
  #   m << rand
  # end
  def initialize(klass, *klass_args, &f)
    @klass = klass
    @klass_args = klass_args
    @f = f
    @interval = INTERVAL

    @metric = new_metric

    start
  end

  def <<(*a)
    @metric.<<(*a)
  end

  def new_metric
    @klass.new *@klass_args
  end

  def flush
    old, @metric = @metric, new_metric
    @f[old]
  end

  def start
    raise RuntimeError, "already running" if @runner
  
    @running = true
    @runner = Thread.new do
      while @running
        sleep @interval
        begin
          flush
        rescue Exception => e
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
