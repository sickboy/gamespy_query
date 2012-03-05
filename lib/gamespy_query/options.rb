require 'slop'
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

        options.options = _parse(args, options)

        options.argv = args.clone
        args.clear

        options
      end

      private
      # Parser definition
      def _parse args, options
        opts = Slop.parse!(args, {help: true, strict: true}) do
          banner "Usage: #{$0} ip:port [options]"

          on :s, :sync, 'Perform sync operation' do
            options.tasks << :sync
          end

          on :v, :verbose, 'Enable verbose mode'

          on :version, 'Show version' do
            puts GamespyQuery::VERSION
          end
        end

        opts
      end
    end
  end

  class MasterOptions < Options
    class <<self
      private
      # Parser definition
      def _parse args, options
        opts = Slop.parse!(args, {help: true, strict: true}) do
          banner "Usage: #{$0} [GAME] [GEO] [options]"

          on :l, :list, 'Fetch gamespy server list' do
            options.tasks << :list
          end

          on :p, :process, 'Fetch gamespy server list and present as hash' do
            options.tasks << :process
          end

          on :m, :process_master, 'Fetch gamespy server list, connect with udpsockets to get player data, and present as hash' do
            options.tasks << :process_master
          end

          on :v, :verbose, 'Enable verbose mode'

          on :version, 'Show version' do
            puts GamespyQuery::VERSION
          end
        end

        opts
      end
    end
  end
end
