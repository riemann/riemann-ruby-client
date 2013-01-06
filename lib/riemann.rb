module Riemann
  $LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__))

  require 'rubygems'
  require 'beefcake'
  require 'riemann/version'
  require 'riemann/state'
  require 'riemann/attribute'
  require 'riemann/event'
  require 'riemann/query'
  require 'riemann/message'
  require 'riemann/client'
end
