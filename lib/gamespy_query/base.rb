#require 'six/tools'
require 'action_controller'
require 'logger'

module GamespyQuery
  module Tools
    STR_EMPTY = ""
  
    module_function
    def logger
      ActionController::Base.logger ||= Logger.new("logger.log")
    end
  
    def debug(&block)
      logger.debug yield
    end
  end
  
  class Base
    def strip_tags(str)
      # TODO: Strip tags!!
      str
    end

    STR_X00 = "\x00"
    RX_F = /\A\-?[0-9][0-9]*\.[0-9]*\Z/
    RX_I = /\A\-?[0-9][0-9]*\Z/
    RX_S = /\A\-?0[0-9]+.*\Z/

    def clean(value) # TODO: Force String, Integer, Float etc?
      case value
        when STR_X00
          nil
        when RX_F
          value =~ RX_S ? strip_tags(value) : value.to_f
        when RX_I
          value =~ RX_S ? strip_tags(value) : value.to_i
        else
          strip_tags(value)
      end
    end
  end
end
