#require 'six/tools'
require 'logger'

module GamespyQuery
  STR_X0, STR_X1, STR_X2 = "\x00", "\x01", "\x02"
  RX_X0, RX_X0_S, RX_X0_E = /\x00/, /^\x00/, /\x00$/
  RX_X0_SPEC = /^\x00|[^\x00]+\x00?/
  STR_EMPTY = ""

  DEBUG = false

  module Tools
    STR_EMPTY = ""
    CHAR_N = "\n"
  
    module_function
    def logger
      @logger ||= defined?(ActionController) ? ActionController::Base.logger || Logger.new("logger.log") : Logger.new("logger.log")
    end

    def dbg_msg(e)
      "#{e.class}: #{e.message if e.respond_to?(:backtrace)}
BackTrace: #{e.backtrace.join(CHAR_N) unless !e.respond_to?(:backtrace) || e.backtrace.nil?}"
    end


    def log_exception(e, as_error = true, msg = "")
      logger.error "#{"#{msg}:" unless msg.empty?}#{e.class} #{e.message}" if as_error

      logger.debug dbg_msg(e)
    end


    def debug(&block)
      return unless DEBUG
      logger.debug yield
    rescue Exception => e
      puts "Error: #{e.class} #{e.message}, #{e.backtrace.join("\n")}"
    end
  end

  module Funcs
    class TimeOutError < StandardError
    end

    def strip_tags(str)
      # TODO: Strip tags!!
      str
    end

    RX_F = /\A\-?[0-9][0-9]*\.[0-9]*\Z/
    RX_I = /\A\-?[0-9][0-9]*\Z/
    RX_S = /\A\-?0[0-9]+.*\Z/

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

    def handle_chr(number)
      number = ((number % 256)+256) if number < 0
      number = number % 256 if number > 255
      number
    end

    def get_string(*params)
      Tools.debug {"Getting string #{params}"}
      _get_string(*params)
    end

    if RUBY_PLATFORM =~ /mswin32/
      include System::Net
      include System::Net::Sockets

      def _get_string(str)
        str.map {|e| e.chr}.join  #  begin; System::Text::Encoding.USASCII.GetString(reply[0]).to_s; rescue nil, Exception => e; Tools.log_exception(e); reply[0].map {|e| e.chr}.join; end
      end
    else
      require 'socket'
      require 'timeout'

      def _get_string(str)
        str
      end
    end
  end


  class Base
    include Funcs
  end
end
