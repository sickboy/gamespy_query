require_relative 'base'

module GamespyQuery
  # Provides access to the Gamespy Master browser
  class Master < Base
    PARAMS = [:hostname, :gamever, :gametype, :gamemode, :numplayers, :maxplayers, :password, :equalModRequired, :mission, :mapname,
              :mod, :signatures, :verifysignatures, :gamestate, :dedicated, :platform, :sv_battleeye, :language, :difficulty]

    RX_ADDR_LINE = /^[\s\t]*([\d\.]+)[\s\t:]*(\d+)[\s\t]*(.*)$/

    DELIMIT = case RUBY_PLATFORM
      when /-mingw32$/, /-mswin32$/
        "\\"
      else
        "\\\\"
    end

    # Get geoip_path
    def geoip_path
      return File.join(Dir.pwd, "config") unless defined?(Rails)

      case RUBY_PLATFORM
      when /-mingw32$/, /-mswin32$/
        File.join(Rails.root, "config").gsub("/", "\\")
      else
        File.join(Rails.root, "config")
      end
    end

    # Initializes the instance
    # @param [String] geo Geo string
    # @param [String] game Game string
    def initialize(geo = nil, game = "arma2oapc")
      @geo, @game = geo, game
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
      list = %x[gslist -p "#{geoip_path}"#{" #{geo}-X #{get_params}" if include_data} -n #{@game}] if list.nil?
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
        i = 0
        content.map! do |e|
          i += 1
          i % 2 == 0 ? e : clean_string(e)
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
          e[:gamedata].merge!(Hash[*content])
        else
          e[:gamedata] = Hash[*content]
        end
      end
      list
    end
  end
end

if $0 == __FILE__
  master = GamespyQuery::Master.new
  r = master.read
  puts r
end
