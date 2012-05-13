module GamespyQuery
  # Provides mass processing of Gamespy UDP sockets, by using Socket/IO select
  class SocketMaster < Base
    # Should the current queue be extended to the maximum amount of connections, or should the queue be emptied first,
    # before adding more?
    FILL_UP_ON_SPACE = true

    # Default maximum concurrent connections
    DEFAULT_MAX_CONNECTIONS = 128

    DEFAULT_THREADS = 0

    # Configurable timeout in seconds
    attr_accessor :timeout

    # Configurable max concurrenct connections
    attr_accessor :max_connections

    # Initializes the object
    # @param [Array] addrs List of addresses to process
    def initialize addrs, info = false
      @addrs = addrs
      @info = info

      @timeout, @max_connections = Socket::DEFAULT_TIMEOUT, DEFAULT_MAX_CONNECTIONS # Per select iteration
    end

    # Process the list of addresses
    def process! use_threads = DEFAULT_THREADS
      sockets = []
      if use_threads.to_i > 0
        monitor = Monitor.new
        threads = []
        addrs_list = @addrs.each_slice(@addrs.size / use_threads).to_a
        use_threads.times.each do |i|
          list = addrs_list.shift
          break if list.nil? || list.empty?
          puts "Spawning thread #{i}" if @info

          threads << Thread.new(list, i) do |addrs, id|
            begin
              puts "Thread: #{id} Start, #{addrs.size}" if @info
              out = proc(addrs)

              puts "Thread: #{id} Pushing output to list. #{out.size}" if @info
              monitor.synchronize do
                sockets += out
              end
              puts "Thread: #{id} End" if @info
            ensure
              ActiveRecord::Base.connection_pool.release_connection
            end
          end
        end
        threads.each {|t| t.join}
      else
        sockets = proc @addrs
      end

      return sockets
    end

    def proc addrs_list
      sockets = []

      until addrs_list.empty?
        addrs = addrs_list.shift @max_connections

        queue = addrs.map { |addr| Socket.new(addr) }
        sockets += queue

        until queue.empty?
          # Fill up the Sockets pool until max_conn
          if FILL_UP_ON_SPACE && queue.size < @max_connections && !addrs_list.empty?
            addrs = addrs_list.shift (@max_connections - queue.size)
            socks = addrs.map { |addr| Socket.new(addr) }

            queue += socks
            sockets += socks
          end

          write_sockets, read_sockets = queue.partition {|s| s.handle_state }

          unless ready = IO.select(read_sockets, write_sockets, nil, @timeout)
            Tools.logger.warn "Timeout, no usable sockets in current queue, within timeout period (#{@timeout}s)"
            queue.each{|s| s.close unless s.closed?}
            queue = []
            next
          end

          Tools.debug {"Sockets: #{queue.size}, AddrsLeft: #{addrs_list.size}, ReadReady: #{"#{ready[0].size} / #{read_sockets.size}, WriteReady: #{ready[1].size} / #{write_sockets.size}, ExcReady: #{ready[2].size} / #{queue.size}" unless ready.nil?}"}

          # Read
          ready[0].each { |s| begin; s.handle_read(); rescue nil, Exception => e; queue.delete(s); end }

          # Write
          ready[1].each { |s| begin; s.handle_write(); rescue nil, Exception => e; queue.delete(s); end }

          # Exceptions
          #ready[2].each { |s| queue.delete(s) unless s.handle_exc }
          queue.reject! {|s| s.valid? }
        end
      end

      sockets
    end

    class <<self
      # Fetch the gamespy master browser list
      # Connect to each individual server to receive player data etc
      # @param [String] game Game to fetch info from
      # @param [String] geo Geo location enabled?
      # @param [Array] remote Hostname and path+filename strings if the list needs to be fetched from http server
      def process_master(game = "arma2oapc", geo = nil, remote = nil, dedicated_only = false, sm_dedicated_only = true, info = false)
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

        ded = "1"
        gm_dat = if dedicated_only || sm_dedicated_only
          h = {}
          dat.each_pair do |k, v|
            next unless v[:gamedata] && v[:gamedata][:dedicated] == ded
            h[k] = v
          end
          h
        else
          dat
        end

        sm = GamespyQuery::SocketMaster.new(gm_dat.keys, info)
        sockets = sm.process!
        valid_sockets = sockets.select{|s| s.valid? }
        puts "Sockets: #{sockets.size}, Valid: #{valid_sockets.size}" if info
        valid_sockets.each do |s|
          begin
            data = gm_dat[s.addr]
            data[:ip], data[:port] = s.addr.split(":")
            data[:gamename] = game
            data[:gamedata].merge!(s.sync(s.data))
          rescue => e
            Tools.log_exception e
          end
        end

        dedicated_only ? gm_dat.values : dat.values
      end
    end
  end
end
