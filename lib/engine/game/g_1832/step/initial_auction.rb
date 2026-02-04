# frozen_string_literal: true

require_relative '../../../step/waterfall_auction'

module Engine
  module Game
    module G1832
      module Step
        # 1832 ISR: payout companies every time all players pass (fake OR),
        # reduce P1 minimum bid when P1 is still unsold,
        # only call or_set_finished when all companies have been sold.
        class InitialAuction < Engine::Step::WaterfallAuction
          protected

          def all_passed!
            @game.payout_companies

            if @companies.include?(@cheapest)
              increase_discount!(@cheapest, 5)
            elsif @companies.empty?
              @game.or_set_finished
            end

            entities.each(&:unpass!)
          end
        end
      end
    end
  end
end
