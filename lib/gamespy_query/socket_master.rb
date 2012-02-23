require 'socket'
require_relative 'socket'

module GamespyQuery
  class SocketMaster
    def initialize addrs
      @addrs = addrs
    end

    def process!
      jar = {}
      sockets = @addrs.map{|addr| s = UDPSocket.new; s.connect(*addr.split(":")); s }
      sockets.each {|s| jar[s] = {data: [], state: 0, needs_challenge: false, packet_count: 0, failed: false}}
      # States:
      # 0 - Not begun
      # 1 - Sent Challenge
      # 2 - Received Challenge
      # 3 - Sent Challenge Response
      # 4 - Receive Data
      # 5 - Ready


      id_packet = Socket::ID_PACKET
      packet = Socket::CHALLENGE_PACKET + id_packet

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

              entry[:state] = 2
            when 3, 4
              entry[:state] = 4
              if entry[:data].size >= 7 # OR we received the end-packet and all packets required
                entry[:state] = 5
                sockets.delete s
              end
          end

          entry[:data] << data

          s.close
          sockets.delete s
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
              #s.puts pack
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