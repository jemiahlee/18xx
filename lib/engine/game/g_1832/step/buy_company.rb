# frozen_string_literal: true

require_relative '../../g_1850/step/buy_company'

module Engine
  module Game
    module G1832
      module Step
        # Inherits 1850's phase-2 restriction: only purchasable companies
        # (as returned by game.purchasable_companies) may be bought in phase 2.
        # P4 and P7 are excluded via their no_buy ability; P6 exclusion handled separately.
        class BuyCompany < G1850::Step::BuyCompany
        end
      end
    end
  end
end
