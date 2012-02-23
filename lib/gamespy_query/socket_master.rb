require 'socket'
require_relative 'socket'

module GamespyQuery
  class SocketMaster < Socket
    FILL_UP_ON_SPACE = true
    DEFAULT_MAX_CONNECTIONS = 128
    DEFAULT_TIMEOUT = 3

    attr_accessor :timeout, :max_connections

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
    # 4 - Receive Data
    # 5 - Ready
    def process!
      jar = {}
      max_connections_int = @max_connections - 1

      until @addrs.empty?
        addrs = @addrs[0..max_connections_int]
        @addrs -= addrs
        sockets = addrs.map{|addr| s = UDPSocket.new; s.connect(*addr.split(":")); s }
        sockets.each_with_index {|s, i| jar[s] = {addr: addrs[i], data: [], state: 0, stamp: nil, needs_challenge: false, max_packets: MAX_PACKETS, failed: false}}

        until sockets.empty?
          read_sockets, write_sockets, exc_sockets = [], [], []

          # Fill up the Sockets pool until max_conn
          if FILL_UP_ON_SPACE && sockets.size < @max_connections
            count = (@max_connections - sockets.size) - 1
            addrs = @addrs[0..count]
            @addrs -= addrs

            socks = addrs.map{|addr| s = UDPSocket.new; s.connect(*addr.split(":")); s }
            socks.each_with_index {|s, i| jar[s] = {addr: addrs[i], data: [], state: 0, stamp: nil, needs_challenge: false, max_packets: MAX_PACKETS, failed: false}}

            sockets += socks
          end

          sockets.each {|s| unless jar[s][:state] >= 5; [0, 2].include?(jar[s][:state]) ? write_sockets << s : read_sockets << s; end }
          #puts "Read: #{read_sockets.inspect}, Write: #{write_sockets.inspect}"
          unless ready = IO.select(read_sockets, write_sockets, nil, @timeout)
            puts "Timeout, no usable sockets within timeout"
            sockets.each{|s| s.close unless s.closed?}
            sockets = []
            next
          end
          puts "Loop, Sockets: #{sockets.size}, AddrsLeft: #{@addrs.size}, ReadReady: #{"#{ready[0].size} / #{read_sockets.size}, WriteReady: #{ready[1].size} / #{write_sockets.size}, ExcReady: #{ready[2].size} / #{exc_sockets.size}" unless ready.nil?}"

          # Read
          ready[0].each { |s| handle_read s, jar[s], sockets }

          # Write
          ready[1].each { |s| handle_write s, jar[s], sockets }

          # Exceptions
          #ready[2].each { |s| handle_exc s, jar[s], sockets }
        end
      end

      return jar
    end

    def handle_read s, entry, sockets
      case entry[:state]
        when 1
          begin
            data = s.recvfrom_nonblock(RECEIVE_SIZE)
            puts "Read (1): #{s.inspect}, #{entry}: #{data}"
            entry[:stamp] = Time.now

            handle_challenge entry, get_string(data[0])

            entry[:state] = 2
          rescue => e
            puts "Error: #{e.message}, #{entry}"
            entry[:failed] = true
            sockets.delete s
            s.close
          end
        when 3, 4
          begin
            data = s.recvfrom_nonblock(RECEIVE_SIZE)
            puts "Read (3,4): #{s.inspect}, #{entry}: #{data}"
            entry[:stamp] = Time.now
            entry[:state] = 4

            game_data = get_string(data[0])
            Tools.debug {"Received (#{entry[:data].size + 1}):\n\n#{game_data.inspect}\n\n#{game_data}\n\n"}

            index = handle_splitnum entry, game_data

            entry[:data][index] = game_data

            if entry[:data].size >= entry[:max_packets] # OR we received the end-packet and all packets required
              puts "Received packet limit: #{entry}"
              entry[:state] = 5
              sockets.delete s
              s.close unless s.closed?
            end
          rescue => e
            puts "Error: #{e.message}, #{entry}"
            entry[:failed] = true
            sockets.delete s
            s.close
          end
      end
    end

    def handle_splitnum entry, game_data
      index = 0
      if game_data.sub(STR_GARBAGE, STR_EMPTY)[RX_SPLITNUM]
        splitnum = $1
        flag = splitnum.unpack("C")[0]
        index = (flag & 127).to_i
        last = flag & 0x80 > 0
        # Data could be received out of order, use the "index" id when "last" flag is true, to determine total packet_count
        entry[:max_packets] = index + 1 if last # update the max
        puts "Splitnum: #{splitnum.inspect} (#{splitnum}) (#{flag}, #{index}, #{last}) Max: #{entry[:max_packets]}"
      else
        entry[:max_packets] = 1
      end

      index
    end

    def handle_challenge entry, str
      #puts "Received challenge response (#{str.length}): #{str.inspect}"
      need_challenge = !(str.sub(STR_X0, STR_EMPTY) =~ RX_NO_CHALLENGE)
      if need_challenge
        str = str.sub(RX_CHALLENGE, STR_EMPTY).gsub(RX_CHALLENGE2, STR_EMPTY).to_i
        challenge_packet = sprintf(STR_BLA, handle_chr(str >> 24), handle_chr(str >> 16), handle_chr(str >> 8), handle_chr(str >> 0))
        entry[:needs_challenge] = challenge_packet
      end
    end

    def handle_write s, entry, sockets
      #puts "Write: #{s.inspect}, #{entry}"
      begin
        case entry[:state]
          when 0
            puts "Write (0): #{entry}"
            # Send Challenge
            s.puts @packet
            entry[:state] = 1
            entry[:stamp] = Time.now
          when 2
            puts "Write (2): #{entry}"
            # Send Challenge response
            packet = entry[:needs_challenge] ? BASE_PACKET + @id_packet + entry[:needs_challenge] + FULL_INFO_PACKET_MP : BASE_PACKET + @id_packet + FULL_INFO_PACKET_MP
            s.puts packet

            entry[:state] = 3
            entry[:stamp] = Time.now
        end
      rescue => e
        puts "Error: #{e.message}, #{entry}"
        entry[:failed] = true
        sockets.delete s
        s.close
        return
      end

      if Time.now - entry[:stamp] > @timeout
        puts "TimedOut: #{entry}"
        entry[:failed] = true
        sockets.delete s
        s.close unless s.closed?
      end
    end

    def handle_exc s, entry, sockets
      #  puts "Exception: #{s.inspect}"
      #  sockets.delete s
      #  s.close
      #  entry = jar[s]
      #  entry[:failed] = true
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
  jar = sm.process!

  cool, dude = 0, 0
  jar.each_pair do |k, v|
    if v[:state] >= 5
      cool += 1
    else
      dude += 1
    end
    puts v.inspect
  end
  puts "Success: #{cool}, Failed: #{dude}"
  time_taken = Time.now - time_start
  puts "Took: #{time_taken}s"
end
