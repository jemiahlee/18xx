# frozen_string_literal: true

require_relative '../../g_1870/step/buy_sell_par_shares'

module Engine
  module Game
    module G1832
      module Step
        class BuySellParShares < G1870::Step::BuySellParShares
          # Chronological founding order per rules §17.4.
          # A corporation's 6th share may not be purchased until all predecessors have sold 6 shares.
          HISTORICAL_ORDER = %w[ACL SALR CG GRR SOU A&WP N&W L&N GMO FECR].freeze

          def round_state
            super.merge(system_redemptions: Hash.new(0))
          end

          # §11.6.9: Systems may redeem up to 2 shares per SR (1 per stock turn).
          # G1870 zeros redeem_cash after every corp redemption; restore it for systems
          # after their first redemption so a second turn is still allowed.
          def process_buy_shares(action)
            super
            entity = action.entity
            return if !entity.corporation? || !@game.system?(entity)

            @round.system_redemptions[entity] += 1
            @round.redeem_cash[entity] = entity.share_price.price if @round.system_redemptions[entity] == 1
          end

          # §17.3: P6 cannot be sold between players after the first 6-train.
          def can_sell_company?(company)
            return false if @game.southern_bank? &&
                            company == @game.southern_bank_company &&
                            @game.phase.name.to_i >= 6

            super
          end

          def visible_corporations
            @game.sorted_corporations.reject { |item| @game.system?(item) unless item.floated? }
          end

          # Historical Order variant (§17.4): a corporation's 6th share may not be purchased
          # until all predecessor corporations have already sold 6 shares from their IPO.
          def can_buy?(entity, bundle)
            return super unless @game.optional_rules&.include?(:historical_order)
            return super if @game.system?(bundle&.corporation)

            corp = bundle.corporation
            idx = self.class::HISTORICAL_ORDER.index(corp.id)
            return super unless idx&.positive?

            # Check all predecessors have 6 shares sold (i.e., ≤2 of 8 IPO shares remaining)
            predecessors_ready = self.class::HISTORICAL_ORDER[0...idx].all? do |pred_id|
              pred = @game.corporation_by_id(pred_id)
              pred&.floated? && pred.num_ipo_shares <= 2
            end

            return super if predecessors_ready

            # Block purchase of the 6th share (when corp has ≤3 IPO shares remaining)
            return false if corp.num_ipo_shares <= 3

            super
          end
        end
      end
    end
  end
end
