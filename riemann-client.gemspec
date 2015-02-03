# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'riemann/version'

Gem::Specification.new do |spec|
  spec.name          = 'riemann-client'
  spec.version       = Riemann::VERSION
  spec.author        = 'Kyle Kingsbury'
  spec.email         = 'aphyr@aphyr.com'
  spec.summary       = 'Client for the distributed event system Riemann.'
  spec.description   = 'Client for the distributed event system Riemann.'
  spec.homepage      = 'https://github.com/aphyr/riemann-ruby-client'
  spec.license       = 'MIT'
  spec.platform      = Gem::Platform::RUBY

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']
  spec.has_rdoc      = true

  spec.required_ruby_version = '>= 1.8.7'

  spec.add_development_dependency 'bundler', '>= 1.3'
  spec.add_development_dependency 'bacon'

  spec.add_dependency 'beefcake', ['>= 0.3.5','<= 1.0.0 ']
  spec.add_dependency 'trollop', '>= 1.16.2'
  spec.add_dependency 'mtrc', '>= 0.0.4'
end
