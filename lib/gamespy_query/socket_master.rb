require 'socket'
require_relative 'socket'

module GamespyQuery
  class SocketMaster < Socket
    FILL_UP_ON_SPACE = true
    DEFAULT_MAX_CONNECTIONS = 128
    DEFAULT_TIMEOUT = 3

    attr_accessor :timeout, :max_connections

    class Socket < UDPSocket
      attr_accessor :addr, :data, :state, :stamp, :needs_challenge, :max_packets, :failed
      def data; @data ||= []; end
      def state; @state ||= 0; end
      def max_packets; @max_packets ||= MAX_PACKETS; end
      def valid?; @state == 5; end
    end

    def initialize addrs
      @addrs = addrs
      @id_packet = ID_PACKET
      @packet = CHALLENGE_PACKET + @id_packet

      @timeout = DEFAULT_TIMEOUT # Per select iteration
      @max_connections = DEFAULT_MAX_CONNECTIONS
    end

    # States:
    # 0 - Not begun
    # 1 - Sent Challenge
    # 2 - Received Challenge
    # 3 - Sent Challenge Response
    # 4 - Receive DataPackets (max 7)
    # 5 - Ready
    def process!
      sockets = []

      until @addrs.empty?
        addrs = @addrs.shift @max_connections
        queue = addrs.map do |addr|
          s = Socket.new
          s.connect(*addr.split(":"))
          s.addr = addr
          s
        end

        sockets += queue

        until queue.empty?
          # Fill up the Sockets pool until max_conn
          if FILL_UP_ON_SPACE && queue.size < @max_connections
            addrs = @addrs.shift (@max_connections - queue.size)

            socks = addrs.map do |addr|
              s = Socket.new
              s.connect(*addr.split(":"))
              s.addr = addr
              s
            end

            queue += socks
            sockets += socks
          end

          write_sockets, read_sockets = queue.reject {|s| s.valid? }.partition {|s| [0, 2].include? s.state }

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
        when 1
          begin
            data = s.recvfrom_nonblock(RECEIVE_SIZE)
            puts "Read (1): #{s.inspect}: #{data}"
            s.stamp = Time.now

            handle_challenge s, get_string(data[0])

            s.state = 2
          rescue => e
            puts "Error: #{e.message}, #{s.inspect}"
            s.failed = true
            queue.delete s
            s.close
          end
        when 3, 4
          begin
            data = s.recvfrom_nonblock(RECEIVE_SIZE)
            puts "Read (3,4): #{s.inspect}: #{data}"
            s.stamp = Time.now
            s.state = 4

            game_data = get_string(data[0])
            Tools.debug {"Received (#{s.data.size + 1}):\n\n#{game_data.inspect}\n\n#{game_data}\n\n"}

            index = handle_splitnum s, game_data

            s.data[index] = game_data

            if s.data.size >= s.max_packets # OR we received the end-packet and all packets required
              puts "Received packet limit: #{s.inspect}"
              s.state = 5
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
          when 0
            puts "Write (0): #{s.inspect}"
            # Send Challenge
            s.puts @packet
            s.state = 1
            s.stamp = Time.now
          when 2
            puts "Write (2): #{s.inspect}"
            # Send Challenge response
            packet = s.needs_challenge ? BASE_PACKET + @id_packet + s.needs_challenge + FULL_INFO_PACKET_MP : BASE_PACKET + @id_packet + FULL_INFO_PACKET_MP
            s.puts packet

            s.state = 3
            s.stamp = Time.now
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
