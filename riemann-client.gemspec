# frozen_string_literal: true

require_relative 'lib/riemann/version'

Gem::Specification.new do |spec|
  spec.name          = 'riemann-client'
  spec.version       = Riemann::VERSION
  spec.author        = 'Kyle Kingsbury'
  spec.email         = 'aphyr@aphyr.com'
  spec.summary       = 'Client for the distributed event system Riemann.'
  spec.homepage      = 'https://github.com/aphyr/riemann-ruby-client'
  spec.license       = 'MIT'
  spec.platform      = Gem::Platform::RUBY

  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})

  spec.required_ruby_version = '>= 2.6.0'

  spec.add_dependency 'beefcake', '>= 1.0.0 '
  spec.add_dependency 'mtrc', '>= 0.0.4'
end
