require 'socket'
require_relative 'socket'

module GamespyQuery
  class SocketMaster < Socket
    FILL_UP_ON_SPACE = true
    DEFAULT_MAX_CONNECTIONS = 128
    DEFAULT_TIMEOUT = 3

    attr_accessor :timeout, :max_connections

    class Socket < UDPSocket
      include Funcs
      STATE_INIT, STATE_SENT_CHALLENGE, STATE_RECEIVED_CHALLENGE, STATE_SENT_CHALLENGE_RESPONSE, STATE_RECEIVE_DATA, STATE_READY = 0, 1, 2, 3, 4, 5

      attr_accessor :addr, :data, :state, :stamp, :needs_challenge, :max_packets, :failed

      def initialize(addr, address_family = ::Socket::AF_INET)
        @addr, @data, @state, @max_packets = addr, [], 0, SocketMaster::MAX_PACKETS
        @id_packet = SocketMaster::ID_PACKET
        @packet = SocketMaster::CHALLENGE_PACKET + @id_packet

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
              self.puts self.needs_challenge ? SocketMaster::BASE_PACKET + @id_packet + self.needs_challenge + SocketMaster::FULL_INFO_PACKET_MP : SocketMaster::BASE_PACKET + @id_packet + SocketMaster::FULL_INFO_PACKET_MP
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
              data = self.recvfrom_nonblock(SocketMaster::RECEIVE_SIZE)
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
              data = self.recvfrom_nonblock(SocketMaster::RECEIVE_SIZE)
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
        if game_data.sub(SocketMaster::STR_GARBAGE, SocketMaster::STR_EMPTY)[SocketMaster::RX_SPLITNUM]
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
        need_challenge = !(str.sub(STR_X0, STR_EMPTY) =~ SocketMaster::RX_NO_CHALLENGE)
        if need_challenge
          str = str.sub(SocketMaster::RX_CHALLENGE, SocketMaster::STR_EMPTY).gsub(SocketMaster::RX_CHALLENGE2, SocketMaster::STR_EMPTY).to_i
          challenge_packet = sprintf(SocketMaster::STR_BLA, handle_chr(str >> 24), handle_chr(str >> 16), handle_chr(str >> 8), handle_chr(str >> 0))
          self.needs_challenge = challenge_packet
        end
      end
    end

    def initialize addrs
      @addrs = addrs

      @timeout, @max_connections = DEFAULT_TIMEOUT, DEFAULT_MAX_CONNECTIONS # Per select iteration
    end

    def process!
      sockets = []

      until @addrs.empty?
        addrs = @addrs.shift @max_connections
        queue = addrs.map { |addr| Socket.new(addr) }

        sockets += queue

        until queue.empty?
          # Fill up the Sockets pool until max_conn
          if FILL_UP_ON_SPACE && queue.size < @max_connections
            addrs = @addrs.shift (@max_connections - queue.size)
            socks = addrs.map { |addr| Socket.new(addr) }

            queue += socks
            sockets += socks
          end

          write_sockets, read_sockets = queue.reject {|s| s.valid? }.partition {|s| [Socket::STATE_INIT, Socket::STATE_RECEIVED_CHALLENGE].include? s.state }

          unless ready = IO.select(read_sockets, write_sockets, nil, @timeout)
            puts "Timeout, no usable sockets in current queue, within timeout period"
            queue.each{|s| s.close unless s.closed?}
            queue = []
            next
          end

          puts "Sockets: #{queue.size}, AddrsLeft: #{@addrs.size}, ReadReady: #{"#{ready[0].size} / #{read_sockets.size}, WriteReady: #{ready[1].size} / #{write_sockets.size}, ExcReady: #{ready[2].size} / #{queue.size}" unless ready.nil?}"

          # Read
          ready[0].each { |s| queue.delete(s) unless s.handle_read() }

          # Write
          ready[1].each { |s| queue.delete(s) unless s.handle_write() }

          # Exceptions
          #ready[2].each { |s| queue.delete(s) unless s.handle_exc }
        end
      end

      return sockets
    end
  end
end

if $0 == __FILE__
  srv = File.open("servers.txt") { |f| f.read }
  addrs = []
  srv.each_line { |line| addrs << "#{$1}:#{$2}" if line =~ /([\d\.]+)[\s\t]*(\d+)/ }

  # addrs = ["192.168.50.1:2356", "89.169.242.67:2302"]
  #addrs = ["95.156.228.83:2402"]
  #addrs = addrs[0..9]

  time_start = Time.now

  sm = GamespyQuery::SocketMaster.new(addrs)
  sockets = sm.process!

  cool = sockets.count {|v| v.valid? }
  dude = sockets.size - cool

  puts "Success: #{cool}, Failed: #{dude}"
  time_taken = Time.now - time_start
  puts "Took: #{time_taken}s"
end
