module Reimann
  class Event
    include Beefcake::Message
    
    optional :time, :int64, 1 
    optional :state, :string,  2
    optional :service, :string, 3
    optional :host, :string, 4
    optional :description, :string, 5
    repeated :tags, :string, 7
    optional :ttl, :float, 8
    optional :metric_f, :float, 15

    def initialize(hash)
      if hash[:metric]
        super hash.merge(metric_f: hash[:metric])
      else
        super hash
      end

      @time ||= Time.now.to_i
    end

    def metric
      metric_f
    end

    def metric=(m)
      self.metric_f = m
    end
  end
end
