# encoding: utf-8
# GameSpy query class by Sickboy [Patrick Roza] (sb_at_dev-heaven.net)

require 'yaml'
require 'socket'

module GamespyQuery
  # Provides socket functionality on multiple platforms
  # TODO
  module MultiSocket
    # Create socket
    def create_socket(*params)
      Tools.debug {"Creating socket #{params}"}
      _create_socket(*params)
    end

    # Write socket
    def socket_send(*params)
      Tools.debug {"Sending socket #{params}"}
      _socket_send(*params)
    end

    # Read socket
    def socket_receive(*params)
      Tools.debug {"Receiving socket #{params}"}
      _socket_receive(*params)
    end

    # Close socket
    def socket_close(*params)
      Tools.debug {"Closing socket #{params}"}
      @s.close
    end

    if RUBY_PLATFORM =~ /mswin32/
      include System::Net
      include System::Net::Sockets

      # Create socket
      def _create_socket(host, port)
        @ip_end_point = IPEndPoint.new(IPAddress.Any, 0)
        @s = UdpClient.new
        @s.client.receive_timeout = DEFAULT_TIMEOUT * 1000
        @s.connect(host, port.to_i)
      end

      # Write socket
      def _socket_send(packet)
        @s.Send(packet, packet.length)
      end

      # Read socket
      def _socket_receive
        @s.Receive(@ip_end_point)
      end

    else

      # Create socket
      def _create_socket(host, port)
        @s = UDPSocket.new
        @s.connect(host, port)
      end

      # Write socket
      def _socket_send(packet)
        @s.puts(packet)
      end

      # Read socket
      def _socket_receive
        begin
          Timeout::timeout(DEFAULT_TIMEOUT) do
            @s.recvfrom(RECEIVE_SIZE)
          end
        rescue Timeout::Error
          raise TimeoutError, "TimeOut on #{self}"
        ensure
          @s.close
        end
      end
    end
  end

  # Provides direct connection functionality to gamespy enabled game servers
  # This query contains up to 7x more information than the gamespy master browser query
  # For example, player lists with info (teams, scores, deaths) are only available by using direct connection
  class Socket < UDPSocket
    include Funcs

    # Default timeout per connection state
    DEFAULT_TIMEOUT = 3

    # Maximum amount of packets sent by the server
    # This is a limit set by gamespy
    MAX_PACKETS = 7

    # Packet bits
    ID_PACKET = [0x04, 0x05, 0x06, 0x07].pack("c*") # TODO: Randomize?
    BASE_PACKET = [0xFE, 0xFD, 0x00].pack("c*")
    CHALLENGE_PACKET = [0xFE, 0xFD, 0x09].pack("c*")

    FULL_INFO_PACKET_MP = [0xFF, 0xFF, 0xFF, 0x01].pack("c*")
    FULL_INFO_PACKET = [0xFF, 0xFF, 0xFF].pack("c*")
    SERVER_INFO_PACKET = [0xFF, 0x00, 0x00].pack("c*")
    PLAYER_INFO_PACKET = [0x00, 0xFF, 0x00].pack("c*")

    # Maximum receive size
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

    # Initializes the object
    # @param [String] addr Server address ("ip:port")
    # @param [Address Family] address_family
    def initialize(addr, address_family = ::Socket::AF_INET)
      @addr, @data, @state, @max_packets = addr, {}, 0, MAX_PACKETS
      @id_packet = ID_PACKET
      @packet = CHALLENGE_PACKET + @id_packet

      super(address_family)
      self.connect(*addr.split(":"))
    end

    # Exception
    class NotInWriteState < StandardError
    end

    # Exception
    class NotInReadState < StandardError
    end

    # Sets the state of the socket
    # @param [Integer] state State to set
    def state=(state); @stamp = Time.now; @state = state; end

    # Is the socket state valid? Only if all states have passed
    def valid?; @state == STATE_READY; end

    # Handle the write state
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
          else
            raise NotInWriteState, "NotInWriteState, #{self}"
        end
      rescue NotInWriteState => e
        r = false
        self.failed = true
        close unless closed?
      rescue => e
        Tools.log_exception e
        self.failed = true
        r = nil
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

    # Handle the read state
    def handle_read
      # Tools.debug {"Read: #{self.inspect}, #{self.state}"}

      r = true
      begin
        case self.state
          when STATE_SENT_CHALLENGE
            data = self.recvfrom_nonblock(RECEIVE_SIZE)
            Tools.debug {"Read (1): #{self.inspect}: #{data}"}

            handle_challenge data[0]

            self.state = STATE_RECEIVED_CHALLENGE
          when STATE_SENT_CHALLENGE_RESPONSE, STATE_RECEIVE_DATA
            data = self.recvfrom_nonblock(RECEIVE_SIZE)
            Tools.debug {"Read (3,4): #{self.inspect}: #{data}"}
            self.state = STATE_RECEIVE_DATA

            game_data = data[0]
            Tools.debug {"Received (#{self.data.size + 1}):\n\n#{game_data.inspect}\n\n#{game_data}\n\n"}

            index = handle_splitnum game_data

            self.data[index] = game_data

            if self.data.size >= self.max_packets # OR we received the end-packet and all packets required
              Tools.debug {"Received packet limit: #{self.inspect}"}
              self.state = STATE_READY
              r = false
              close unless closed?
            end
          else
            raise NotInReadState, "NotInReadState, #{self}"
        end
      rescue NotInReadState => e
        r = false
        self.failed = true
        close unless closed?
      rescue => e
        # TODO: Simply raise the exception?
        Tools.log_exception(e)
        self.failed = true
        r = nil
        close unless closed?
      end
      r
    end

    # Handle the exception state
    # TODO
    def handle_exc
      Tools.debug {"Exception: #{self.inspect}"}
      close unless closed?
      self.failed = true

      false
    end

    # Process the splitnum provided in the packet
    # @param [String] packet Packet data
    def handle_splitnum packet
      index = 0
      if packet.sub(STR_GARBAGE, STR_EMPTY)[RX_SPLITNUM]
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

    # Handle the challenge/response, if the server requires it
    # @param [String] packet Packet to process for challenge/response
    def handle_challenge packet
      # Tools.debug{"Received challenge response (#{packet.length}): #{packet.inspect}"}
      need_challenge = !(packet.sub(STR_X0, STR_EMPTY) =~ RX_NO_CHALLENGE)
      if need_challenge
        str = packet.sub(RX_CHALLENGE, STR_EMPTY).gsub(RX_CHALLENGE2, STR_EMPTY).to_i
        challenge_packet = sprintf(STR_BLA, handle_chr(str >> 24), handle_chr(str >> 16), handle_chr(str >> 8), handle_chr(str >> 0))
        self.needs_challenge = challenge_packet
      end
    end

    # Determine Read/Write/Exception state
    def handle_state; [STATE_INIT, STATE_RECEIVED_CHALLENGE].include? state; end

    # Process data
    # Supports challenge/response and multi-packet
    # @param [String] reply Reply from server
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

    # Fetch all packets from socket
    def fetch
      pings = []
      r = self.data
      begin
        until valid?
          if handle_state
            if IO.select(nil, [self], nil, DEFAULT_TIMEOUT)
              handle_write
            else
              raise TimeOutError, "TimeOut during write, #{self}"
            end
          else
            if IO.select([self], nil, nil, DEFAULT_TIMEOUT)
              handle_read
            else
              raise TimeOutError, "TimeOut during read, #{self}"
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
        # TODO: Simply raise the exception?
        Tools.log_exception(e)
        r = nil
        close unless closed?
      end
      r
    end
  end
end
