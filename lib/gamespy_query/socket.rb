# encoding: utf-8
# GameSpy query class by Sickboy [Patrick Roza] (sb_at_dev-heaven.net)



require 'yaml'
require_relative 'base'
require_relative 'parser'

module GamespyQuery
  class Socket < Base
    TIMEOUT = 3
    MAX_PACKETS = 7

    ID_PACKET = [0x04, 0x05, 0x06, 0x07].pack("c*") # TODO: Randomize
    BASE_PACKET = [0xFE, 0xFD, 0x00].pack("c*")
    CHALLENGE_PACKET = [0xFE, 0xFD, 0x09].pack("c*")

    FULL_INFO_PACKET_MP = [0xFF, 0xFF, 0xFF, 0x01].pack("c*")
    FULL_INFO_PACKET = [0xFF, 0xFF, 0xFF].pack("c*")
    SERVER_INFO_PACKET = [0xFF, 0x00, 0x00].pack("c*")
    PLAYER_INFO_PACKET = [0x00, 0xFF, 0x00].pack("c*")

    STR_HOSTNAME = "hostname"
    STR_PLAYERS = "players"
    STR_DEATHS = "deaths_\x00\x00"
    STR_PLAYER = "player_\x00\x00"
    STR_TEAM = "team_\x00\x00"
    STR_SCORE = "score_\x00\x00"

    SPLIT = STR_X0
    STR_END = "\x00\x02"
    STR_EMPTY = Tools::STR_EMPTY
    STR_BLA = "%c%c%c%c".encode("ASCII-8BIT")
    STR_GARBAGE = "\x00\x04\x05\x06\a"

    RX_PLAYER_EMPTY = /^player_\x00\x00\x00/
    RX_PLAYER_INFO = /\x01(team|player|score|deaths)_.(.)/ # \x00 from previous packet, \x01 from continueing player info, (.) - should it overwrite previous value?

    RX_NO_CHALLENGE = /0@0$/
    RX_CHALLENGE = /0@/
    RX_CHALLENGE2 = /[^0-9\-]/si
    RX_SPLITNUM = /^splitnum\x00(.)/i

    def create_socket(*params)
      puts "Creating socket #{params}"
      _create_socket(*params)
    end

    def socket_send(*params)
      puts "Sending socket #{params}"
      _socket_send(*params)
    end

    def socket_receive(*params)
      puts "Receiving socket #{params}"
      _socket_receive(*params)
    end

    def socket_close(*params)
      puts "Closing socket #{params}"
      _socket_close(*params)
    end

    def get_string(*params)
      puts "Getting string #{params}"
      _get_string(*params)
    end

    if RUBY_PLATFORM =~ /mswin32/
      include System::Net
      include System::Net::Sockets

      def get_string(str)
        str.map {|e| e.chr}.join  #  begin; System::Text::Encoding.USASCII.GetString(reply[0]).to_s; rescue nil, Exception => e; Tools.log_exception(e); reply[0].map {|e| e.chr}.join; end
      end

      def _create_socket(host, port)
        @ip_end_point = IPEndPoint.new(IPAddress.Any, 0)
        @s = UdpClient.new
        @s.client.receive_timeout = TIMEOUT * 1000
        @s.connect(host, port.to_i)
      end

      def _socket_send(packet)
        @s.Send(packet, packet.length)
      end

      def _socket_receive
        @s.Receive(@ip_end_point)
      end

      def _socket_close
        @s.close
      end
    else
      require 'socket'
      require 'timeout'

      def get_string(str)
        str
      end

      def _create_socket(host, port)
        @s = UDPSocket.new
        @s.connect(host, port)
      end

      def _socket_send(packet)
        @s.puts(packet)
      end

      def _socket_receive
        begin
          Timeout::timeout(TIMEOUT) do
            @s.recvfrom(4096)
          end
        rescue Timeout::Error
          #socket_close
          raise TimeoutError
        end
      end

      def _socket_close
        @s.close
      end
    end

    attr_accessor :silent
    def initialize(host, port, silent = nil)
      @host, @port, @silent = host, port, silent
    end

    # Supports challenge/response and multi-packet
    def sync
      game_data, key, reply = {}, nil, self.fetch
      return game_data if reply.nil?

      parser = Parser.new(reply)
      data = parser.parse

      game_data.merge!(data[:game])
      game_data["players"] = Parser.pretty_player_data2(data[:players]).sort {|a, b| a[:name].downcase <=> b[:name].downcase }
      
      game_data["ping"] = @ping unless @ping.nil?

      game_data
    end

    def fetch
      data = {}
      status, reply = nil, nil

      # Prepare socket / endpoint and connect
      create_socket(@host, @port)

      # Prepare and send challenge request
      # TODO: Randomize
      id_packet = ID_PACKET
      packet = CHALLENGE_PACKET + id_packet
      Tools.debug{"Sending Challenge (#{packet.length}): #{packet.inspect}"}
      sent = Time.now

      socket_send(packet)

      pings = []

      challenge, received = nil, nil
      begin
        # By default, Blocks until a message returns on this socket from a remote host.
        reply = socket_receive
        received = Time.now
        # TODO: Improve ping test?
        ping = received - sent
        pings << ping
        Tools.debug {"PingTest: #{ping}"}
        challenge = reply[0]
      rescue nil, Exception => e  # Cannot use ensure as we want to keep the socket open :P
        socket_close
        raise e
      end
      return nil if challenge.nil? || challenge.empty?

      # Prepare challenge response, if needed
      str = get_string(challenge)
      Tools.debug{"Received challenge response (#{str.length}): #{str.inspect}"}
      need_challenge = !(str.sub(STR_X0, STR_EMPTY) =~ RX_NO_CHALLENGE)

      if need_challenge
        Tools.debug {"Needs challenge!"}
        str = str.sub(RX_CHALLENGE, STR_EMPTY).gsub(RX_CHALLENGE2, STR_EMPTY).to_i
        challenge_packet = sprintf(STR_BLA, handle_chr(str >> 24), handle_chr(str >> 16), handle_chr(str >> 8), handle_chr(str >> 0))
      end

      # Prepare and send info request packet
      packet = need_challenge ? BASE_PACKET + id_packet + challenge_packet + FULL_INFO_PACKET_MP : BASE_PACKET + id_packet + FULL_INFO_PACKET_MP
      Tools.debug{"Sending:\n#{packet.inspect}"}
      sent = Time.now
      socket_send(packet)

      # Receive response to info request packet, up to 7 packets of information, each limited to 1400 bytes
      max_packets = MAX_PACKETS # Default max
      begin
        # In case some server info didn't fit in a single packet, there will be no proper END OF DATA signal
        # So we manually quit after reaching MAX_PACKETS.
        until data.size >= max_packets
          reply = socket_receive

          if data.empty?
            received = Time.now
            ping = received - sent
            pings << ping
            Tools.debug {"PingTest: #{ping}"}
          end
          index = 0

          game_data = get_string(reply[0])
          Tools.debug {"Received (#{data.size + 1}):\n\n#{game_data.inspect}\n\n#{game_data}\n\n"}

          if game_data.sub(STR_GARBAGE, STR_EMPTY)[RX_SPLITNUM]
            splitnum = $1
            flag = splitnum.unpack("C")[0]
            index = (flag & 127).to_i
            last = flag & 0x80 > 0
            # Data could be received out of order, use the "index" id when "last" flag is true, to determine total packet_count
            max_packets = index + 1 if last # update the max
            Tools.debug {"Splitnum: #{splitnum.inspect} (#{splitnum}) (#{flag}, #{index}, #{last}) Max: #{max_packets}"}
          else
            max_packets = 1
          end
          data[index] = game_data #.sub(RX_X0_S, STR_EMPTY) # Cut off first \x00 from package
        end
      ensure
        socket_close
      end

      pings.map!{|ping| (ping * 1000).round}
      pings_c = 0
      pings.each { |ping| pings_c += ping }

      ping = pings_c / pings.size
      Tools.debug{"Gamespy pings: #{pings}, #{ping}"}

      return nil if data.keys.empty?
      @ping = ping
      data.each_pair {|k, d| Tools.debug {"GSPY Infos: #{k} #{d.size}"} } unless @silent || !$debug

      data
    end

    def handle_chr(number)
      number = ((number % 256)+256) if number < 0
      number = number % 256 if number > 255
      number
    end
  end
end

if $0 == __FILE__
  host = ARGV[0]
  port = ARGV[1]
  g = GamespyQuery::Socket.new(host, port)
  r = g.sync
  exit unless r
  puts r.to_yaml
end
