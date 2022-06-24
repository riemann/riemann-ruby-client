# frozen_string_literal: true

module Riemann
  class Event
    require 'set'
    include Beefcake::Message

    optional :time, :int64, 1
    optional :state, :string, 2
    optional :service, :string, 3
    optional :host, :string, 4
    optional :description, :string, 5
    repeated :tags, :string, 7
    optional :ttl, :float, 8
    repeated :attributes, Attribute, 9
    optional :time_micros, :int64, 10

    optional :metric_sint64, :sint64, 13
    optional :metric_d, :double, 14
    optional :metric_f, :float, 15

    # Fields which don't really exist in protobufs, but which are reserved
    # and can't be used as attributes.
    VIRTUAL_FIELDS = Set.new([:metric])
    # Fields which are specially encoded in the Event protobuf--that is, they
    # can't be used as attributes.
    RESERVED_FIELDS = fields.map do |_i, field|
      field.name.to_sym
    end.reduce(VIRTUAL_FIELDS) do |set, field| # rubocop:disable Style/MultilineBlockChain
      set << field
    end

    def self.now
      (Time.now.to_f * 1_000_000).to_i
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
      init.metric_f ||= states.inject(0.0) do |a, state|
        a + (state.metric || 0)
      end / states.size
      init.metric_f = 0.0 if init.metric_f.nan?

      # Event
      init.state ||= mode states.map(&:state)
      init.service ||= mode states.map(&:service)

      # Time
      init.time_micros = begin
        times = states.map(&:time_micros).compact
        (times.inject(:+) / times.size).to_i
      rescue ZeroDivisionError
        nil
      end
      init.time_micros ||= now

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
      init.metric_f ||= states.inject(0.0) do |a, state|
        a + (state.metric || 0)
      end
      init.metric_f = 0.0 if init.metric_f.nan?

      # Event
      init.state ||= mode states.map(&:state)
      init.service ||= mode states.map(&:service)

      # Time
      init.time_micros = begin
        times = states.map(&:time_micros).compact
        (times.inject(:+) / times.size).to_i
      rescue ZeroDivisionError
        nil
      end
      init.time_micros ||= now

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
      init.metric_f ||= states.inject(0.0) do |a, state|
        a + (state.metric || 0)
      end
      init.metric = 0.0 if init.metric.nan?

      # Event
      init.state ||= states.inject(nil) do |max, state|
        state.state if Dash.config[:state_order][state.state] > Dash.config[:state_order][max]
      end

      # Time
      init.time_micros = begin
        times = states.map(&:time_micros).compact
        (times.inject(:+) / times.size).to_i
      rescue ZeroDivisionError
        nil
      end
      init.time_micros ||= now

      init
    end

    def self.mode(array)
      array.each_with_object(Hash.new(0)) do |e, counts|
        counts[e] += 1
      end.max_by { |_e, count| count }.first # rubocop:disable Style/MultilineBlockChain
    rescue StandardError
      nil
    end

    # Partition a list of states by a field
    # Returns a hash of field_value => state
    def self.partition(states, field)
      states.each_with_object({}) do |state, p|
        k = state.send field
        if p.include? k
          p[k] << state
        else
          p[k] = [state]
        end
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
        super hash
        self.metric = hash[:metric] if hash[:metric]

        # Add extra attributes to the event as Attribute instances with values
        # converted to String
        self.attributes = hash.map do |key, _value|
          unless RESERVED_FIELDS.include? key.to_sym
            Attribute.new(key: key.to_s,
                          value: (hash[key] || hash[key.to_sym]).to_s)
          end
        end.compact
      else
        super()
      end

      @time_micros ||= self.class.now unless @time
    end

    def metric
      metric_d ||
        metric_sint64 ||
        metric_f
    end

    def metric=(value)
      if value.is_a?(Integer) && (-(2**63)...2**63).include?(value)
        # Long
        self.metric_sint64 = value
      else
        self.metric_d = value.to_f
      end
      self.metric_f = value.to_f
    end

    # Look up attributes
    def [](key)
      if RESERVED_FIELDS.include? key.to_sym
        super
      else
        attributes.find { |a| a.key.to_s == key.to_s }.value
      end
    end

    # Set attributes
    def []=(key, value)
      if RESERVED_FIELDS.include? key.to_sym
        super
      else
        attr = attributes.find { |a| a.key == key.to_s }
        if attr
          attr.value = value.to_s
        else
          attributes << Attribute.new(key: key.to_s, value: value.to_s)
        end
      end
    end
  end
end
