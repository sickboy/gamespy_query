module GamespyQuery
  # Provides mass processing of Gamespy UDP sockets, by using Socket/IO select
  class SocketMaster < Base
    # Should the current queue be extended to the maximum amount of connections, or should the queue be emptied first,
    # before adding more?
    FILL_UP_ON_SPACE = true

    # Default maximum concurrent connections
    DEFAULT_MAX_CONNECTIONS = 128

    # Configurable timeout in seconds
    attr_accessor :timeout

    # Configurable max concurrenct connections
    attr_accessor :max_connections

    # Initializes the object
    # @param [Array] addrs List of addresses to process
    def initialize addrs
      @addrs = addrs

      @timeout, @max_connections = Socket::DEFAULT_TIMEOUT, DEFAULT_MAX_CONNECTIONS # Per select iteration
    end

    # Process the list of addresses
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
            Tools.logger.warn "Timeout, no usable sockets in current queue, within timeout period (#{@timeout}s)"
            queue.each{|s| s.close unless s.closed?}
            queue = []
            next
          end

          Tools.debug {"Sockets: #{queue.size}, AddrsLeft: #{@addrs.size}, ReadReady: #{"#{ready[0].size} / #{read_sockets.size}, WriteReady: #{ready[1].size} / #{write_sockets.size}, ExcReady: #{ready[2].size} / #{queue.size}" unless ready.nil?}"}

          # Read
          ready[0].each { |s| begin; s.handle_read(); rescue nil, Exception => e; queue.delete(s); end }

          # Write
          ready[1].each { |s| begin; s.handle_write(); rescue nil, Exception => e; queue.delete(s); end }

          # Exceptions
          #ready[2].each { |s| queue.delete(s) unless s.handle_exc }
        end
      end

      return sockets
    end

    class <<self
      # Fetch the gamespy master browser list
      # Connect to each individual server to receive player data etc
      # @param [String] game Game to fetch info from
      # @param [String] geo Geo location enabled?
      # @param [Array] remote Hostname and path+filename strings if the list needs to be fetched from http server
      def process_master(game = "arma2oapc", geo = nil, remote = nil)
        master = GamespyQuery::Master.new(geo, game)
        list = if remote
                 Net::HTTP.start(remote[0]) do |http|
                   resp = http.get(remote[1])
                   resp.body.split("\n")
                 end
               else
                 master.get_server_list(nil, true, geo)
               end

        dat = master.process list

        sm = GamespyQuery::SocketMaster.new(dat.keys)
        sockets = sm.process!
        sockets.select{|s| s.valid? }.each do |s|
          begin
            data = dat[s.addr]
            data[:ip], data[:port] = s.addr.split(":")
            data[:gamename] = game
            data[:gamedata].merge!(s.sync(s.data))
          rescue => e
            Tools.log_exception e
          end
        end

        dat.values
      end
    end
  end
end
