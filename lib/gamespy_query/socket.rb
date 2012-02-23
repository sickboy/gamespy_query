# encoding: utf-8
# GameSpy query class by Sickboy [Patrick Roza] (sb_at_dev-heaven.net)



require 'yaml'
require_relative 'base'
require_relative 'parser'
require 'socket'

module GamespyQuery
  module MultiSocket
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

    if RUBY_PLATFORM =~ /mswin32/
      include System::Net
      include System::Net::Sockets

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
            @s.recvfrom(RECEIVE_SIZE)
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
  end

  class Socket < UDPSocket
    TIMEOUT = 3
    MAX_PACKETS = 7

    ID_PACKET = [0x04, 0x05, 0x06, 0x07].pack("c*") # TODO: Randomize
    BASE_PACKET = [0xFE, 0xFD, 0x00].pack("c*")
    CHALLENGE_PACKET = [0xFE, 0xFD, 0x09].pack("c*")

    FULL_INFO_PACKET_MP = [0xFF, 0xFF, 0xFF, 0x01].pack("c*")
    FULL_INFO_PACKET = [0xFF, 0xFF, 0xFF].pack("c*")
    SERVER_INFO_PACKET = [0xFF, 0x00, 0x00].pack("c*")
    PLAYER_INFO_PACKET = [0x00, 0xFF, 0x00].pack("c*")

    RECEIVE_SIZE = 1500

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

    # TODO: Support pings
    # TODO: Handle .NET native sockets
    include Funcs
    STATE_INIT, STATE_SENT_CHALLENGE, STATE_RECEIVED_CHALLENGE, STATE_SENT_CHALLENGE_RESPONSE, STATE_RECEIVE_DATA, STATE_READY = 0, 1, 2, 3, 4, 5

    attr_accessor :addr, :data, :state, :stamp, :needs_challenge, :max_packets, :failed

    def initialize(addr, address_family = ::Socket::AF_INET)
      @addr, @data, @state, @max_packets = addr, {}, 0, MAX_PACKETS
      @id_packet = ID_PACKET
      @packet = CHALLENGE_PACKET + @id_packet

      super(address_family)
      self.connect(*addr.split(":"))
    end

    def state=(state); @stamp = Time.now; @state = state; end

    def valid?; @state == STATE_READY; end

    def handle_write
      #STDOUT.puts "Write: #{self.inspect}, #{self.state}"

      r = true
      begin
        case self.state
          when STATE_INIT
            STDOUT.puts "Write (0): #{self.inspect}"
            # Send Challenge
            self.puts @packet
            self.state = STATE_SENT_CHALLENGE
          when STATE_RECEIVED_CHALLENGE
            STDOUT.puts "Write (2): #{self.inspect}"
            # Send Challenge response
            self.puts self.needs_challenge ? BASE_PACKET + @id_packet + self.needs_challenge + FULL_INFO_PACKET_MP : BASE_PACKET + @id_packet + FULL_INFO_PACKET_MP
            self.state = STATE_SENT_CHALLENGE_RESPONSE
        end
      rescue => e
        STDOUT.puts "Error: #{e.message}, #{self.inspect}"
        self.failed = true
        r = false
        close
      end

=begin
    if Time.now - self.stamp > @timeout
      STDOUT.puts "TimedOut: #{self.inspect}"
      self.failed = true
      r = false
      close unless closed?
    end
=end
      r
    end

    def handle_read
      #STDOUT.puts "Read: #{self.inspect}, #{self.state}"

      r = true
      case self.state
        when STATE_SENT_CHALLENGE
          begin
            data = self.recvfrom_nonblock(RECEIVE_SIZE)
            STDOUT.puts "Read (1): #{self.inspect}: #{data}"

            handle_challenge get_string(data[0])

            self.state = STATE_RECEIVED_CHALLENGE
          rescue => e
            STDOUT.puts "Error: #{e.message}, #{self.inspect}"
            self.failed = true
            r = false
            close
          end
        when STATE_SENT_CHALLENGE_RESPONSE, STATE_RECEIVE_DATA
          begin
            data = self.recvfrom_nonblock(RECEIVE_SIZE)
            STDOUT.puts "Read (3,4): #{self.inspect}: #{data}"
            self.state = STATE_RECEIVE_DATA

            game_data = get_string(data[0])
            Tools.debug {"Received (#{self.data.size + 1}):\n\n#{game_data.inspect}\n\n#{game_data}\n\n"}

            index = handle_splitnum game_data

            self.data[index] = game_data

            if self.data.size >= self.max_packets # OR we received the end-packet and all packets required
              STDOUT.puts "Received packet limit: #{self.inspect}"
              self.state = STATE_READY
              r = false
              close unless closed?
            end
          rescue => e
            STDOUT.puts "Error: #{e.message}, #{self.inspect}"
            self.failed = true
            r = false
            close
          end
      end
      r
    end

    def handle_exc
      STDOUT.puts "Exception: #{self.inspect}"
      close
      self.failed = true

      false
    end


    def handle_splitnum game_data
      index = 0
      if game_data.sub(STR_GARBAGE, STR_EMPTY)[RX_SPLITNUM]
        splitnum = $1
        flag = splitnum.unpack("C")[0]
        index = (flag & 127).to_i
        last = flag & 0x80 > 0
        # Data could be received out of order, use the "index" id when "last" flag is true, to determine total packet_count
        self.max_packets = index + 1 if last # update the max
        STDOUT.puts "Splitnum: #{splitnum.inspect} (#{splitnum}) (#{flag}, #{index}, #{last}) Max: #{self.max_packets}"
      else
        self.max_packets = 1
      end

      index
    end

    def handle_challenge str
      #STDOUT.puts "Received challenge response (#{str.length}): #{str.inspect}"
      need_challenge = !(str.sub(STR_X0, STR_EMPTY) =~ RX_NO_CHALLENGE)
      if need_challenge
        str = str.sub(RX_CHALLENGE, STR_EMPTY).gsub(RX_CHALLENGE2, STR_EMPTY).to_i
        challenge_packet = sprintf(STR_BLA, handle_chr(str >> 24), handle_chr(str >> 16), handle_chr(str >> 8), handle_chr(str >> 0))
        self.needs_challenge = challenge_packet
      end
    end

    def handle_state; [STATE_INIT, STATE_RECEIVED_CHALLENGE].include? state; end

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
      r = self.data
      begin
        until valid?
          handle_state ? handle_write : handle_read
        end
        data.each_pair {|k, d| Tools.debug {"GSPY Infos: #{k} #{d.size}"} } unless @silent || !$debug

        pings.map!{|ping| (ping * 1000).round}
        pings_c = 0
        pings.each { |ping| pings_c += ping }

        ping = pings_c / pings.size
        Tools.debug{"Gamespy pings: #{pings}, #{ping}"}
        @ping = ping
      rescue => e
        puts "Error during fetch #{self.inspect}: #{e.message}"
        r = nil
      end
      r
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
