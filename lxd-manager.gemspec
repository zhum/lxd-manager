# frozen_string_literal: true
require_relative "lib/lxd/version"

Gem::Specification.new do |s|
  s.name        = 'lxd-manager'
  s.version       = Lxd::Manager::VERSION
  s.summary     = 'LXD manager'
  s.description = 'Provides simple communication with local LXD server'
  s.authors     = ['Sergey Zhumatiyt']
  s.email       = 'serg@parallel.ru'
  s.files       = Dir.glob 'lib/**/*.rb'
  s.homepage    = 'https://rubygems.org/gems/lxd-manager'
  s.license     = 'MIT'

  s.required_ruby_version = ">= 2.4.0"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  s.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  s.bindir        = "exe"
  s.executables   = s.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency('json', '~> 2.1')

  s.add_development_dependency('yard', '~> 0.9')
  s.add_development_dependency('bundler', '~> 2.2')
end

