# frozen_string_literal: true

require_relative '../../corporation'

module Engine
  module Game
    module G1832
      class Corporation < Engine::Corporation
        attr_accessor :coal_token, :cotton_token, :port_token, :key_west_placed,
                      :system_shells, :system_id, :operated_once
      end
    end
  end
end
