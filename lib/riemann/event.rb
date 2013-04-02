module Riemann
  class Event
    require 'set'
    include Beefcake::Message

    optional :time, :int64, 1
    optional :state, :string,  2
    optional :service, :string, 3
    optional :host, :string, 4
    optional :description, :string, 5
    repeated :tags, :string, 7
    optional :ttl, :float, 8
    repeated :attributes, Attribute, 9

    optional :metric_sint64, :sint64, 13
    optional :metric_d, :double, 14
    optional :metric_f, :float, 15

    # Fields which don't really exist in protobufs, but which are reserved
    # and can't be used as attributes.
    VIRTUAL_FIELDS = Set.new([:metric])
    # Fields which are specially encoded in the Event protobuf--that is, they
    # can't be used as attributes.
    RESERVED_FIELDS = fields.map do |i, field|
      field.name.to_sym
    end.reduce(VIRTUAL_FIELDS) do |set, field|
      set << field
    end

    # Average a set of states together. Chooses the mean metric, the mode
    # state, mode service, and the mean time. If init is provided, its values
    # override (where present) the computed ones.
    def self.average(states, init = Event.new)
      init = case init
             when Event
               init.dup
             else
               Event.new init
             end

      # Metric
      init.metric_f ||= states.inject(0.0) { |a, state|
          a + (state.metric || 0)
        } / states.size
      if init.metric_f.nan?
        init.metric_f = 0.0
      end

      # Event
      init.state ||= mode states.map(&:state)
      init.service ||= mode states.map(&:service)

      # Time
      init.time = begin
        times = states.map(&:time).compact
        (times.inject(:+) / times.size).to_i
      rescue
      end
      init.time ||= Time.now.to_i

      init
    end

    # Sum a set of states together. Adds metrics, takes the mode state, mode
    # service and the mean time. If init is provided, its values override
    # (where present) the computed ones.
    def self.sum(states, init = Event.new)
      init = case init
             when Event
               init.dup
             else
               Event.new init
             end

      # Metric
      init.metric_f ||= states.inject(0.0) { |a, state|
          a + (state.metric || 0)
        }
      if init.metric_f.nan?
        init.metric_f = 0.0
      end

      # Event
      init.state ||= mode states.map(&:state)
      init.service ||= mode states.map(&:service)

      # Time
      init.time = begin
        times = states.map(&:time).compact
        (times.inject(:+) / times.size).to_i
      rescue
      end
      init.time ||= Time.now.to_i

      init
    end

    # Finds the maximum of a set of states. Metric is the maximum. Event is the
    # highest, as defined by Dash.config.state_order. Time is the mean.
    def self.max(states, init = Event.new)
      init = case init
             when Event
               init.dup
             else
               Event.new init
             end

      # Metric
      init.metric_f ||= states.inject(0.0) { |a, state|
          a + (state.metric || 0)
        }
      if init.metric.nan?
        init.metric = 0.0
      end

      # Event
      init.state ||= states.inject(nil) do |max, state|
        state.state if Dash.config[:state_order][state.state] > Dash.config[:state_order][max]
      end

      # Time
      init.time = begin
        times = states.map(&:time).compact
        (times.inject(:+) / times.size).to_i
      rescue
      end
      init.time ||= Time.now.to_i

      init
    end

    def self.mode(array)
      array.inject(Hash.new(0)) do |counts, e|
        counts[e] += 1
        counts
      end.sort_by { |e, count| count }.last.first rescue nil
    end

    # Partition a list of states by a field
    # Returns a hash of field_value => state
    def self.partition(states, field)
      states.inject({}) do |p, state|
        k = state.send field
        if p.include? k
          p[k] << state
        else
          p[k] = [state]
        end
        p
      end
    end

    # Sorts states by a field. nil values first.
    def self.sort(states, field)
      states.sort do |a, b|
        a = a.send field
        b = b.send field
        if a.nil?
          -1
        elsif b.nil?
          1
        else
          a <=> b
        end
      end
    end

    def initialize(hash = nil)
      if hash
        if hash[:metric]
          super hash
          self.metric = hash[:metric]
        else
          super hash
        end

        # Add extra attributes to the event as Attribute instances with values
        # converted to String
        self.attributes = hash.map do |key, value|
          unless RESERVED_FIELDS.include? key.to_sym
            Attribute.new(:key => key.to_s,
                          :value => (hash[key] || hash[key.to_sym]).to_s)
          end
        end.compact
      else
        super()
      end

      @time ||= Time.now.to_i
    end

    def metric
      metric_d ||
        metric_sint64 ||
        metric_f
    end

    def metric=(m)
      if Integer === m and (-(2**63)...2**63) === m
        # Long
        self.metric_sint64 = m
        self.metric_f = m.to_f
      else
        self.metric_d = m.to_f
        self.metric_f = m.to_f
      end
    end

    # Look up attributes
    def [](k)
      if RESERVED_FIELDS.include? k.to_sym
        super
      else
        r = attributes.find {|a| a.key.to_s == k.to_s }.value
      end
    end

    # Set attributes
    def []=(k, v)
      if RESERVED_FIELDS.include? k.to_sym
        super
      else
        a = self.attributes.find {|a| a.key == k.to_s }
        if(a)
          a.value = v.to_s
        else
          self.attributes << Attribute.new(:key => k.to_s, :value => v.to_s)
        end
      end
    end
  end
end
