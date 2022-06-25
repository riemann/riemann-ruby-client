# frozen_string_literal: true

module Riemann
  class Attribute < Protobuf::Message
    required :string, :key, 1
    optional :string, :value, 2
  end
end
