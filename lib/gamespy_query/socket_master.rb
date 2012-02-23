require 'socket'
require_relative 'socket'

module GamespyQuery
  class SocketMaster < Socket
    def initialize addrs
      @addrs = addrs
    end

    def process!
      jar = {}
      # TODO: Keep filling the sockets array when sockets.size  < max_connections
      max_connections = 5
      max_connections_int = max_connections - 1
      timeout = 30

      id_packet = ID_PACKET
      packet = CHALLENGE_PACKET + id_packet

      # States:
      # 0 - Not begun
      # 1 - Sent Challenge
      # 2 - Received Challenge
      # 3 - Sent Challenge Response
      # 4 - Receive Data
      # 5 - Ready


      until @addrs.empty?
        addrs = @addrs[0..max_connections_int]
        @addrs -= addrs
        sockets = addrs.map{|addr| s = UDPSocket.new; s.connect(*addr.split(":")); s }
        sockets.each_with_index {|s, i| jar[s] = {addr: addrs[i], data: [], state: 0, stamp: nil, needs_challenge: false, max_packets: MAX_PACKETS, failed: false}}

        until sockets.empty?
          puts "Loop, #{sockets.size}"
          if sockets.size < max_connections
            count = (max_connections - sockets.size) - 1
            addrs = @addrs[0..count]
            @addrs -= addrs

            socks = addrs.map{|addr| s = UDPSocket.new; s.connect(*addr.split(":")); s }
            socks.each_with_index {|s, i| jar[s] = {addr: addrs[i], data: [], state: 0, stamp: nil, needs_challenge: false, max_packets: MAX_PACKETS, failed: false}}

            sockets += socks
          end

          ready = IO.select(sockets, sockets, sockets)

          processed = []

          # Read
          ready[0].each do |s|
            entry = jar[s]

            begin
              data = s.recvfrom(RECEIVE_SIZE)
            rescue => e
              puts "Error: #{e.message}, #{entry}"
              entry[:failed] = true
              sockets.delete s
              s.close
              next
            end
            #puts "Read: #{s.inspect}, #{entry}: #{data}"
            processed << s
            entry[:stamp] = Time.now

            case entry[:state]
              when 1
                puts "Read (1): #{entry}"
                # Receive challenge
                challenge = data[0]
                str = get_string(challenge)
                puts "Received challenge response (#{str.length}): #{str.inspect}"
                need_challenge = !(str.sub(STR_X0, STR_EMPTY) =~ RX_NO_CHALLENGE)
                if need_challenge
                  Tools.debug {"Needs challenge!"}
                  str = str.sub(RX_CHALLENGE, STR_EMPTY).gsub(RX_CHALLENGE2, STR_EMPTY).to_i
                  challenge_packet = sprintf(STR_BLA, handle_chr(str >> 24), handle_chr(str >> 16), handle_chr(str >> 8), handle_chr(str >> 0))
                  entry[:needs_challenge] = challenge_packet
                end

                entry[:state] = 2
              when 3, 4
                puts "Read (3,4): #{entry}"
                entry[:state] = 4

                index = 0

                game_data = get_string(data[0])
                Tools.debug {"Received (#{entry[:data].size + 1}):\n\n#{game_data.inspect}\n\n#{game_data}\n\n"}

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
                entry[:data][index] = game_data #.sub(RX_X0_S, STR_EMPTY) # Cut off first \x00 from package

                if entry[:data].size >= entry[:max_packets] # OR we received the end-packet and all packets required
                  entry[:state] = 5
                  s.close
                  sockets.delete s
                end
            end
          end

          # Write
          (ready[1] - processed).each do |s|
            entry = jar[s]
            #puts "Write: #{s.inspect}, #{entry}"
            processed << s
            begin
              case entry[:state]
                when 0
                  puts "Write (0): #{entry}"
                  # Send Challenge
                  s.puts packet
                  entry[:state] = 1
                  entry[:stamp] = Time.now
                when 2
                  puts "Write (2): #{entry}"
                  # Send Challenge response
                  packet = entry[:needs_challenge] ? BASE_PACKET + id_packet + entry[:needs_challenge] + FULL_INFO_PACKET_MP : BASE_PACKET + id_packet + FULL_INFO_PACKET_MP
                  s.puts packet
                  entry[:state] = 3
              end
            rescue => e
              puts "Error: #{e.message}, #{entry}"
              entry[:failed] = true
              sockets.delete s
              s.close
              next
            end

            if Time.now - entry[:stamp] > timeout
              puts "TimedOut: #{entry}"
              entry[:failed] = true
              sockets.delete s
              s.close
            end
          end

          # Exceptions
          ready[2].each do |s|
            puts "Exception: #{s.inspect}"
            s.close
            sockets.delete s
            entry = jar[s]
            entry[:failed] = true
          end
        end
      end
      puts "Finished"
      jar.each_pair do |k, v|
        puts v.inspect
      end


      return jar
    end
  end
end

if $0 == __FILE__
  srv = File.open("servers.txt") { |f| f.read }
  addrs = []
  srv.each_line do |line|
    p line
    addrs << "#{$1}:#{$2}" if line =~ /([\d\.]+)[\s\t]*(\d+)/
  end
  # addrs = ["192.168.50.1:2356", "89.169.242.67:2302"]
  #addrs = ["24.3.36.214:2311"]
  sm = GamespyQuery::SocketMaster.new(addrs)
  sm.process!
end
