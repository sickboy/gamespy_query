require_relative "gamespy_query/version"

# GamespyQuery provides access to GameSpy master server (through gslist utility)
# and to GameSpy enabled game servers directly through UDPSocket.
module GamespyQuery
  autoload :Base, "gamespy_query/base"
  autoload :Funcs, "gamespy_query/base"
  autoload :Tools, "gamespy_query/base"

  autoload :Options, "gamespy_query/options"
  autoload :MasterOptions, "gamespy_query/options"

  autoload :Parser, "gamespy_query/parser"
  autoload :Socket, "gamespy_query/socket"
  autoload :MultiSocket, "gamespy_query/socket"
  autoload :SocketMaster, "gamespy_query/socket_master"
  autoload :Master, "gamespy_query/master"
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
