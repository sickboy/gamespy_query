require 'cri'
require 'ostruct'

module GamespyQuery
  # Handles commandline parameters for the Main tool
  class Options
    class <<self
      # Parse given args
      # @param [Array] args Parse given args
      def parse args = ARGV
        _parse(options).run(args)
      end

      # Defaults for options
      # @param [Hash] opts Options
      def setup_master_opts opts
        opts = opts.clone
        opts[:geo] ||= ""
        opts[:game] ||= "arma2oapc"
        opts
      end

      private
      # Parser definition
      def _parse options
        #root_command = Cri::Command.new_basic_root # Bug with h self.help -> cmd.help etc
        root_command = Cri::Command.define do
          name        'gamespy_query'
          usage       'gamespy_query [options]'
          summary     'Gamespy Protocol'
          description 'This command provides the basic functionality'


          option :h, :help, 'show help for this command' do |value, cmd|
            puts cmd.help
            exit 0
          end

          subcommand Cri::Command.new_basic_help

          flag nil, :version, 'Show version' do |value, cmd|
            puts GamespyQuery.product_version
            exit 0
          end

          flag :v, :verbose, 'Verbose'
        end

        root_command.define_command do
          name    'sync'
          usage   'sync ip:port [options]'
          summary 'Sync data'
          aliases :s

          run do |opts, args, cmd|
            puts "Running Sync, #{opts}, #{args}, #{cmd}"
            if args.empty?
              puts "Missing ip:port"
              exit 1
            end
            host, port = if args.size > 1
                           args
                         else
                           args[0].split(":")
                         end
            time_start = Time.now
            g = GamespyQuery::Socket.new("#{host}:#{port}")
            r = g.sync
            time_taken = Time.now - time_start
            puts "Took: #{time_taken}s"
            exit unless r
            puts r.to_yaml
          end
        end

        root_command.add_command _parse_master_command(options)

        root_command
      end

      def _parse_master_command options
        master_command = Cri::Command.define do
          name    'master'
          usage   'master COMMAND [options]'
          aliases :m

          option :g, :game, 'Specify game', :argument => :required
          option nil, :geo, 'Specify geo', :argument => :required

          subcommand Cri::Command.new_basic_help

          run do |opts, args, cmd|
            puts "Running Master, #{opts}, #{args}, #{cmd}"
          end
        end

        master_command.define_command do
          name 'list'
          usage 'list [options]'
          aliases :l

          run do |opts, args, cmd|
            opts = GamespyQuery::Options.setup_master_opts opts
            master = GamespyQuery::Master.new(opts[:geo], opts[:game])
            list = master.read
            puts list
          end
        end

        master_command.define_command do
          name 'process'
          usage 'process [options]'
          aliases :p

          run do |opts, args, cmd|
            opts = GamespyQuery::Options.setup_master_opts opts

            master = GamespyQuery::Master.new(opts[:geo], opts[:game])
            process = master.process
            puts process
          end
        end

        master_command.define_command do
          name 'process_master'
          usage 'process_master [options]'
          aliases :m

          run do |opts, args, cmd|
            opts = GamespyQuery::Options.setup_master_opts opts
            process = GamespyQuery::SocketMaster.process_master(opts[:game], opts[:geo])
            puts process
          end
        end

        master_command
      end
    end
  end
end
