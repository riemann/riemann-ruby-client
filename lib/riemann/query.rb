# frozen_string_literal: true

module Riemann
  class Query
    include Beefcake::Message

    optional :string, :string, 1
  end
end
