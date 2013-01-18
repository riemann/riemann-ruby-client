module Riemann
  class Attribute
    include Beefcake::Message
  
	required :string, :name, 1
  	optional :string, :value, 2
  end 
end