# encoding: utf-8
# GameSpy query class by Sickboy [Patrick Roza] (sb_at_dev-heaven.net)

require 'yaml'
require_relative 'base'
require_relative 'parser'
require 'socket'

module GamespyQuery
  # TODO
  module MultiSocket
    def create_socket(*params)
      Tools.debug {"Creating socket #{params}"}
      _create_socket(*params)
    end

    def socket_send(*params)
      Tools.debug {"Sending socket #{params}"}
      _socket_send(*params)
    end

    def socket_receive(*params)
      Tools.debug {"Receiving socket #{params}"}
      _socket_receive(*params)
    end

    def socket_close(*params)
      Tools.debug {"Closing socket #{params}"}
      @s.close
    end

    if RUBY_PLATFORM =~ /mswin32/
      include System::Net
      include System::Net::Sockets

      def _create_socket(host, port)
        @ip_end_point = IPEndPoint.new(IPAddress.Any, 0)
        @s = UdpClient.new
        @s.client.receive_timeout = DEFAULT_TIMEOUT * 1000
        @s.connect(host, port.to_i)
      end

      def _socket_send(packet)
        @s.Send(packet, packet.length)
      end

      def _socket_receive
        @s.Receive(@ip_end_point)
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
          Timeout::timeout(DEFAULT_TIMEOUT) do
            @s.recvfrom(RECEIVE_SIZE)
          end
        rescue Timeout::Error
          raise TimeoutError
        ensure
          @s.close
        end
      end
    end
  end

  class Socket < UDPSocket
    include Funcs

    DEFAULT_TIMEOUT = 3
    MAX_PACKETS = 7

    ID_PACKET = [0x04, 0x05, 0x06, 0x07].pack("c*") # TODO: Randomize?
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
      #Tools.debug {"Write: #{self.inspect}, #{self.state}"}

      r = true
      begin
        case self.state
          when STATE_INIT
            Tools.debug {"Write (0): #{self.inspect}"}
            # Send Challenge request
            self.puts @packet
            self.state = STATE_SENT_CHALLENGE
          when STATE_RECEIVED_CHALLENGE
            Tools.debug {"Write (2): #{self.inspect}"}
            # Send Challenge response
            self.puts self.needs_challenge ? BASE_PACKET + @id_packet + self.needs_challenge + FULL_INFO_PACKET_MP : BASE_PACKET + @id_packet + FULL_INFO_PACKET_MP
            self.state = STATE_SENT_CHALLENGE_RESPONSE
        end
      rescue => e
        Tools.log_exception e
        self.failed = true
        r = false
        close unless closed?
      end

=begin
    if Time.now - self.stamp > @timeout
      Tools.debug {"TimedOut: #{self.inspect}"}
      self.failed = true
      r = false
      close unless closed?
    end
=end
      r
    end

    def handle_read
      # Tools.debug {"Read: #{self.inspect}, #{self.state}"}

      r = true
      case self.state
        when STATE_SENT_CHALLENGE
          begin
            data = self.recvfrom_nonblock(RECEIVE_SIZE)
            Tools.debug {"Read (1): #{self.inspect}: #{data}"}

            handle_challenge get_string(data[0])

            self.state = STATE_RECEIVED_CHALLENGE
          rescue => e
            Tools.log_exception e
            self.failed = true
            r = false
            close unless closed?
          end
        when STATE_SENT_CHALLENGE_RESPONSE, STATE_RECEIVE_DATA
          begin
            data = self.recvfrom_nonblock(RECEIVE_SIZE)
            Tools.debug {"Read (3,4): #{self.inspect}: #{data}"}
            self.state = STATE_RECEIVE_DATA

            game_data = get_string(data[0])
            Tools.debug {"Received (#{self.data.size + 1}):\n\n#{game_data.inspect}\n\n#{game_data}\n\n"}

            index = handle_splitnum game_data

            self.data[index] = game_data

            if self.data.size >= self.max_packets # OR we received the end-packet and all packets required
              Tools.debug {"Received packet limit: #{self.inspect}"}
              self.state = STATE_READY
              r = false
              close unless closed?
            end
          rescue => e
            Tools.log_exception(e)
            self.failed = true
            r = false
            close unless closed?
          end
      end
      r
    end

    def handle_exc
      Tools.debug {"Exception: #{self.inspect}"}
      close unless closed?
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
        Tools.debug {"Splitnum: #{splitnum.inspect} (#{splitnum}) (#{flag}, #{index}, #{last}) Max: #{self.max_packets}"}
      else
        self.max_packets = 1
      end

      index
    end

    def handle_challenge str
      # Tools.debug{"Received challenge response (#{str.length}): #{str.inspect}"}
      need_challenge = !(str.sub(STR_X0, STR_EMPTY) =~ RX_NO_CHALLENGE)
      if need_challenge
        str = str.sub(RX_CHALLENGE, STR_EMPTY).gsub(RX_CHALLENGE2, STR_EMPTY).to_i
        challenge_packet = sprintf(STR_BLA, handle_chr(str >> 24), handle_chr(str >> 16), handle_chr(str >> 8), handle_chr(str >> 0))
        self.needs_challenge = challenge_packet
      end
    end

    def handle_state; [STATE_INIT, STATE_RECEIVED_CHALLENGE].include? state; end

    # Supports challenge/response and multi-packet
    def sync reply = self.fetch
      game_data, key = {}, nil
      return game_data if reply.nil? || reply.empty?

      parser = Parser.new(reply)
      data = parser.parse

      game_data.merge!(data[:game])
      game_data["players"] = Parser.pretty_player_data2(data[:players]).sort {|a, b| a[:name].downcase <=> b[:name].downcase }

      game_data["ping"] = @ping unless @ping.nil?

      game_data
    end

    def fetch
      pings = []
      r = self.data
      begin
        until valid?
          if handle_state
            if IO.select(nil, [self], nil, DEFAULT_TIMEOUT)
              handle_write
            else
              raise "TimeOut"
            end
          else
            if IO.select([self], nil, nil, DEFAULT_TIMEOUT)
              handle_read
            else
              raise "TimeOut"
            end
          end
        end
        data.each_pair {|k, d| Tools.debug {"GSPY Infos: #{k} #{d.size}"} } unless @silent || !$debug

        pings.map!{|ping| (ping * 1000).round}
        pings_c = 0
        pings.each { |ping| pings_c += ping }

        ping = pings.size == 0 ? nil : pings_c / pings.size
        Tools.debug{"Gamespy pings: #{pings}, #{ping}"}
        @ping = ping
      rescue => e
        Tools.log_exception(e)
        r = nil
        close unless closed?
      end
      r
    end
  end
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
