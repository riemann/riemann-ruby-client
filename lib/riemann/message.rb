# frozen_string_literal: true

module Riemann
  class Message < Protobuf::Message
    optional :bool, :ok, 2
    optional :string, :error, 3
    repeated State, :states, 4
    optional Query, :query, 5
    repeated Event, :events, 6

    def encode_with_length
      encoded_string = encode.to_s
      [encoded_string.length].pack('N') << encoded_string
    end
  end
end
