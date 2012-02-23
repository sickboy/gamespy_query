require 'socket'
require_relative 'socket'

module GamespyQuery
  class SocketMaster < Socket
    FILL_UP_ON_SPACE = true
    DEFAULT_MAX_CONNECTIONS = 128
    DEFAULT_TIMEOUT = 3
    STATE_INIT, STATE_SENT_CHALLENGE, STATE_RECEIVED_CHALLENGE, STATE_SENT_CHALLENGE_RESPONSE, STATE_RECEIVE_DATA, STATE_READY = 0, 1, 2, 3, 4, 5

    attr_accessor :timeout, :max_connections

    class Socket < UDPSocket
      attr_accessor :addr, :data, :state, :stamp, :needs_challenge, :max_packets, :failed

      def initialize(addr, address_family = ::Socket::AF_INET)
        @addr, @data, @state, @max_packets = addr, [], 0, SocketMaster::MAX_PACKETS
        super(address_family)
        self.connect(*addr.split(":"))
      end

      def state=(state); @state = state; @stamp = Time.now; end

      def valid?; @state == SocketMaster::STATE_READY; end
    end

    def initialize addrs
      @addrs = addrs
      @id_packet = ID_PACKET
      @packet = CHALLENGE_PACKET + @id_packet

      @timeout = DEFAULT_TIMEOUT # Per select iteration
      @max_connections = DEFAULT_MAX_CONNECTIONS
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

          write_sockets, read_sockets = queue.reject {|s| s.valid? }.partition {|s| [STATE_INIT, STATE_RECEIVED_CHALLENGE].include? s.state }

          unless ready = IO.select(read_sockets, write_sockets, nil, @timeout)
            puts "Timeout, no usable sockets in current queue, within timeout period"
            queue.each{|s| s.close unless s.closed?}
            queue = []
            next
          end
          puts "Sockets: #{queue.size}, AddrsLeft: #{@addrs.size}, ReadReady: #{"#{ready[0].size} / #{read_sockets.size}, WriteReady: #{ready[1].size} / #{write_sockets.size}, ExcReady: #{ready[2].size} / #{queue.size}" unless ready.nil?}"

          # Read
          ready[0].each { |s| handle_read s, queue }

          # Write
          ready[1].each { |s| handle_write s, queue }

          # Exceptions
          #ready[2].each { |s| handle_exc s, queue }
        end
      end

      return sockets
    end

    def handle_read s, queue
      case s.state
        when STATE_SENT_CHALLENGE
          begin
            data = s.recvfrom_nonblock(RECEIVE_SIZE)
            puts "Read (1): #{s.inspect}: #{data}"

            handle_challenge s, get_string(data[0])

            s.state = STATE_RECEIVED_CHALLENGE
          rescue => e
            puts "Error: #{e.message}, #{s.inspect}"
            s.failed = true
            queue.delete s
            s.close
          end
        when STATE_SENT_CHALLENGE_RESPONSE, STATE_RECEIVE_DATA
          begin
            data = s.recvfrom_nonblock(RECEIVE_SIZE)
            puts "Read (3,4): #{s.inspect}: #{data}"
            s.state = STATE_RECEIVE_DATA

            game_data = get_string(data[0])
            Tools.debug {"Received (#{s.data.size + 1}):\n\n#{game_data.inspect}\n\n#{game_data}\n\n"}

            index = handle_splitnum s, game_data

            s.data[index] = game_data

            if s.data.size >= s.max_packets # OR we received the end-packet and all packets required
              puts "Received packet limit: #{s.inspect}"
              s.state = STATE_READY
              queue.delete s
              s.close unless s.closed?
            end
          rescue => e
            puts "Error: #{e.message}, #{s.inspect}"
            s.failed = true
            queue.delete s
            s.close
          end
      end
    end

    def handle_write s, queue
      #puts "Write: #{s.inspect}"
      begin
        case s.state
          when STATE_INIT
            puts "Write (0): #{s.inspect}"
            # Send Challenge
            s.puts @packet
            s.state = STATE_SENT_CHALLENGE
          when STATE_RECEIVED_CHALLENGE
            puts "Write (2): #{s.inspect}"
            # Send Challenge response
            packet = s.needs_challenge ? BASE_PACKET + @id_packet + s.needs_challenge + FULL_INFO_PACKET_MP : BASE_PACKET + @id_packet + FULL_INFO_PACKET_MP
            s.puts packet

            s.state = STATE_SENT_CHALLENGE_RESPONSE
        end
      rescue => e
        puts "Error: #{e.message}, #{s.inspect}"
        s.failed = true
        queue.delete s
        s.close
        return
      end

=begin
      if Time.now - s.stamp > @timeout
        puts "TimedOut: #{s.inspect}"
        s.failed = true
        queue.delete s
        s.close unless s.closed?
      end
=end
    end

    def handle_exc s, queue
      puts "Exception: #{s.inspect}"
      queue.delete s
      s.close
      s.failed = true
    end


    def handle_splitnum s, game_data
      index = 0
      if game_data.sub(STR_GARBAGE, STR_EMPTY)[RX_SPLITNUM]
        splitnum = $1
        flag = splitnum.unpack("C")[0]
        index = (flag & 127).to_i
        last = flag & 0x80 > 0
        # Data could be received out of order, use the "index" id when "last" flag is true, to determine total packet_count
        s.max_packets = index + 1 if last # update the max
        puts "Splitnum: #{splitnum.inspect} (#{splitnum}) (#{flag}, #{index}, #{last}) Max: #{s.max_packets}"
      else
        s.max_packets = 1
      end

      index
    end

    def handle_challenge s, str
      #puts "Received challenge response (#{str.length}): #{str.inspect}"
      need_challenge = !(str.sub(STR_X0, STR_EMPTY) =~ RX_NO_CHALLENGE)
      if need_challenge
        str = str.sub(RX_CHALLENGE, STR_EMPTY).gsub(RX_CHALLENGE2, STR_EMPTY).to_i
        challenge_packet = sprintf(STR_BLA, handle_chr(str >> 24), handle_chr(str >> 16), handle_chr(str >> 8), handle_chr(str >> 0))
        s.needs_challenge = challenge_packet
      end
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
