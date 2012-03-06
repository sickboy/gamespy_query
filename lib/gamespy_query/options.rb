require 'cri'
require 'ostruct'

module GamespyQuery
  # Handles commandline parameters for the Main tool
  class Options
    class <<self
      # Parse given args
      # @param [Array] args Parse given args
      def parse args = ARGV
        options = OpenStruct.new
        options.tasks = []

        root_command = _parse(options)
        root_command.run(args)

        options.argv = args.clone
        args.clear

        options
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
            options.tasks << [:sync, args[0] || Dir.pwd]
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
            options.tasks << :list
          end
        end

        master_command.define_command do
          name 'process'
          usage 'process [options]'
          aliases :p

          run do |opts, args, cmd|
            options.tasks << :process
          end
        end

        master_command.define_command do
          name 'process_master'
          usage 'process_master [options]'
          aliases :m

          run do |opts, args, cmd|
            options.tasks << :process_master
          end
        end

        master_command
      end
    end
  end
end
