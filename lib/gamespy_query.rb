require_relative "gamespy_query/version"
require_relative "gamespy_query/base"
require_relative "gamespy_query/socket"
require_relative "gamespy_query/socket_master"
require_relative "gamespy_query/master"

module GamespyQuery
  # Your code goes here...
end


if $0 == __FILE__
  host = ARGV[0]
  port = ARGV[1]
  g = GamespyQuery::Socket.new(host, port)
  r = g.sync
  exit unless r
  puts r.to_yaml
end
