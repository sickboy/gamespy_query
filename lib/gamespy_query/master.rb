module GamespyQuery
  # Provides access to the Gamespy Master browser
  class Master < Base
    # TODO: gslist.exe output encoding seems to be a problem.
    # not been able to find a solution yet to get unicode instead of garbelled characters
    # If impossible, perhaps should try custom implementation of master query

    PARAMS = [:hostname, :gamever, :gametype, :gamemode, :numplayers, :maxplayers, :password, :equalModRequired, :mission, :mapname,
              :mod, :signatures, :verifysignatures, :gamestate, :dedicated, :platform, :sv_battleye, :language, :difficulty]

    RX_ADDR_LINE = /^[\s\t]*([\d\.]+)[\s\t:]*(\d+)[\s\t]*(.*)$/

    DELIMIT = case RUBY_PLATFORM
      when /-mingw32$/, /-mswin32$/
        "\\"
      else
        "\\\\"
    end

    path = defined?(Rails) ? File.join(Rails.root, "config") : File.join(Dir.pwd, "config")
    DEFAULT_GEOIP_PATH = case RUBY_PLATFORM
                  when /-mingw32$/, /-mswin32$/
                    path.gsub("/", "\\")
                  else
                    path
                end

    # Geo settings
    attr_reader :geo

    # Game
    attr_reader :game

    # Initializes the instance
    # @param [String] geo Geo string
    # @param [String] game Game string
    def initialize(geo = nil, game = "arma2oapc", geoip_path = nil)
      @geo, @game, @geoip_path = geo, game, geoip_path
    end

    # Convert the master browser data to hash
    def process list = self.read
      self.to_hash list
    end

    # Gets list of PARAMS, delimited by {DELIMIT}
    def get_params
      PARAMS.clone.map{|e| "#{DELIMIT}#{e}"}.join("")
    end

    # Gets list of server addressses and optionally data
    # @param [String] list Specify list or nil to fetch the list
    # @param [Boolean] include_data Should server info data from the master browser be included
    # @param [String] geo Geo String
    def get_server_list list = nil, include_data = false, geo = nil
      addrs = []
      list = %x[gslist -C -p "#{geoip_path}"#{" #{geo}-X #{get_params}" if include_data} -n #{@game}] if list.nil?
      if include_data
        addrs = handle_data(list, geo)
      else
        list.split("\n").each do |line|
          addrs << "#{$1}:#{$2}" if line =~ RX_ADDR_LINE
        end
      end
      addrs
    end

    # Read the server list from gamespy
    def read
      geo = @geo ? @geo : "-Q 11 "
      unless geo.nil? || geo.empty? || File.exists?(File.join(geoip_path, "GeoIP.dat"))
        Tools.logger.warn "Warning: GeoIP.dat database missing. Can't parse countries. #{geoip_path}"
        geo = nil
      end
      get_server_list(nil, true, geo)
    end

    # Handle reply data from gamespy master browser
    # @param [String] reply Reply from gamespy
    # @param [String] geo Geo String
    def handle_data(reply, geo = nil)
      reply = encode_string(reply) # Hmm
      reply = reply.gsub("\\\\\\", "") if geo
      reply.split("\n").select{|line| line =~ RX_ADDR_LINE }
    end


    # Address and Data regex
    RX_H = /\A([\.0-9]*):([0-9]*) *\\(.*)/
    # Split string
    STR_SPLIT = "\\"

    # Convert array of data to hash
    # @param [Array] ar Array to convert
    def to_hash(ar)
      list = Hash.new
      ar.each_with_index do |entry, index|
        str = entry[RX_H]
        next unless str
        ip, port, content = $1, $2, $3
        content = content.split(STR_SPLIT)
        content << "" unless (content.size % 2 == 0)
        game_data = {}
        key = nil
        content.each_with_index do |data, i|
          if i % 2 == 0
            key = data.to_sym
          else
            game_data[key] = data
          end
        end
        addr = "#{ip}:#{port}"
        if list.has_key?(addr)
          e = list[addr]
        else
          e = Hash.new
          e[:ip] = ip
          e[:port] = port
          e[:gamename] = @game
          list[addr] = e
        end
        if e[:gamedata]
          e[:gamedata].merge!(game_data)
        else
          e[:gamedata] = game_data
        end
      end
      list
    end


    # Get geoip_path
    def geoip_path
      @geoip_path || DEFAULT_GEOIP_PATH
    end
  end
end
