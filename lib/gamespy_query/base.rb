#require 'six/tools'
require 'logger'

module GamespyQuery
  STR_X0, STR_X1, STR_X2 = "\x00", "\x01", "\x02"
  RX_X0, RX_X0_S, RX_X0_E = /\x00/, /^\x00/, /\x00$/
  RX_X0_SPEC = /^\x00|[^\x00]+\x00?/
  STR_EMPTY = ""

  DEBUG = false

  # Contains basic Tools set to work with logging, debugging, etc.
  module Tools
    STR_EMPTY = ""
    CHAR_N = "\n"

    module_function
    # Provides access to the logger object
    # Will use ActionController::Base.logger if available
    def logger
      @logger ||= if defined?(::Tools); ::Tools.logger; else; defined?(ActionController) ? ActionController::Base.logger || Logger.new("logger.log") : Logger.new("logger.log"); end
    end

    # Create debug message from Exception
    # @param [Exception] e Exception to create debug message from
    def dbg_msg(e)
      <<STR
#{e.class}: #{e.message if e.respond_to?(:backtrace)}
BackTrace: #{e.backtrace.join(CHAR_N) unless !e.respond_to?(:backtrace) || e.backtrace.nil?}
STR
    end

    # Log exception
    # @param [Exception] e Exception to log
    # @param [Boolean] as_error Log the exception as error in the log
    # @param [String] msg Include custom error message
    def log_exception(e, as_error = true, msg = "")
      if defined?(::Tools)
        ::Tools.log_exception(e, as_error, msg)
      else
        puts "Error: #{e.class} #{e.message}, #{e.backtrace.join("\n") unless e.backtrace.nil? }"
        logger.error "#{"#{msg}:" unless msg.empty?}#{e.class} #{e.message}" if as_error
        logger.debug dbg_msg(e)
      end
    end

    # Log to debug log if DEBUG enabled
    # @param [Block] block Block to yield string from
    def debug(&block)
      return unless DEBUG
      out = yield
      logger.debug out
      puts out
    rescue Exception => e
      puts "Error: #{e.class} #{e.message}, #{e.backtrace.join("\n")}"
    end
  end

  # Contains basic Funcs used throughout the classes
  module Funcs
    # Provides TimeOutError exception
    class TimeOutError < StandardError
    end

    # Strips tags from string
    # @param [String] str
    def strip_tags(str)
      # TODO: Strip tags!!
      str
    end

    # Float Regex
    RX_F = /\A\-?[0-9]+\.[0-9]*\Z/
    # Integer Regex
    RX_I = /\A\-?[0-9]+\Z/
    # Integer / Float actually String Regex
    RX_S = /\A\-?0[0-9]+.*\Z/

    # Clean value, convert if possible
    # @param [String] value String to convert
    def clean(value) # TODO: Force String, Integer, Float etc?
      case value
        when STR_X0
          nil
        when RX_F
          value =~ RX_S ? strip_tags(value) : value.to_f
        when RX_I
          value =~ RX_S ? strip_tags(value) : value.to_i
        else
          strip_tags(value)
      end
    end

    # Handle char
    # @param [Integer] number Integer to convert
    def handle_chr(number)
      number = ((number % 256)+256) if number < 0
      number = number % 256 if number > 255
      number
    end

    # Convert string to UTF-8, stripping out all invalid/undefined characters
    # @param [String] str String to convert
    def encode_string(str)
      #Tools.debug {"Getting string #{str}"}
      # System::Text::Encoding.UTF8.GetString(System::Array.of(System::Byte).new(str.bytes.to_a)).to_s # #  begin; System::Text::Encoding.USASCII.GetString(reply[0]).to_s; rescue nil, Exception => e; Tools.log_exception(e); reply[0].map {|e| e.chr}.join; end
      str.bytes.to_a.pack("U*")
    end
  end

  # Base class from which all others derrive
  class Base
    include Funcs
  end
end
