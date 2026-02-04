# frozen_string_literal: true

require_relative '../../g_1850/step/price_protection'

module Engine
  module Game
    module G1832
      module Step
        class PriceProtection < G1850::Step::PriceProtection
          # Use object identity instead of value equality so that a freshly
          # constructed market-share bundle (share.to_bundle) does not compare
          # equal to the protected bundle and generate a spurious Buy button
          # alongside the dedicated "Protect Shares" button.
          def can_buy?(entity, bundle)
            return unless bundle&.buyable
            return unless bundle.equal?(price_protection)

            have_cert_room = if bundle.corporation.counts_for_limit
                               @game.num_certs(entity, price_protecting: true) + bundle.num_shares <= @game.cert_limit
                             else
                               true
                             end

            entity.cash >= bundle.price &&
              price_protection_seller != entity &&
              have_cert_room
          end
        end
      end
    end
  end
end
