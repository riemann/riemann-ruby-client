module Riemann
  class Attribute
    include Beefcake::Message
  
	required :string, :key, 1
  	optional :string, :value, 2
  end 
end
