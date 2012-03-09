require_relative "gamespy_query/version"

# GamespyQuery provides access to GameSpy master server (through gslist utility)
# and to GameSpy enabled game servers directly through UDPSocket.
module GamespyQuery
  autoload :Base, "gamespy_query/base"
  autoload :Funcs, "gamespy_query/base"
  autoload :Tools, "gamespy_query/base"

  autoload :Options, "gamespy_query/options"

  autoload :Parser, "gamespy_query/parser"
  autoload :Socket, "gamespy_query/socket"
  autoload :MultiSocket, "gamespy_query/socket"
  autoload :SocketMaster, "gamespy_query/socket_master"
  autoload :Master, "gamespy_query/master"

  module_function

  # Retrieve full product version string
  def product_version
    "GamespyQuery version #{VERSION}"
  end
end
