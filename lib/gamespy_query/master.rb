require_relative 'base'

module GamespyQuery
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

    def geoip_path
      return File.join(Dir.pwd, "config") unless defined?(Rails)

      case RUBY_PLATFORM
      when /-mingw32$/, /-mswin32$/
        File.join(Rails.root, "config").gsub("/", "\\")
      else
        File.join(Rails.root, "config")
      end
    end

    def initialize(geo = nil, game = "arma2oapc")
      @geo, @game = geo, game
    end

    def process
      @list = Hash.new
      self.to_hash(self.read)
    end

    def get_params
      PARAMS.clone.map{|e| "#{DELIMIT}#{e}"}.join("")
    end

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

    def read
      geo = @geo ? @geo : "-Q 11 "
      unless geo.nil? || geo.empty? || File.exists?(File.join(geoip_path, "GeoIP.dat"))
        Tools.logger.warn "Warning: GeoIP.dat database missing. Can't parse countries. #{geoip_path}"
        geo = nil
      end
      get_server_list(nil, true, geo)
    end

    def handle_data(reply, geo = nil)
      reply = reply.gsub("\\\\\\", "") if geo
      reply.split("\n").select{|line| line =~ RX_ADDR_LINE }
    end

    RX_H = /\A([\.0-9]*):([0-9]*) *\\(.*)/
    STR_SPLIT = "\\"
    def to_hash(ar)
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
        if @list.has_key?(addr)
          e = @list[addr]
        else
          e = Hash.new
          e[:ip] = ip
          e[:port] = port
          @list[addr] = e
        end
        if e[:gamedata]
          e[:gamedata].merge!(Hash[*content])
        else
          e[:gamedata] = Hash[*content]
        end
      end
      @list
    end
  end
end

if $0 == __FILE__
  master = GamespyQuery::Master.new
  r = master.read
  puts r
end