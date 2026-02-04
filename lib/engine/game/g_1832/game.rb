# frozen_string_literal: true

require_relative '../g_1870/game'
require_relative 'entities'
require_relative 'map'
require_relative 'market'
require_relative 'meta'
require_relative 'phases'
require_relative 'trains'
require_relative '../base'

module Engine
  module Game
    module G1832
      class Game < Game::Base
        include_meta(G1832::Meta)
        include G1832::Entities
        include G1832::Map
        include G1832::Market
        include G1832::Phases
        include G1832::Trains

        attr_accessor :sell_queue, :reissued, :coal_token_counter, :coal_company_sold_or_closed, :p4_invested_in,
                      :southern_bank_mortgage, :p4_share

        CORPORATION_CLASS = G1832::Corporation
        CORPORATE_BUY_SHARE_ALLOW_BUY_FROM_PRESIDENT = true
        MULTIPLE_BUY_ONLY_FROM_MARKET = true
        MUST_SELL_IN_BLOCKS = true
        EBUY_OTHER_VALUE = false

        CLOSED_CORP_TRAINS_REMOVED = false

        CURRENCY_FORMAT_STR = '$%s'
        BANK_CASH = 12_000
        CAPITALIZATION = :full
        FLOAT_PERCENT = 60

        SOUTHERN_BANK_STARTING_CASH = { 2 => 1200, 3 => 800, 4 => 600, 5 => 480, 6 => 400 }.freeze
        VARIANT_GAME_END_CHECK = { bankrupt: :immediate, bank: :full_or, stock_market: :immediate }.freeze

        IPO_RESERVED_NAME = 'Treasury'

        BOOMTOWN_HEXES = %w[D8 F14 G9 G11 H6 L14].freeze
        MIAMI_HEX = 'N16'

        TILE_LAYS = [{ lay: true, upgrade: true }, { lay: :not_if_upgraded, upgrade: false }].freeze
        SYSTEM_TILE_LAYS = [{ lay: true, upgrade: true },
                            { lay: :not_if_upgraded, upgrade: false },
                            { lay: true, upgrade: :not_if_upgraded, cannot_reuse_same_hex: true }].freeze

        CERT_LIMIT = {
          2 => { '10' => 28, '9' => 24, '8' => 21, '7' => 17, '6' => 14 },
          3 => { '10' => 20, '9' => 17, '8' => 15, '7' => 12, '6' => 10 },
          4 => { '10' => 16, '9' => 14, '8' => 12, '7' => 10, '6' => 8 },
          5 => { '10' => 13, '9' => 11, '8' => 9, '7' => 8, '6' => 6 },
          6 => { '10' => 11, '9' => 9, '8' => 8, '7' => 6, '6' => 5 },
          7 => { '10' => 9, '9' => 7, '8' => 6, '7' => 5, '6' => 4 },
        }.freeze

        STARTING_CASH = { 2 => 1050, 3 => 700, 4 => 525, 5 => 420, 6 => 350, 7 => 300 }.freeze

        def tile_lays(entity)
          return self.class::SYSTEM_TILE_LAYS if system?(entity)
          return self.class::TILE_LAYS if @recently_floated&.include?(entity)

          self.class::TILE_LAYS
        end

        def system?(entity)
          entity.is_a?(Corporation) && entity.type == :system
        end

        ASSIGNMENT_TOKENS = {
          'boomtown' => '/icons/1832/boomtown_token.svg',
          'P2' => '/icons/1846/sc_token.svg',
          'P3' => '/icons/1832/cotton_token.svg',
        }.freeze

        EVENTS_TEXT = Base::EVENTS_TEXT.merge(
          'companies_buyable' => ['Companies become buyable', 'All companies may now be bought in by corporation'],
          'final_merger_chance' => ['Final Merger Chance', 'Last opportunity for mergers and takeovers'],
          'remove_tokens' => ['Remove Tokens', 'Remove private company tokens'],
          'remove_key_west_token' => ['Remove Key West Token', 'FECR loses the Key West']
        ).freeze

        MARKET_TEXT = Base::MARKET_TEXT.merge(
          ignore_one_sale: 'Can only enter when 2 shares sold at the same time'
        ).freeze

        STATUS_TEXT = Base::STATUS_TEXT.merge(
          'can_buy_companies_from_other_players' => ['Interplayer Company Buy',
                                                     'Companies can be bought between players',
                                                     'The West Virginia Coalfields private company can be bought in for '\
                                                     'up to face value from the owning player'],
        ).merge(
          'companies_buyable' => ['Companies become buyable', 'All companies may now be bought in by corporations'],
        )

        def new_auction_round
          Engine::Round::Auction.new(self, [
            G1832::Step::CompanyPendingPar,
            G1832::Step::InitialAuction,
          ])
        end

        def stock_round
          G1870::Round::Stock.new(self, [
            Engine::Step::DiscardTrain,
            G1832::Step::Exchange,
            G1832::Step::BuySellParShares,
            G1832::Step::PriceProtection,
          ])
        end

        def operating_round(round_num)
          steps = [
            Engine::Step::Bankrupt,
            G1832::Step::Exchange,
            G1832::Step::BuyCompany,
            G1870::Step::Assign,
            G1870::Step::SpecialTrack,
            G1832::Step::Track,
            G1832::Step::Token,
            Engine::Step::Route,
            G1832::Step::Dividend,
            Engine::Step::DiscardTrain,
            G1832::Step::BuyTrain,
            [G1832::Step::BuyCompany, { blocks: true }],
            G1832::Step::PriceProtection,
          ]
          steps.unshift(G1832::Step::SouthernBank) if southern_bank?
          Engine::Round::Operating.new(self, steps, round_num: round_num)
        end

        def init_stock_market
          G1870::StockMarket.new(self.game_market, self.class::CERT_LIMIT_TYPES,
                                 multiple_buy_types: self.class::MULTIPLE_BUY_TYPES)
        end

        def ipo_reserved_name(_entity = nil)
          'Treasury'
        end

        def setup
          @sell_queue = []
          @reissued = {}
          @coal_token_counter = 5
          @miami_first_run = false
          @final_merger_triggered = false
          @merger_after_or_set = false
          @recently_floated = []
          @vice_president_certs = {}
          @p4_invested_in = nil
          @southern_bank_mortgage = nil

          coal_company.max_price = coal_company.value

          @sharp_city ||= @all_tiles.find { |t| t.name == '5' }
          @gentle_city ||= @all_tiles.find { |t| t.name == '6' }
          @straight_city ||= @all_tiles.find { |t| t.name == '57' }

          @tile_141 ||= @all_tiles.find { |t| t.name == '141' }
          @tile_142 ||= @all_tiles.find { |t| t.name == '142' }
          @tile_143 ||= @all_tiles.find { |t| t.name == '143' }
          @tile_144 ||= @all_tiles.find { |t| t.name == '144' }
        end

        def game_trains
          @optional_rules&.include?(:diesels) ? self.class::DIESEL_VARIANT_TRAINS : self.class::STANDARD_TRAINS
        end

        def game_phases
          @optional_rules&.include?(:diesels) ? self.class::DIESEL_VARIANT_PHASES : self.class::STANDARD_PHASES
        end

        def game_companies
          @optional_rules&.include?(:southern_bank) ? self.class::SOUTHERN_BANK_VARIANT_COMPANIES : self.class::STANDARD_COMPANIES
        end

        def game_market
          @optional_rules&.include?(:finish_on_400) ? self.class::GAME_END_AT_400_MARKET : self.class::STANDARD_MARKET
        end

        def available_programmed_actions
          [Action::ProgramMergerPass, Action::ProgramBuyShares, Action::ProgramSharePass]
        end

        def merge_rounds
          [G1832::Round::Merger]
        end

        def corps_available_for_systems
          @corporations.select { |c| c.operated? && c.type != :system }
        end

        def event_companies_buyable!
          coal_company.max_price = 2 * coal_company.value
        end

        def event_close_companies!
          @log << '-- Event: Private companies close --'
          @companies.each do |company|
            next if southern_bank? && company.sym == 'P6'

            company.close! unless company.closed?
          end
          @coal_company_sold_or_closed = true
        end

        def event_close_remaining_companies!
          @log << '-- Event: All remaining private companies close --'
          @companies.each(&:close!)
        end

        def event_final_merger_chance!
          @log << '-- Event: Final merger and takeover opportunity --'
          @final_merger_triggered = true
        end

        def event_remove_key_west_token!
          @log << '-- Event: Key West Token removed --'
          fec = fec_corporation
          return unless fec&.key_west_placed

          miami = hex_by_id(self.class::MIAMI_HEX)
          miami&.remove_assignment!(fec.id)
          fec.key_west_placed = false
        end

        # can't run to or through the West Virginia Coalfied hex (B14) without a coal token
        def check_distance(route, visits, _train = nil)
          return super if visits.none? { |v| v.hex == coal_hex } || route.train.owner.coal_token

          raise GameError, 'Corporation must own coal token to enter West Virginia Coalfields'
        end

        def event_remove_tokens!
          removals = Hash.new { |h, k| h[k] = {} }

          @corporations.each do |corp|
            corp.assignments.dup.each do |company, _|
              if ASSIGNMENT_TOKENS[company]
                removals[company][:corporation] = corp
                corp.remove_assignment!(company)
              end
            end
          end

          @hexes.each do |hex|
            hex.assignments.dup.each do |company, _|
              if ASSIGNMENT_TOKENS[company]
                removals[company][:hex] = hex.name
                hex.remove_assignment!(company)
              end
            end
          end

          removals.each do |company, removal|
            hex = removal[:hex]
            corp = removal[:corporation]
            owner = corp ? "#{corp.name}'s " : ''
            @log << "-- Event: #{owner}#{company_by_id(company).name} token removed from #{hex} --"
          end
        end

        def port_company
          @port_company ||= company_by_id('P2')
        end

        def cotton_company
          @cotton_company ||= company_by_id('P3')
        end

        def can_hold_above_corp_limit?(_entity)
          true
        end

        def can_par?(corporation, parrer)
          return false if system?(corporation)

          super
        end

        def coal_company
          @coal_company ||= company_by_id('P5')
        end

        def coal_hex
          @coal_hex ||= hex_by_id('B14')
        end

        def revenue_for(route, stops)
          revenue = super

          cotton = 'P2'
          revenue += 10 if route.corporation.assigned?(cotton) && stops.any? { |stop| stop.hex.assigned?(cotton) }

          revenue += (route.corporation.assigned?('P3') ? 20 : 10) if stops.any? { |stop| stop.hex.assigned?('P3') }

          # Miami first-run rule: worth $0 the first time any corporation runs there
          miami_stops = stops.select { |stop| stop.hex.id == self.class::MIAMI_HEX }
          if !@miami_first_run && miami_stops.any?
            @miami_first_run = true
            miami_stops.each { |stop| revenue -= stop.route_revenue(route.phase, route.train) }
          end

          # Key West bonus: FEC earns +$50 when running to Miami with token placed (phases 3-7)
          if route.corporation == fec_corporation &&
             route.corporation.key_west_placed &&
             miami_stops.any?
            revenue += 50
          end

          revenue
        end

        def sell_shares_and_change_price(bundle, allow_president_change: true, swap: nil, movement: nil)
          @sell_queue << [bundle, bundle.corporation.owner, bundle.owner]

          @share_pool.sell_shares(bundle)
        end

        def num_certs(entity, price_protecting: false)
          entity.shares.sum do |s|
            next 0 unless s.corporation.counts_for_limit
            next 0 unless s.counts_for_limit
            next 0 if !price_protecting && @sell_queue.any? do |bundle, _|
              bundle.corporation == s.corporation &&
                !stock_market.find_share_price(s.corporation, Array.new(bundle.num_shares, :down)).counts_for_limit
            end

            s.cert_size
          end + entity.companies.size
        end

        def legal_tile_rotation?(_entity, _hex, _tile)
          true
        end

        def purchasable_companies(entity = nil)
          entity ||= current_entity
          return super unless @phase.name == '2'

          coal_company.owner.player? ? [coal_company] : []
        end

        def after_sell_company(buyer, company, _price, _seller)
          return unless company == coal_company

          buyer.coal_token = true
          @coal_token_counter -= 1
          @coal_company_sold_or_closed = true
          log << "#{buyer.name} receives Coal token. #{@coal_token_counter} Coal tokens left in the game."
          log << '-- Corporations can now buy Coal tokens --'
        end

        def status_array(corporation)
          statuses = []
          statuses << 'Coal Token' if corporation.coal_token
          statuses << 'Key West Token' if corporation == fec_corporation && corporation.key_west_placed
          statuses.empty? ? nil : statuses
        end

        def upgrades_to?(from, to, special = false, selected_company: nil)
          # Boomtowns: a yellow town tile on a boomtown hex may upgrade to a yellow
          # single-city tile (same color, bypassing normal color-progression check).
          if from.color == :yellow && from.towns.size == 1 && from.cities.empty? &&
             from.hex && self.class::BOOMTOWN_HEXES.include?(from.hex.id) &&
             to.color == :yellow && to.cities.size == 1 && to.towns.empty?
            return Engine::Tile::ALL_EDGES.any? { |ticks| (from.exits - to.exits.map { |e| (e + ticks) % 6 }).empty? }
          end

          super
        end

        def all_potential_upgrades(tile, tile_manifest: false, selected_company: nil)
          upgrades = super

          return upgrades unless tile_manifest

          # Tile manifest: show city upgrades for standard boomtown town tiles
          upgrades |= [@sharp_city, @tile_141, @tile_142, @tile_143] if tile.name == '3'
          upgrades |= [@straight_city, @tile_141, @tile_142] if tile.name == '4'
          upgrades |= [@gentle_city, @tile_141, @tile_142, @tile_143, @tile_144] if tile.name == '58'

          upgrades
        end

        def reissued?(corporation)
          @reissued[corporation]
        end

        def float_corporation(corporation)
          @recently_floated << corporation
          super
        end

        def track_action_processed(entity)
          @recently_floated.delete(entity)
        end

        def graph_skip_paths(entity)
          return nil if entity.coal_token

          @skip_paths ||= {}

          return @skip_paths unless @skip_paths.empty?

          coal_hex.tile.paths.each do |path|
            @skip_paths[path] = true
          end

          @skip_paths
        end

        def max_reissue_200?
          true
        end

        def mergers_allowed?
          @phase.status.include?('mergers_allowed')
        end

        def southern_bank?
          @optional_rules&.include?(:southern_bank)
        end

        # §17.3: P6 only pays $10 revenue when a mortgage is outstanding.
        # Interest on the outstanding mortgage is collected at the start of each OR.
        def payout_companies(ignore: [])
          sb_ignore = southern_bank? && @southern_bank_mortgage.nil? ? ['P6'] : []
          super(ignore: ignore + sb_ignore)
          pay_southern_bank_interest if southern_bank? && @southern_bank_mortgage
        end

        def pay_southern_bank_interest
          mortgage = @southern_bank_mortgage
          corp     = mortgage[:corp]
          interest = (mortgage[:value] * 0.10).ceil
          p6_owner = southern_bank_company.owner
          return unless p6_owner&.player?

          if corp.cash >= interest
            corp.spend(interest, p6_owner)
            @log << "#{corp.name} pays #{format_currency(interest)} Southern Bank interest to #{p6_owner.name}"
          else
            @log << "#{corp.name} cannot pay Southern Bank interest of #{format_currency(interest)}"
          end
        end

        def no_mergers_variant?
          @optional_rules&.include?(:no_mergers)
        end

        def game_end_check_values
          @optional_rules&.include?(:finish_on_400) ? self.class::VARIANT_GAME_END_CHECK : self.class::GAME_END_CHECK
        end

        def init_starting_cash(players, bank)
          cash = southern_bank? ? self.class::SOUTHERN_BANK_STARTING_CASH : self.class::STARTING_CASH
          players.each do |player|
            bank.spend(cash[players.size], player)
          end
        end

        def next_round!
          @round =
            case @round
            when Engine::Round::Stock
              @operating_rounds = @phase.operating_rounds
              reorder_players
              if mergers_allowed? && !no_mergers_variant?
                new_merger_round
              else
                new_operating_round
              end
            when G1832::Round::Merger
              if @merger_after_or_set
                @merger_after_or_set = false
                @turn += 1
                or_set_finished
                new_stock_round
              else
                new_operating_round
              end
            when Engine::Round::Operating
              if @final_merger_triggered
                @final_merger_triggered = false
                or_round_finished
                @merger_after_or_set = true
                new_merger_round
              elsif @round.round_num < @operating_rounds
                or_round_finished
                new_operating_round(@round.round_num + 1)
              else
                @turn += 1
                or_round_finished
                or_set_finished
                new_stock_round
              end
            when init_round.class
              init_round_finished
              reorder_players
              new_stock_round
            end
        end

        def new_merger_round
          @log << "-- #{round_description('Merger and Takeover')} --"
          G1832::Round::Merger.new(self, [
            G1832::Step::Merge,
            G1832::Step::SellSharesForTakeover,
            Engine::Step::DiscardTrain,
          ])
        end

        def merge_corporations
          @corporations.select { |c| c.type != :system && c.floated? }
        end

        def london_company
          @london_company ||= company_by_id('P4')
        end

        # §11.6.7: Systems hold twice the normal train limit.
        def train_limit(entity)
          super * (system?(entity) ? 2 : 1)
        end

        def southern_bank_company
          @southern_bank_company ||= company_by_id('P6')
        end

        def central_rr_company
          @central_rr_company ||= company_by_id('P7')
        end

        def fec_corporation
          @fec_corporation ||= corporation_by_id('FECR')
        end

        def cog_corporation
          @cog_corporation ||= corporation_by_id('CG')
        end

        # ── Merger helpers ────────────────────────────────────────────

        def available_systems
          @corporations.select { |c| c.type == :system && !c.floated? }
        end

        # True if any player holds ≥40% combined across both corporations.
        def can_form_system?(corp1, corp2)
          return false if available_systems.empty?

          @players.any? do |p|
            p.shares_of(corp1).sum(&:percent) + p.shares_of(corp2).sum(&:percent) >= 40
          end
        end

        # BFS-based connectivity: are corp_a and corp_b reachable from each other via laid track?
        # Iterative to avoid JS call-stack overflow from the recursive Graph walk on large boards.
        def corps_connected?(corp_a, corp_b)
          hexes_b = network_hexes(corp_b)
          return false if hexes_b.empty?

          hexes_a = network_hexes(corp_a)
          return false if hexes_a.empty?

          # Hash for O(1) membership test — avoid to_set (requires 'set' in Opal)
          hexes_b_lookup = hexes_b.each_with_object({}) { |h, acc| acc[h] = true }

          visited = {}
          queue = hexes_a
          until queue.empty?
            hex = queue.shift
            next if visited[hex]

            visited[hex] = true
            return true if hexes_b_lookup.key?(hex)

            hex.neighbors.each do |edge, neighbor|
              next if visited[neighbor]
              next unless hex.tile.paths.any? { |p| p.exits.include?(edge) } &&
                          neighbor.tile.paths.any? { |p| p.exits.include?(hex.invert(edge)) }

              queue << neighbor
            end
          end
          false
        end

        private

        # Returns an Array of hexes forming corp's network: placed-token hexes,
        # or home hex(es) if no tokens are on the map yet.
        # Uses only Array/Hash — no filter_map or to_set (not reliably in Opal).
        def network_hexes(corp)
          placed = corp.placed_tokens.map(&:hex).compact.uniq
          return placed unless placed.empty?

          Array(corp.coordinates).map { |coord| hex_by_id(coord) }.compact
        end

        public

        def takeover_cost(target)
          target_par = target.par_price&.price || target.share_price.price
          target_mkt = target.share_price.price
          cost = 0
          target.shares.select { |s| s.owner == target }.each do |s|
            cost += (s.percent.to_f / 10 * target_par).round
          end
          @share_pool.shares_of(target).each do |s|
            cost += (s.percent.to_f / 10 * target_mkt).round
          end
          @players.each do |player|
            player.shares_of(target).each do |s|
              cost += (s.percent.to_f / 10 * target_mkt).round
            end
          end
          cost
        end

        def bundles_for_corporation(share_holder, corporation, shares: nil)
          shares ||= share_holder.shares_of(corporation)
          shares = shares.reject { |s| s == @p4_share }
          super(share_holder, corporation, shares: shares)
        end

        def can_afford_takeover?(buyer, target)
          president = buyer.owner
          cost = takeover_cost(target)
          # Compute president's max liquidity directly: avoids sellable_bundles →
          # active_step recursion that occurs during merger-round blocking? checks.
          president_liquidity = president.cash + president.shares.sum do |s|
            next 0 unless (price = s.corporation.share_price&.price)
            (s.percent.to_f / 10.0 * price).floor
          end
          buyer.cash + president_liquidity >= cost
        end

        # ── System formation (§11.6) ──────────────────────────────────

        def perform_system_formation(corp1, corp2, system)
          @log << "#{corp1.name} and #{corp2.name} form #{system.name}"

          # 1. Set par & share price (average of two, rounded to nearest, capped at $275 per §11.6.3)
          # TODO(beta): implement full diagonal-placement algorithm per §11.6.3
          avg = [(corp1.share_price.price + corp2.share_price.price) / 2.0, 275].min
          all_prices = stock_market.market.flatten.compact.map(&:price).sort.uniq
          nearest = all_prices.min_by { |p| [(p - avg).abs, -p] }
          new_sp = stock_market.market.flatten.compact.find { |sp| sp.price == nearest }
          raise GameError, 'Cannot determine system share price' unless new_sp

          stock_market.set_par(system, new_sp)
          system.ipoed = true

          # 2. Convert both component president certs into 10% VP certs of the system.
          # Each stays with whoever held the component presidency.
          vp_certs = []
          [corp1, corp2].each do |corp|
            holder = corp.share_holders.keys.find { |h| h.player? && h.shares_of(corp).any?(&:president) }
            next unless holder

            share = holder.shares_of(corp).find(&:president)
            holder.shares_by_corporation[corp].delete(share)
            corp.share_holders[holder] -= share.percent

            share.percent /= 2 # 20% → 10%
            share.instance_variable_set(:@corporation, system)
            share.instance_variable_set(:@president, false)

            system.share_holders[holder] += share.percent
            holder.shares_by_corporation[system] << share

            vp_certs << share
            (@vice_president_certs[system] ||= []) << share
            @log << "#{holder.name} receives VP certificate (10%) in #{system.name}"
          end

          # 3. Exchange all remaining outstanding component shares 1:1 for system 5% shares
          system_reg = system.shares.reject(&:president).select { |s| s.owner == system }
          @log << "There are #{system_reg.count} system shares available"
          sys_idx = 0
          [corp1, corp2].each do |corp|
            corp.share_holders.dup.each do |holder, _|
              next if holder == corp

              holder.shares_of(corp).dup.each do |share|
                next if vp_certs.include?(share)
                next unless sys_idx < system_reg.size

                share.transfer(@bank)
                @log << "#{holder.name} receives a regular #{system_reg[sys_idx].percent}% share in exchange for a component one"
                system_reg[sys_idx].transfer(holder)
                sys_idx += 1
              end
            end
          end

          # 4. President = player holding the largest system share percentage
          system.owner = @players.max_by { |p| p.percent_of(system) }
          @log << "#{system.owner.name} is the system owner with #{system.owner.percent_of(system)}%"
          president = system.owner

          # 5. Form the 20% president cert: president surrenders VP certs first, then regular
          # shares, until 20% is covered. Surrendered shares go to the bank.
          system_pres = system.shares.find(&:president)
          pct_needed = system_pres.percent
          to_surrender = []

          vp_certs.select { |v| v.owner == president }.each do |vp|
            break unless pct_needed.positive?

            to_surrender << vp
            pct_needed -= vp.percent
            @log << "#{vp.owner.name} is surrendering a VP cert and needs to surrender an additional #{pct_needed}%"
          end

          if pct_needed.positive?
            president.shares_of(system).reject(&:president).sort_by(&:percent).each do |share|
              break unless pct_needed.positive?

              to_surrender << share
              pct_needed -= share.percent
              @log << "#{share.owner.name} surrenders a #{share.percent}% cert; #{pct_needed}% still needed"
            end
          end

          to_surrender.each { |s| s.transfer(@bank) }
          system_pres.transfer(president)

          @log << "#{president.name} becomes president of #{system.name}"

          # 6. Transfer cash, trains, companies to system
          [corp1, corp2].each do |comp|
            comp.spend(comp.cash, system) if comp.cash.positive?
            transfer(:trains, comp, system)
            transfer(:companies, comp, system)
          end

          # 7. Handle coal tokens
          coal_count = [corp1.coal_token, corp2.coal_token].count(&:itself)
          case coal_count
          when 2
            @coal_token_counter += 1
            system.coal_token = true
            @log << "#{system.name} has duplicate Coal tokens; one returned. #{@coal_token_counter} Coal tokens remaining."
          when 1
            system.coal_token = true
          end

          # 8. Replace map tokens (remove duplicates, assign remainder to system)
          system_merge_tokens(corp1, corp2, system)

          # 9. Close component companies (force_next_entity! suppressed in merger round)
          system.system_shells = [corp1.id, corp2.id]
          [corp1, corp2].each { |corp| close_corporation(corp) }

          system.floated = true
          clear_token_graph_for_entity(system)
          @log << "#{system.name} formed at #{format_currency(new_sp.price)}"
        end

        def system_merge_tokens(comp1, comp2, system)
          placed_cities = {}
          [comp1, comp2].each do |comp|
            comp.tokens.select(&:city).each do |token|
              city = token.city
              if placed_cities.key?(city)
                token.remove!
                system.tokens << Engine::Token.new(system, price: 100)
                @log << "Duplicate token in #{city.hex.id} returned to #{system.name}'s charter"
              else
                placed_cities[city] = true
                new_tok = system.next_token
                new_tok ||= Engine::Token.new(system, price: 100).tap { |t| system.tokens << t }
                token.remove!
                city.place_token(system, new_tok, check_tokenable: false)
              end
            end
          end
        end

        # ── Takeover (§11.7) ─────────────────────────────────────────

        def perform_takeover(buyer, target)
          @log << "#{buyer.name} takes over #{target.name}"

          target_mkt = target.share_price.price
          total_cost = takeover_cost(target)

          # Build player payment map (needed to pay players their market price)
          player_payments = Hash.new(0)
          @players.each do |player|
            player.shares_of(target).each do |s|
              player_payments[player] += (s.percent.to_f / 10 * target_mkt).round
            end
          end

          # President contributes cash if buyer can't cover the full cost
          if buyer.cash < total_cost
            needed    = total_cost - buyer.cash
            president = buyer.owner
            if president.cash < needed
              raise GameError, "#{president.name} cannot fund the takeover (needs #{format_currency(needed)})"
            end

            president.spend(needed, buyer)
            @log << "#{president.name} contributes #{format_currency(needed)} to fund takeover"
          end

          # Pay players for their shares
          player_payments.each do |player, amount|
            buyer.spend(amount, player) if amount.positive?
          end

          # Remainder goes to bank (pool + IPO shares)
          bank_cost = total_cost - player_payments.values.sum
          buyer.spend(bank_cost, @bank) if bank_cost.positive?

          @log << "#{buyer.name} pays #{format_currency(total_cost)} to acquire #{target.name}"

          # Transfer assets
          target.spend(target.cash, buyer) if target.cash.positive?
          transfer(:trains, target, buyer)
          transfer(:companies, target, buyer)

          # Handle coal tokens
          if buyer.coal_token && target.coal_token
            @coal_token_counter += 1
            @log << "Duplicate Coal token returned. #{@coal_token_counter} Coal tokens remaining."
          elsif target.coal_token
            buyer.coal_token = true
          end

          # Replace map tokens (remove duplicates)
          buyer_cities = buyer.tokens.select(&:city).each_with_object({}) { |t, h| h[t.city] = true }
          target.tokens.select(&:city).each do |token|
            city = token.city
            if buyer_cities.key?(city)
              token.remove!
              @log << "Duplicate token in #{city.hex.id} removed; may be re-placed for $100"
            else
              buyer_cities[city] = true
              new_tok = buyer.next_token
              new_tok ||= Engine::Token.new(buyer, price: 100).tap { |t| buyer.tokens << t }
              token.remove!
              city.place_token(buyer, new_tok, check_tokenable: false)
            end
          end

          close_corporation(target)
          # §11.7: cert limit moves one column right per shell removed.
          # close_corporation already applied one step; systems (2 shells) need a second.
          tighten_cert_limit_by_one if system?(target)
          clear_token_graph_for_entity(buyer)
        end

        # Tighten the cert limit as if one additional corporation had been removed,
        # without actually removing anything from @corporations.
        def tighten_cert_limit_by_one
          player_count = @players.size
          limit_table = self.class::CERT_LIMIT[player_count]
          return unless limit_table.is_a?(Hash)

          virtual_size = @corporations.size - 1
          tighter = limit_table.reject { |k, _| k.to_i < virtual_size }.min_by(&:first)&.last
          @cert_limit = tighter if tighter
        end
      end
    end
  end
end
