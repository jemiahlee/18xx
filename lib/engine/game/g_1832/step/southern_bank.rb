# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G1832
      module Step
        # §17.3 Southern Bank variant: the P6 owner's corporation may take or
        # repay a mortgage on one of its trains or placed tokens during the OR.
        # Interest (10% of mortgage value) is collected in payout_companies.
        class SouthernBank < Engine::Step::Base
          ACTIONS = %w[choose pass].freeze

          def actions(entity)
            return [] unless entity.corporation?
            return [] unless @game.southern_bank?

            p6 = @game.southern_bank_company
            return [] if !p6 || p6.closed? || p6.owner != entity.owner

            can_mortgage = @game.southern_bank_mortgage.nil? && eligible_assets(entity).any?
            can_repay    = @game.southern_bank_mortgage&.dig(:corp) == entity

            return ACTIONS if can_mortgage || can_repay

            []
          end

          def blocks?
            false
          end

          def choice_name
            'Southern Bank'
          end

          def choices
            entity = current_entity
            c = {}

            if @game.southern_bank_mortgage.nil?
              eligible_assets(entity).each_with_index do |asset, idx|
                val  = asset_value(asset)
                half = (val / 2.0).ceil
                dbl  = val * 2
                c["mort_#{idx}_min"] = "Mortgage #{asset_label(asset)} for #{@game.format_currency(half)} (min)"
                c["mort_#{idx}_max"] = "Mortgage #{asset_label(asset)} for #{@game.format_currency(dbl)} (max)"
              end
            elsif @game.southern_bank_mortgage[:corp] == entity
              remaining = @game.southern_bank_mortgage[:value]
              c['repay_half'] = "Repay #{@game.format_currency((remaining / 2.0).ceil)} (half)"
              c['repay_full'] = "Repay #{@game.format_currency(remaining)} (full)"
            end

            c
          end

          def process_choose(action)
            choice = action.choice
            entity = action.entity

            if choice.start_with?('mort_')
              take_mortgage!(entity, choice)
            elsif choice.start_with?('repay_')
              repay_mortgage!(entity, choice)
            end

            pass!
          end

          def process_pass(_action)
            pass!
          end

          private

          def eligible_assets(entity)
            entity.trains.reject(&:obsolete) + entity.tokens.select(&:city)
          end

          def asset_value(asset)
            asset.is_a?(Engine::Train) ? asset.price : 100
          end

          def asset_label(asset)
            if asset.is_a?(Engine::Train)
              "#{asset.name}-train"
            else
              "token in #{asset.city.hex.id}"
            end
          end

          def take_mortgage!(entity, choice)
            _, idx_str, amount_type = choice.split('_')
            asset = eligible_assets(entity)[idx_str.to_i]
            return unless asset

            val    = asset_value(asset)
            amount = amount_type == 'min' ? (val / 2.0).ceil : val * 2

            @game.bank.spend(amount, entity)
            @game.southern_bank_mortgage = { corp: entity, asset_label: asset_label(asset), value: amount }
            @game.log << "#{entity.name} takes Southern Bank mortgage on #{asset_label(asset)} "\
                         "for #{@game.format_currency(amount)}"
          end

          def repay_mortgage!(entity, choice)
            mortgage = @game.southern_bank_mortgage
            return if !mortgage || mortgage[:corp] != entity

            repay = choice == 'repay_half' ? (mortgage[:value] / 2.0).ceil : mortgage[:value]
            raise GameError, "#{entity.name} cannot afford repayment" if entity.cash < repay

            entity.spend(repay, @game.bank)

            if repay >= mortgage[:value]
              @game.southern_bank_mortgage = nil
              @game.log << "#{entity.name} fully repays Southern Bank mortgage"
            else
              @game.southern_bank_mortgage[:value] -= repay
              @game.log << "#{entity.name} repays #{@game.format_currency(repay)} of Southern Bank mortgage; "\
                           "#{@game.format_currency(@game.southern_bank_mortgage[:value])} remaining"
            end
          end
        end
      end
    end
  end
end
