# frozen_string_literal: true

module Riemann
  class Query < Protobuf::Message
    optional :string, :string, 1
  end
end
