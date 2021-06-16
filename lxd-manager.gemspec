Gem::Specification.new do |s|
  s.name        = 'lxd-manager'
  s.version     = '0.1.2'
  s.summary     = 'LXD manager'
  s.description = 'Provides simple communication with local LXD server'
  s.authors     = ['Sergey Zhumatiyt']
  s.email       = 'serg@parallel.ru'
  s.files       = Dir.glob 'lib/**/*.rb'
  s.homepage    = 'https://rubygems.org/gems/lxd-manager'
  s.license     = 'MIT'

  s.add_dependency('json')
  s.add_dependency('socket')

  s.add_development_dependency('yard')
end
