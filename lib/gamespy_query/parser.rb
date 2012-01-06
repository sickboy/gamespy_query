# encoding: utf-8

=begin
 GameSpy parser class by Sickboy [Patrick Roza] (sb_at_dev-heaven.net)

 Notes:
 Gamedata values are not split, Player lists can be (names, teams, scores, deaths), while individual values still are not.
=end

require_relative 'base'

module GamespyQuery
  class Parser
    STR_SPLIT = STR_X0
    STR_ID = "\x00\x04\x05\x06\a"

    RX_SPLITNUM = /^splitnum\x00(.)/i
    RX_PLAYER_HEADER = /\x01/
    RX_END = /\x00\x02$/

    # packets:
    #   - Hash, key: packetID, value: packetDATA
    #   or
    #   - Array, packetDATA ordered already by packetID
    def initialize(packets)
      @packets = case packets
      when Hash
        packets.keys.sort.map{|key| packets[key] }
      when Array
        packets
      else
        raise "Unsupported format"
      end
    end

    # Returns Hash with parsed data (:game and :players)
    # :game => Hash, Key: InfoKey, Value: InfoValue
    # :players => Hash, Key: InfoType, Value: Array of Values
    def parse
      data = {}
      data[:game] = {} # Key: InfoKey, Value: InfoValue
      data[:players] = {} # Key: InfoType, Value: Array of Values
      player_info = false
      player_data = ""

      # Parse the packets
      @packets.each do |packet|
        packet = clean_packet(packet)

        if player_info
          # Player header was found before, add packet to player_data
          player_data += packet
        else
          if packet =~ RX_PLAYER_HEADER
            # Found Player header, packet possibly contains partial gamedata too
            player_info = true
            packets = packet.split(RX_PLAYER_HEADER, 2)

            # Parse last game_data piece if available
            data[:game].merge!(parse_game_data(packets[0])) unless packets[0].empty?

            # Collect the player_data if available
            player_data += packets[1]
          else
            # GameData-only
            data[:game].merge!(parse_game_data(packet))
          end         
        end
      end

      # Parse player_data
      unless player_data.empty?
        data[:players] = parse_player_data(player_data)
      end

      data
    end

    if RUBY_PLATFORM =~ /mswin32/
      def get_string(str)
        System::Text::Encoding.UTF8.GetString(System::Array.of(System::Byte).new(str.bytes.to_a)).to_s
      end
    else
      def get_string(str)
        #(str + '  ').encode("UTF-8", :invalid => :replace, :undef => :replace)[0..-2]
        str
      end
    end

    def clean_packet(packet)
      packet = packet.clone
      packet.sub!(STR_ID, STR_EMPTY) # Cut off the identity
      packet.sub!(RX_SPLITNUM, STR_EMPTY) # Cut off the splitnum
      packet.sub!(RX_X0_E, STR_EMPTY) # Cut off last \x00
      packet.sub!(RX_X0_S, STR_EMPTY) # Cut off first \x00 
      packet.sub!(RX_END, STR_EMPTY) # Cut off the last \x00\x02

      # Encoding
      get_string(packet)
    end

    def parse_game_data(packet)
      Tools.debug {"Game Parsing #{packet.inspect}"}

      key = nil
      game_data = {}

      packet.split(STR_SPLIT).each_with_index do |data, index|
        if (index % 2) == 0
          key = data
        else
          game_data[key] = data
        end
      end

      game_data
    end

    RX_PLAYER_EMPTY = /^player_\x00\x00\x00/
    RX_PLAYER_INFO = /\x01(team|player|score|deaths)_.(.)/ # \x00 from previous packet, \x01 from continueing player info, (.) - should it overwrite previous value?
    STR_DEATHS = "deaths_\x00\x00"
    STR_PLAYER = "player_\x00\x00"
    STR_TEAM = "team_\x00\x00"
    STR_SCORE = "score_\x00\x00"

    # TODO: Cleanup
    def parse_player_data(packet)
      Tools.debug {"Player Parsing #{packet.inspect}"}

      player_data = {:names => [], :teams => [], :scores => [], :deaths => []} # [[], [], [], []]

      return player_data if packet.nil? || packet.empty?

      data = packet.clone
      unless data =~ RX_PLAYER_EMPTY

        # Leave out the character or Replace character with special string later used to replace the previous value
        data.sub!(RX_PLAYER_INFO) { |r|
          str = $1
          if $2 == STR_X0
            # If a proper primary info header of this type was not yet found, replace this secondary header with a proper primary header
            # This will add the broken info header to the previous info list (name for team, team for score, score for deaths)
            # However the resulting arrays are limited to num_players, so the info is discared anyway.
            # TODO: Cleaner implementation!
            data =~ /(^|[^\x01])#{str}_\x00\x00/ ? STR_X0 : :"#{str}_\x00\x00"
          else
            STR_SIX_X0
          end
        }

        data, deaths = data.split(STR_DEATHS, 2)
        data, scores = data.split(STR_SCORE, 2)
        data, teams = data.split(STR_TEAM, 2)
        data, names = data.split(STR_PLAYER, 2)

        orig_data = [names, teams, scores, deaths]

        # TODO: Handle seperate score
        orig_data.each_with_index do |data, i|
          next if data.nil? || data.empty?
          str = data.clone

          str.sub!(RX_X0_E, STR_EMPTY) # Remove last \x00

          # Parse the data - \x00 is printed after a non-nil entry, otherwise \x00 means nil (e.g empty team)
          until str.empty?
            entry = str[RX_X0_SPEC]
            player_data[player_data.keys[i]] << entry.sub(STR_X0, STR_EMPTY)
            str.sub!(entry, STR_EMPTY)
          end
          
          # Search for SIX string to overwrite last entry
          new_player_data = []
          overwrite = false
          player_data[player_data.keys[i]].each do |info|
            if info == STR_SIX
              overwrite = true # tag so that the next entry will overwrite the latest entry
              next # ignore
            else
              if overwrite
                new_player_data[-1] = info # Overwrite latest entry
                overwrite = false # done the overwrite
              else
                #break if new_player_data.size == num_players
                new_player_data << info # insert entry
              end
            end
          end
          player_data[player_data.keys[i]] = new_player_data
        end
      end

      player_data
    end

    # Hash of Hashes
    def self.pretty_player_data(data)
      player_data = {}

      data[:names].each_with_index do |name, index|
        player_data[name] = {}
        player_data[name][:team] = data[:teams][index]
        player_data[name][:score] = data[:scores][index]
        player_data[name][:deaths] = data[:deaths][index]
      end

      player_data
    end

    # Array of Hashes
    def self.pretty_player_data2(data)
      player_data = []

      data[:names].each_with_index do |name, index|
        player = {}

        player[:name] = name
        player[:team] = data[:teams][index]
        player[:score] = data[:scores][index]
        player[:deaths] = data[:deaths][index]

        player_data << player
      end

      player_data
    end
  end
end
