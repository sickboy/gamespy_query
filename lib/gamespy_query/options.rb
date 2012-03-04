require 'optparse'
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

        _parse(options).parse!(args)

        options
      end

      private
      # Parser definition
      def _parse options
        OptionParser.new do |opts|
          opts.banner = "Usage: #{$0} [options]"
          opts.separator ""
          opts.separator "Specific options:"




          # Boolean switch.
          opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
            options.verbose = v
          end

          opts.separator ""
          opts.separator "Common options:"

          # No argument, shows at tail.  This will print an options summary.
          # Try it and see!
          opts.on_tail("-h", "--help", "Show this message") do
            puts opts
            exit
          end

          # Another typical switch to print the version.
          opts.on_tail("--version", "Show version") do
            puts GamespyQuery::VERSION
            exit
          end
        end
      end
    end
  end

  class MasterOptions < Options
    class <<self
      private
      # Parser definition
      def _parse options
        OptionParser.new do |opts|
          opts.banner = "Usage: #{$0} [options]"
          opts.separator ""
          opts.separator "Specific options:"



          # Boolean switch.
          opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
            options.verbose = v
          end

          opts.separator ""
          opts.separator "Common options:"

          # No argument, shows at tail.  This will print an options summary.
          # Try it and see!
          opts.on_tail("-h", "--help", "Show this message") do
            puts opts
            exit
          end

          # Another typical switch to print the version.
          opts.on_tail("--version", "Show version") do
            puts GamespyQuery::VERSION
            exit
          end
        end
      end
    end
  end
end
