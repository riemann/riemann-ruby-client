# frozen_string_literal: true

module Riemann
  $LOAD_PATH.unshift __dir__

  require 'rubygems'
  require 'beefcake'
  require 'timeout'
  require 'riemann/version'
  require 'riemann/state'
  require 'riemann/attribute'
  require 'riemann/event'
  require 'riemann/query'
  require 'riemann/message'
  require 'riemann/client'
end
