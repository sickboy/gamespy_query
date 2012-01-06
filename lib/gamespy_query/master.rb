require_relative 'base'

module GamespyQuery
  class Master < Base
    PARAMS = [:hostname, :gamever, :gametype, :gamemode, :numplayers, :maxplayers, :password, :equalModRequired, :mission, :mapname,
              :mod, :signatures, :verifysignatures, :gamestate, :dedicated, :platform, :sv_battleeye, :language, :difficulty]

    # TODO: Gspy v3 multipacket

    DELIMIT = case RUBY_PLATFORM
      when /-mingw32$/, /-mswin32$/
        "\\"
      else
        "\\\\"
    end
    GEOIP_PATH = case RUBY_PLATFORM
      when /-mingw32$/, /-mswin32$/
        File.join(Rails.root, "config").gsub("/", "\\")
      else
        File.join(Rails.root, "config")
    end

    def initialize(geo = nil, game = "arma2oapc")
      @geo, @game = geo, game
    end

    def process
      @list = Hash.new
      self.to_hash(self.read)
    end

    def read
      geo = @geo ? @geo : "-Q 11 "
      unless File.exists?(File.join(GEOIP_PATH, "GeoIP.dat"))
        puts
        puts "Warning: GeoIP.dat database missing. Can't parse countries. #{GEOIP_PATH}"
        geo = nil
      end
      reply = %x[gslist -p "#{GEOIP_PATH}" -n #{@game} #{geo}-X #{PARAMS.clone.map{|e| "#{DELIMIT}#{e}"}.join("")}]
      reply.gsub!("\\\\\\", "") if geo
      reply.split("\n")
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
          i % 2 == 0 ? e : clean(e)
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
