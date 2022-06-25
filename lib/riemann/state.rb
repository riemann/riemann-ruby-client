# frozen_string_literal: true

require 'protobuf'

module Riemann
  class State < Protobuf::Message
    optional :int64, :time, 1
    optional :string, :state, 2
    optional :string, :service, 3
    optional :string, :host, 4
    optional :string, :description, 5
    optional :bool, :once, 6
    repeated :string, :tags, 7
    optional :float, :ttl, 8
    optional :float, :metric_f, 15

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
