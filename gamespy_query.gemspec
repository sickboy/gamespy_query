# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "gamespy_query/version"

Gem::Specification.new do |s|
  s.name        = "gamespy_query"
  s.version     = GamespyQuery::VERSION
  s.authors     = ["Patrick Roza"]
  s.email       = ["sb@dev-heaven.net"]
  s.homepage    = "http://dev-heaven.net"
  s.summary     = %q{Ruby library for accessing Gamespy services}
  s.description = %q{}

  s.rubyforge_project = "gamespy_query"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
  s.add_development_dependency "riot"
  s.add_development_dependency "yard"
end
