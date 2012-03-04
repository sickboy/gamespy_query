require_relative "gamespy_query/version"

require_relative "gamespy_query/base"
require_relative "gamespy_query/socket"
require_relative "gamespy_query/socket_master"
require_relative "gamespy_query/master"

# GamespyQuery provides access to GameSpy master server (through gslist utility)
# and to GameSpy enabled game servers directly through UDPSocket.
module GamespyQuery

end


if $0 == __FILE__
  host, port = if ARGV.size > 1
                 ARGV
               else
                 ARGV[0].split(":")
               end
  time_start = Time.now
  g = GamespyQuery::Socket.new("#{host}:#{port}")
  r = g.sync
  time_taken = Time.now - time_start
  puts "Took: #{time_taken}s"
  exit unless r
  puts r.to_yaml
end
