module Riemann
  class Attribute
    include Beefcake::Message

    required :key, :string, 1
    optional :value, :string, 2
  end
end
