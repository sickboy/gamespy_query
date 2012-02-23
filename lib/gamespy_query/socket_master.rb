require_relative 'socket'

module GamespyQuery
  class SocketMaster < Base
    FILL_UP_ON_SPACE = true
    DEFAULT_MAX_CONNECTIONS = 128
    DEFAULT_TIMEOUT = 3

    attr_accessor :timeout, :max_connections

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

          write_sockets, read_sockets = queue.reject {|s| s.valid? }.partition {|s| s.handle_state }

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
  srv = File.open(ARGV[0] || "servers.txt") { |f| f.read }
  addrs = []
  srv.each_line { |line| addrs << "#{$1}:#{$2}" if line =~ /([\d\.]+)[\s\t]*(\d+)/ }

  time_start = Time.now

  sm = GamespyQuery::SocketMaster.new(addrs)
  sockets = sm.process!

  cool = sockets.count {|v| v.valid? }
  dude = sockets.size - cool

  puts "Success: #{cool}, Failed: #{dude}"
  time_taken = Time.now - time_start
  puts "Took: #{time_taken}s"
end
