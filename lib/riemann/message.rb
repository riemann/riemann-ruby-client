# frozen_string_literal: true

module Riemann
  class Message
    include Beefcake::Message

    optional :ok, :bool, 2
    optional :error, :string, 3
    repeated :states, State, 4
    optional :query, Query, 5
    repeated :events, Event, 6

    def encode_with_length
      encoded_string = encode.to_s
      [encoded_string.length].pack('N') << encoded_string
    end
  end
end
