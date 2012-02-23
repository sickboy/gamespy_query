require 'socket'
require_relative 'socket'

module GamespyQuery
  class SocketMaster < Socket
    def initialize addrs
      @addrs = addrs
    end

    def process!
      jar = {}
      sockets = @addrs.map{|addr| s = UDPSocket.new; s.connect(*addr.split(":")); s }
      sockets.each {|s| jar[s] = {data: [], state: 0, needs_challenge: false, max_packets: MAX_PACKETS, failed: false}}
      # States:
      # 0 - Not begun
      # 1 - Sent Challenge
      # 2 - Received Challenge
      # 3 - Sent Challenge Response
      # 4 - Receive Data
      # 5 - Ready


      id_packet = ID_PACKET
      packet = CHALLENGE_PACKET + id_packet

      while !sockets.empty? && ready = IO.select(sockets, sockets, sockets)
        puts "YAY #{ready.inspect}"

        processed = []

        # Read
        ready[0].each do |s|
          entry = jar[s]

          data = s.recvfrom(4096)
          puts "Read: #{s.inspect}, #{entry}: #{data}"
          processed << s

          case entry[:state]
            when 1
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
                sockets.delete s
              end
          end
        end

        # Write
        (ready[1] - processed).each do |s|
          entry = jar[s]
          puts "Write: #{s.inspect}, #{entry}"
          processed << s
          case entry[:state]
            when 0
              # Send Challenge
              s.puts packet
              entry[:state] = 1
            when 2
              # Send Challenge response
              packet = entry[:needs_challenge] ? BASE_PACKET + id_packet + entry[:needs_challenge] + FULL_INFO_PACKET_MP : BASE_PACKET + id_packet + FULL_INFO_PACKET_MP
              s.puts packet
              entry[:state] = 3
          end
        end

        # Exceptions
        ready[2].each do |s|
          puts "Exception: #{s.inspect}"
          sockets.delete s
          entry = jar[s]
          entry[:failed] = true
        end
      end
      puts "Finished"
      puts jar.inspect
    end
  end
end

if $0 == __FILE__
  sm = GamespyQuery::SocketMaster.new(["192.168.50.1:2356"])
  sm.process!
end