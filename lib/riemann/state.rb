# frozen_string_literal: true

module Riemann
  class State
    include Beefcake::Message

    optional :time, :int64, 1
    optional :state, :string, 2
    optional :service, :string, 3
    optional :host, :string, 4
    optional :description, :string, 5
    optional :once, :bool, 6
    repeated :tags, :string, 7
    optional :ttl, :float, 8
    optional :metric_f, :float, 15

    def initialize
      super

      @time ||= Time.now.to_i
    end

    def metric
      @metric || metric_f
    end

    attr_writer :metric
  end
end
