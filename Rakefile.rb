$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'rubygems'
require 'rubygems/package_task'
require 'rdoc/task'
require 'riemann/version'
require 'find'
 
# Don't include resource forks in tarballs on Mac OS X.
ENV['COPY_EXTENDED_ATTRIBUTES_DISABLE'] = 'true'
ENV['COPYFILE_DISABLE'] = 'true'
 
# Gemspec
gemspec = Gem::Specification.new do |s|
  s.rubyforge_project = 'riemann-client'
 
  s.name = 'riemann-client'
  s.version = Riemann::VERSION
  s.author = 'Kyle Kingsbury'
  s.email = 'aphyr@aphyr.com'
  s.homepage = 'https://github.com/aphyr/riemann-ruby-client'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Client for the distributed event system Riemann.'

  s.add_dependency 'beefcake', '>= 0.3.5' 
  s.add_dependency 'trollop', '>= 1.16.2'
  s.add_dependency 'mtrc', '>= 0.0.4'
   
  s.files = FileList['{lib}/**/*', 'LICENSE', 'README.markdown'].to_a
  s.executables = []
  s.require_path = 'lib'
  s.has_rdoc = true
 
  s.required_ruby_version = '>= 1.8.7'
end

Gem::PackageTask.new gemspec do |p|
end
 
RDoc::Task.new do |rd|
  rd.main = 'Riemann'
  rd.title = 'Riemann'
  rd.rdoc_dir = 'doc'
 
  rd.rdoc_files.include('lib/**/*.rb')
end
