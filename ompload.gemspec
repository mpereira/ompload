require File.expand_path('../lib/ompload', __FILE__)

Gem::Specification.new do |s|
  s.name     = 'ompload'
  s.version  = Ompload::VERSION
  s.platform = Gem::Platform::RUBY
  s.author   = 'Murilo Pereira'
  s.email    = 'murilo@murilopereira.com'
  s.homepage = 'https://github.com/murilasso/ompload'
  s.summary  = 'Upload files to omploader.'

  s.required_rubygems_version = '>= 1.3.6'

  s.files        = `git ls-files`.split("\n")
  s.require_path = '.'
  s.executable   = 'ompload'
end
