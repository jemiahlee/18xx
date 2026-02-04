# 1832: The South — Implementation Plan

## Overview

1832 is a merger-focused 18xx game by W. R. Dixon set in the American South. It shares its
stock market, share redemption/reissue, price protection, half-dividend, and train progression
mechanics with **1870** and **1850** (also by Dixon). Steps and rounds from those games should
be reused or subclassed directly wherever the rules match.

The major new mechanics requiring original implementation are:
- A modified Initial Stock Round (waterfall auction with a price-reducing P1 and a CoG-linked P7)
- System Formation mergers (two 10-share companies → one 20-share company)
- Takeover mergers (one company buys all shares of another)
- A Merger Round inserted between Stock and Operating rounds in phases 4–5
- A special mid-OR Merger Round triggered by the first 6-train purchase
- The West Virginia Coal Fields grey hex (analogous to the Mesabi Range in 1850)
- The Key West Token (FEC only, phases 3–7, adds $50 to Miami)
- Cotton (P2) and Port (P3) tokens placed as an extra token lay
- The London Investment Company (P4), which lets its owner buy one share in any newly started company
- The variable certificate limit that decreases when companies are absorbed in takeovers

---

## File Listing

```
lib/engine/game/g_1832/
  meta.rb
  entities.rb
  map.rb
  corporation.rb
  game.rb
  round/
    merger.rb
    operating.rb         (only if needed beyond 1870's)
  step/
    buy_sell_par_shares.rb
    price_protection.rb
    buy_train.rb
    dividend.rb
    buy_company.rb
    track.rb
    token.rb
    initial_auction.rb
    company_pending_par.rb
    merger.rb

spec/lib/engine/game/g_1832/
  game_spec.rb

public/fixtures/1832/
  (fixture JSON files added as implementation is validated)

public/logos/1832/
  AWP.svg, ACL.svg, CoG.svg, FEC.svg, GRR.svg, GMO.svg, LN.svg, NW.svg, SAL.svg, Sou.svg
  (plus .alt simple versions)

public/icons/1832/
  wvcf.svg        (West Virginia Coal Fields token icon)
  cotton.svg      (Cotton Warehouse token icon)
  port.svg        (Atlantic Shipping port token icon)
  port_closed.svg (closed port token icon, if needed)
```

---

## Step 1: `lib/engine/game/g_1832/meta.rb`

Standard metadata module, no code reuse needed.

```
include Game::Meta

DEV_STAGE = :prealpha
GAME_TITLE = '1832'
GAME_SUBTITLE = 'The South'
GAME_DESIGNER = 'W. R. Dixon'
GAME_IMPLEMENTER = (your name)
GAME_LOCATION = 'The American South'
GAME_PUBLISHER = :deep_thought_games
GAME_RULES_URL = (URL to rules PDF if publicly available)
GAME_INFO_URL = 'https://github.com/tobymao/18xx/wiki/1832'

PLAYER_RANGE = [2, 6].freeze
```

Define optional rules as constants (none enabled by default):
- `:finish_on_400` — game ends immediately when any share price reaches $400 (rules §17.1)
- `:diesels` — 8- and 10-trains replaced by 1830-style Diesel trains; 12-trains available after
  first 6-train; 5-trains are permanent; trade-in credit of $300 against Diesel (rules §17.2)
- `:southern_bank` — enables P6 (Southern Bank private company) and increases starting capital
  to $2400 (rules §17.3)
- `:historical_order` — companies must start in historical order (rules §17.4)
- `:no_mergers` — disables all merger rules (rules §17.6)

Note: The Civil War variant (§17.5) is marked as "not extensively tested" in the rules and may
be omitted from the initial implementation.

---

## Step 2: `lib/engine/game/g_1832/corporation.rb`

Subclass `Engine::Corporation`. Add instance attributes needed to track game-specific state.

```ruby
class Corporation < Engine::Corporation
  attr_accessor :wvcf_token,       # true if this corp has bought WVCF access
                :cotton_token,     # true if this corp's Cotton token has been placed
                :port_token,       # true if this corp's Port token has been placed
                :key_west_placed,  # true if FEC's Key West token has been placed
                :system_shells,    # array of absorbed corporation syms (for takeover tracking)
                :system_id,        # symbol :A–:E if this corp is or has become a System
                :operated_once     # true after first operating round (merger eligibility)
end
```

`system_shells` is used for takeovers: each absorbed company adds its shell sym to the
buyer's list, which decreases the certificate limit (one column right per shell, §11.7).

---

## Step 3: `lib/engine/game/g_1832/entities.rb`

Define `COMPANIES` and `CORPORATIONS` arrays.

### COMPANIES

**P1 — Carolina Stage Coach Company**
- `value: 20, revenue: 5, sym: 'CSC'`
- No abilities
- `min_price` starts at value; the ISR step reduces it by $5 when all players pass before P7 is sold

**P2 — Cotton Warehouse**
- `value: 40, revenue: 10, sym: 'CW'`
- Ability type `assign_hexes` with `owner_type: 'corporation'`, `when: 'owning_corp_or_turn'`,
  `count: 1`, targeting all non-coastal (non-Atlantic, non-Gulf) city hexes
- Ability type `assign_corporation` with `when: 'sold'`, `count: 1`
- The assign_hexes ability places the cotton token during the owning corp's token step (see Step 9)
- Revenue +$10 to owning company only in that city
- Token placed on yellow/green Atlanta must specify one of Atlanta's three city slots
- Company closes at first 5-train purchase; token not removed until first 6-train

**P3 — Atlantic Shipping Company**
- `value: 50, revenue: 10, sym: 'ASC'`
- Same ability structure as P2 but targeting coastal city hexes (those marked with an anchor on the map)
- Port token: +$20 for owning company, +$10 for any other company running through that city
- Needs two separate icon/assignment states (open port, closed port) for the UI
- Closes at first 5-train; token not removed until first 6-train

**P4 — London Investment Company**
- `value: 70, revenue: 10, sym: 'LIC'`
- Custom ability: during the ISR (only), after any company is floated with its president's
  share purchased this stock round, the P4 owner may buy one share in that company for par
  price as part of the ISR phase (counts as a stock action for priority purposes)
- Cannot be sold to a public company
- Closes after the company that P4 was used on pays its first dividend (see game.rb events)
- Cannot be sold between players after using it to acquire a share (mark ability as used)
- Implementation: track this with a custom boolean on the company. The ISR step checks for the
  ability after each new company is started.

**P5 — West Virginia Coal Fields**
- `value: 80, revenue: 15, sym: 'WVCF'`
- Owning corporation receives a free WVCF token (set `corp.wvcf_token = true` in `after_sell_company`)
- When other corps connect and buy WVCF access for $80: $40 goes to P5 owner's corp treasury
  (or bank if P5 is closed), $40 goes to bank
- Phase 2: `max_price = value` (half to full); phases 3–4: `max_price = 2 * value` (half to double)
- Closes at first 5-train; WVCF access rights persist for token-holding corps
- No corp may connect to WVCF hex until P5 has been sold to a corp or closed by first 5-train
- Five WVCF tokens total; at most one per corporation (excess from merger returned immediately)
- Implementation is closely analogous to the Mesabi Range in 1850 (`G1850::Corporation#mesabi_token`,
  `G1850::Step::Track#buy_mesabi_token`, `G1850::Game#after_sell_company` etc.). Reuse and adapt
  that pattern.

**P6 — Southern Bank** *(only in play with `:southern_bank` optional rule)*
- `value: 100, revenue: 10, sym: 'SB'`
- Complex mortgage mechanic: P6 owner can mortgage a train or placed token the owner's
  company holds; sets mortgage value (half to double asset value); company pays 10% interest
  per OR at start of operating; if no cash, pays nothing; company can repay mortgage for half
  to full asset value; only one mortgage outstanding at a time
- Does not close at first 5-train (unique); does not pay $10 revenue if no outstanding mortgage
- Cannot be sold to a public company or between players after first 6-train
- Worth face value ($100) at game end
- Does not count against certificate limit while mortgage is outstanding
- Starting capital increases to $2400 / num_players when this private is in play
- Implementation: This is the most mechanically complex private; consider deferring to a
  separate phase of implementation. Track mortgage state (`mortgaged_asset`, `mortgage_value`)
  on the P6 company object.

**P7 — Central Rail Road and Canal Company**
- `value: 200, revenue: 30, sym: 'CRRCC'`
- Ability type `shares` pointing to the CoG president's certificate (`'CoG_0'`)
- Purchasing player must immediately set the CoG par value (uses `CompanyPendingPar` pattern —
  see Step 12 and the 1870 `Step::CompanyPendingPar` which should be subclassed)
- P7 closes when CoG buys its first train OR at first 5-train purchase, whichever is earlier
- Cannot be sold to a public company; included in ISR waterfall
- This is directly analogous to 1870's Mississippi & Missouri Railroad private (sym `'MMR'`)
  which comes with a RI share and closes after payment of first dividend. The key difference is
  that the CoG must set par value immediately on purchase. Subclass `G1870::Step::CompanyPendingPar`.

### CORPORATIONS

Ten corporations with `float_percent: 60` (floats at 6 of 10 shares sold):

| sym  | name                                | start          | tokens               | color       |
|------|-------------------------------------|----------------|----------------------|-------------|
| AWP  | Atlanta & West Point Railroad       | Atlanta (hex)  | 2 (home free, $100)  | TBD         |
| ACL  | Atlantic Coast Line Railroad        | Charleston     | 3 (home, $40, $100)  | TBD         |
| CoG  | Central of Georgia Railway          | Savannah       | 3 (home, $40, $100)  | TBD         |
| FEC  | Florida East Coast Railway          | Jacksonville   | 2 + Key West token   | TBD         |
| GRR  | Georgia Railroad                    | Atlanta (hex)  | 2 (home free, $100)  | TBD         |
| GMO  | Gulf, Mobile & Ohio Railroad        | New Orleans    | 3 (home, $40, $100)  | TBD         |
| LN   | Louisville & Nashville Railroad     | Nashville      | 3 (home, $40, $100)  | TBD         |
| NW   | Norfolk & Western Railway           | Norfolk        | 3 (home, $40, $100)  | TBD         |
| SAL  | Seaboard Air Line Railway           | Raleigh        | 3 (home, $40, $100)  | TBD         |
| Sou  | Southern Railway                    | Knoxville      | 3 (home, $40, $100)  | TBD         |

Notes:
- AWP and GRR both start in Atlanta; each gets their own city slot. When both are on the same
  tile (Atlanta's green/yellow upgrade has multiple city circles), each occupies a distinct slot.
  If a merger results in two tokens in the same city, one is discarded (§7.3.3 / §11.6.5).
- FEC has a `key_west_token` ability (type `assign_hexes`, targeting Miami hex, count 1, cost 0)
  representing the Key West Token placement (phases 3–7 only). See Step 9.
- Token costs per corporation: home token is always free; remaining tokens cost as listed.
  Verify against the physical game components — typical for this era is $40/$100 or $40/$40/$100.
- For Systems (§11.6): pre-create five inert `system_corporation` objects labeled System A–E in
  `setup` but kept off the market. When a System is formed, one is assigned as the System's
  representation. See Step 13 (merger) for details.

---

## Step 4: `lib/engine/game/g_1832/map.rb`

Define `LAYOUT`, `TILES`, and `HEXES`.

**Layout:** The map uses a flat (`:flat`) hex layout.

**Tile counts:** Determine from the tile manifest (rules §23). The standard tile set overlaps
heavily with 1870 and 1850. Special tiles needed:
- `'190'` — Atlanta green upgrade (2-city, special track, game-specific)
- `'191'` — Atlanta brown upgrade (game-specific)
- `'193'` — Savannah brown upgrade (game-specific)
- `'611'` — Charleston/Jacksonville brown upgrade (shared with some other games; verify)
- Medium city marker tiles: the map uses a circle-with-dot symbol for medium cities (§6.4.2);
  these initially receive yellow town tiles (#3, #4, #58) with an extra icon/marker to show
  medium city status. The marker is removed when the tile is upgraded.

**Hex definitions:** Transcribe from the physical map. Each hex entry needs:
- Coordinates (the 1832 map likely uses a standard A–Z/number coordinate system)
- Preprinted tile (cities, towns, offboards, terrain, grey hexes)
- Terrain costs for mountain/water hexes (shown as `$XX` on the map)
- Location names for cities/towns/offboards
- Border impassability where applicable (the solid blue line south of Tallahassee in the Gulf)
- Red offboard hexes with phase-dependent revenue values (two values: one for phases 2–5,
  one for phases 6+, per rules §4.2.4 and §4.2.5)

**Special hexes:**
- **West Virginia Coal Fields**: A grey hex (preprinted, never replaced with a tile).
  Mark it as accessible only to corporations with a WVCF token (enforced in `check_distance`
  analogous to Mesabi in 1850). Revenue per the physical map components.
- **Miami (AA28 or equivalent)**: A grey city preprinted. Needs phase-dependent value tracking
  (see Step 5, `game.rb` `revenue_for` and `miami_used` flag).
- **Atlanta**: Has multiple city slots (2 cities in the same hex); green and brown upgrades
  use game-specific tiles `'190'` (green) and `'191'` (brown).
- **Medium cities**: Mark with a custom hex attribute or use a preprinted tile containing a
  `label` or icon to indicate medium city status. The upgrade path is: yellow town tile
  (with medium marker icon) → either yellow city tile (#5, #6, #57) OR green town tile
  (#141–#144). After that first upgrade, the marker is gone and normal upgrade rules apply.
  Implement the medium city choice in `track.rb` (Step 8).

**Key West:** Key West is an off-map destination, not a hex on the map. The Key West Token
is placed in Miami (the Miami hex), not in a separate hex. See Step 9.

---

## Step 5: `lib/engine/game/g_1832/game.rb`

Inherit from `Game::Base`. Require all local files plus 1870 steps as needed.

### Constants

```ruby
CORPORATION_CLASS = G1832::Corporation
CURRENCY_FORMAT_STR = '$%s'
BANK_CASH = 12_000
CAPITALIZATION = :full
MUST_SELL_IN_BLOCKS = true
FLOAT_PERCENT = 60   # or set per-corporation in entities.rb
CORPORATE_BUY_SHARE_ALLOW_BUY_FROM_PRESIDENT = true
MULTIPLE_BUY_ONLY_FROM_MARKET = true
EBUY_OTHER_VALUE = false
IPO_RESERVED_NAME = 'Treasury'
```

**Starting cash** (§3.3): `$2100 / num_players`, same formula as 1850/1870.
With `:southern_bank` variant: `$2400 / num_players`.
```ruby
STARTING_CASH = { 2 => 1050, 3 => 700, 4 => 525, 5 => 420, 6 => 350 }.freeze
SOUTHERN_BANK_STARTING_CASH = { 2 => 1200, 3 => 800, 4 => 600, 5 => 480, 6 => 400 }.freeze
```

**Certificate limits** (§5.4.1 and §21): Variable by player count and number of companies
still in play. The rules include a table on the physical map. The 2D hash format used in
1870 and 1850 (`{ player_count => { company_count => limit } }`) is the right approach.
Populate from the rules table in §21 for 2–6 players × 10–some-reduced count companies.
When a Takeover occurs, the cert limit table shrinks (one column to the right per shell
absorbed, §11.7). Implement `cert_limit` to look up the table keyed by current active
corporation/shell count.

**Phases:**
```ruby
PHASES = [
  { name: '2', train_limit: 4, tiles: [:yellow], operating_rounds: 1 },
  { name: '3', on: '3', train_limit: 4, tiles: %i[yellow green],
    operating_rounds: 2, status: %w[can_buy_companies] },
  { name: '4', on: '4', train_limit: 3, tiles: %i[yellow green],
    operating_rounds: 2, status: %w[can_buy_companies mergers_allowed] },
  { name: '5', on: '5', train_limit: 2, tiles: %i[yellow green brown],
    operating_rounds: 3, status: %w[mergers_allowed] },
  { name: '6', on: '6', train_limit: 2, tiles: %i[yellow green brown],
    operating_rounds: 3 },
  { name: '8', on: '8', train_limit: 2, tiles: %i[yellow green brown],
    operating_rounds: 3 },
  { name: '10', on: '10', train_limit: 2, tiles: %i[yellow green brown],
    operating_rounds: 3 },
  { name: '12', on: '12', train_limit: 2, tiles: %i[yellow green brown],
    operating_rounds: 3 },
]
```

**Trains:**
```ruby
TRAINS = [
  { name: '2',  distance: 2,  price: 80,   rusts_on: '4',  num: 7 },
  { name: '3',  distance: 3,  price: 180,  rusts_on: '6',  num: 6,
    events: [{ 'type' => 'companies_buyable' }] },
  { name: '4',  distance: 4,  price: 300,  rusts_on: '8',  num: 4,
    events: [{ 'type' => 'rust_2' }] },   # also triggers mergers allowed (handled via phase)
  { name: '5',  distance: 5,  price: 450,  rusts_on: '12', num: 3,
    events: [{ 'type' => 'close_companies' }] },
  { name: '6',  distance: 6,  price: 630,              num: 3,
    events: [{ 'type' => 'final_merger_chance' }, { 'type' => 'close_privates_tokens' }] },
  { name: '8',  distance: 8,  price: 800,  rusts_on: nil, num: 3,
    events: [{ 'type' => 'rust_4' }, { 'type' => 'remove_key_west' }] },
  { name: '10', distance: 10, price: 950,              num: 2 },
  { name: '12', distance: 12, price: 1100,             num: 99 },  # unlimited
]
```

Note on train events:
- `close_companies` (first 5-train): all privates except P6 (Southern Bank variant) close
- `close_privates_tokens` (first 6-train): Cotton and Port tokens are removed from the map
- `final_merger_chance` (first 6-train): triggers the special mid-OR merger phase after the
  current company finishes its operating round (§4.2.5 / §11.1)
- `remove_key_west` (first 8-train): Key West token is removed from play
- `rust_4` (first 8-train): 4-trains rust
- 3-trains rust on first 6-train (`rusts_on: '6'`)
- 2-trains rust on first 4-train (`rusts_on: '4'`)
- 5-trains rust on first 12-train (`rusts_on: '12'`)

Also support the `:diesels` variant trains (same as 1870 `DIESEL_VARIANT_TRAINS` but adapted
to the 1832 train set — 8 and 10 trains are removed, 12-trains become Diesels with $300
trade-in credit).

**Stock market:**
```ruby
MARKET = [
  # Same grid as 1850/1870 — the original 1832 market
  # 1870's meta.rb explicitly notes the original_market option is "identical to the
  # market in 1832 and 1850"
  # Copy MARKET constant verbatim from G1850::Game::MARKET
]
```

Use `G1870::StockMarket` (which implements the soft ledge / right-ledge logic). No new
stock market subclass is needed.

```ruby
def init_stock_market
  G1870::StockMarket.new(self.class::MARKET, self.class::CERT_LIMIT_TYPES,
                         multiple_buy_types: self.class::MULTIPLE_BUY_TYPES)
end
```

**Par values** (§5.6): Only the six red-outlined values may be used when starting a new
company: $68, $72, $76, $82, $90, $100. Enforce this in `init_stock_market` by only
marking those cells as `:par` type. The remaining white cells are valid for reissue.

**`setup` method:**
```ruby
def setup
  @sell_queue = []          # for price protection (same as 1870)
  @reissued = {}             # for share reissue tracking (same as 1870)
  @wvcf_token_counter = 4   # starts at 4; P5 purchase gives 1 free, leaving 4 buyable
  @miami_first_run = false   # set to true when any corp first runs to Miami
  @p5_sold_or_closed = false # gates WVCF token purchases

  # Set max_price for phase-restricted companies
  wvcf_company.max_price = wvcf_company.value   # P5: half-to-full in phase 2

  # Handle `:southern_bank` optional rule (P6)
  southern_bank_company.close! unless southern_bank?

  # Set aside CoG president's certificate with P7
  # (handled in entities.rb via `shares` ability on P7)
end
```

**`event_companies_buyable!`:** Set `wvcf_company.max_price = 2 * wvcf_company.value` (phase 3+)

**`event_close_companies!`:** Close all privates except P6 (if Southern Bank variant). Log the event.

**`event_close_privates_tokens!`:** Remove Cotton and Port tokens from the map. Log removals.

**`event_final_merger_chance!`:** Set a flag `@final_merger_triggered = true`. The merger round
will be inserted after the current operating company finishes (see `next_round!`).

**`event_remove_key_west!`:** Mark `@key_west_removed = true`; if FEC's Key West token is placed,
remove it from Miami and log the removal.

**`event_rust_4!`:** Handled automatically by the train system (rusts_on: '8'), but may need a
log message.

**`after_sell_company(buyer, company, price, seller)`:** If company is P5 (WVCF):
- Set `buyer.wvcf_token = true`
- Decrement `@wvcf_token_counter` (buyer got the free token)
- Set `@p5_sold_or_closed = true`
- Log token acquisition and remaining count

**`purchasable_companies(entity)`:**
- In phase 2: only P5 is purchasable (at half-to-full face), and P4 (at half-to-double since
  it has no phase 2 restriction noted — but verify against rules); P2 and P3 cannot be bought
  by corps until phase 3. Per rules §4.1.3 and §12: P5 may be bought in phase 2, others
  require phase 3+. P4 and P7 may never be bought by a corp.
- Return `[]` for P4 and P7 regardless of phase.

**`check_distance(route, visits)`:** If any visit includes the WVCF hex and the route's
corporation does not have `wvcf_token`, raise `GameError`. (Same as Mesabi in 1850.)

**`graph_skip_paths(entity)`:** If entity does not have `wvcf_token`, return WVCF hex paths
in the skip set. (Same as Mesabi in 1850.)

**`revenue_for(route, stops)`:**
- Base revenue via `super`
- Cotton token: if the stop's hex is assigned to the route's corporation (P2 token), add +$10
- Port token: if the stop's hex has a port assignment, add +$20 if assigned to the route's
  corporation, +$10 for all other corporations
- Miami first-run rule: if the stop is Miami and `!@miami_first_run`, revenue for Miami = 0
  for that stop on this route (only the first time any corporation runs to Miami; after that
  run, set `@miami_first_run = true` so subsequent runs use the printed value)
- Key West Token: if the route's corporation is FEC and FEC's Key West token is placed in Miami
  (check `entity.key_west_placed`) and Miami is in the route, add +$50

**`revenue_str(route)`:** Annotate the revenue string if Cotton, Port, or Key West tokens
are contributing.

**`sell_shares_and_change_price`:** Same sell-queue pattern as 1870 and 1850 — queue the
bundle for price protection, defer stock price movement.

**`num_certs(entity, price_protecting: false)`:** Same implementation as 1870 (checks sell
queue, handles price protection cert counting).

**`can_hold_above_corp_limit?(_entity)`:** Return `true` (same as 1870/1850).

**`reissued?(corporation)`:** Return `@reissued[corporation]`.

**`float_corporation(corporation)`:** Track `@recently_floated` list (same as 1850, for
extra tile lay on float).

**`tile_lays(entity)`:** If entity is in `@recently_floated`, allow
`[{ lay: true, upgrade: true }, { lay: :not_if_upgraded, upgrade: false }]` (same as 1850).
For Systems, allow `[{ lay: true, upgrade: true }, { lay: true, upgrade: false },
{ lay: true, upgrade: false }]` — three yellow lays, or one yellow + one upgrade (§11.6.8).

**`operating_round(round_num)`:**
```ruby
def operating_round(round_num)
  Engine::Round::Operating.new(self, [
    Engine::Step::Bankrupt,
    Engine::Step::Exchange,
    G1832::Step::BuyCompany,
    Engine::Step::HomeToken,
    G1832::Step::Track,
    G1832::Step::Token,
    Engine::Step::Route,
    G1832::Step::Dividend,
    Engine::Step::DiscardTrain,
    G1832::Step::BuyTrain,
    [G1832::Step::BuyCompany, { blocks: true }],
    G1832::Step::PriceProtection,
  ], round_num: round_num)
end
```

**`stock_round`:**
```ruby
def stock_round
  G1870::Round::Stock.new(self, [
    Engine::Step::DiscardTrain,
    G1832::Step::BuySellParShares,
    G1832::Step::PriceProtection,
  ])
end
```

**`new_auction_round`:**
```ruby
def new_auction_round
  Engine::Round::Auction.new(self, [
    G1832::Step::CompanyPendingPar,
    G1832::Step::InitialAuction,
  ])
end
```

**`next_round!`:** Override to insert merger rounds at the right times:
```ruby
def next_round!
  @round = case @round
  when Round::Stock
    @operating_rounds = @phase.operating_rounds
    reorder_players
    # Insert merger round after stock round in phases 4 and 5
    if mergers_allowed? && !no_mergers_variant?
      new_merger_round
    else
      new_operating_round
    end
  when G1832::Round::Merger
    new_operating_round
  when Round::Operating
    if @final_merger_triggered
      @final_merger_triggered = false
      # Return to operating round after special merger phase
      # (see final_merger_chance event handling)
      new_final_merger_round
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
```

The `final_merger_chance` event sets `@final_merger_triggered = true` but it must fire
*after* the current operating company completes its OR turn, not mid-turn. Override
`or_round_finished` or use an after-process hook on the OR to check the flag and transition
to the special merger round before continuing remaining OR companies.

Specifically: when the first 6-train event fires, store a flag. At the end of the current
operating company's turn (after `after_process` in the OR), if the flag is set, insert
the final merger round into the round sequence and clear the flag. After the final merger
round completes, resume the OR for remaining companies (or start the next OR if that was
the last company). This is the most complex part of `next_round!` and may require
overriding `Round::Operating#after_process` to redirect to the merger round mid-OR.

**`new_merger_round`:**
```ruby
def new_merger_round
  G1832::Round::Merger.new(self, [G1832::Step::Merger])
end
```

**`mergers_allowed?`:** Return true if phase status includes `'mergers_allowed'`.

**Helper accessors:** `wvcf_company`, `cotton_company`, `port_company`, `london_company`,
`southern_bank_company`, `central_rr_company` (P1–P7 lookups by sym).
Also `fec_corporation`, `cog_corporation` lookups.

**`status_array(corporation)`:** Return `['WVCF Token']` if corporation has WVCF token;
`['Key West Token']` if FEC and key west placed, etc.

**`southern_bank?`:** Check optional rules for `:southern_bank`.

**`no_mergers_variant?`:** Check optional rules for `:no_mergers`.

**`after_buy_train(train, source)`:** Check if P7 should close (CoG bought first train).

---

## Step 6: `lib/engine/game/g_1832/step/buy_sell_par_shares.rb`

**Reuse:** Subclass `G1870::Step::BuySellParShares` directly. Almost everything is identical.

Differences to override:
- `can_sell?(entity, bundle)`: Inherit from 1870 (checks 20% minimum for president hold).
- **Historical order variant**: If `:historical_order` optional rule is active, override
  `can_par?(entity, corp)` to check that all predecessor companies have 6 shares sold from
  initial offering before this one can sell its 6th share. The historical order is defined
  in rules §17.4.
- `issuable_shares` / `issue_par`: Inherit from 1870 verbatim (reissue at 75% of market,
  rounded to nearest par value). 1832 allows reissue up to $200 by default (same as the
  `max_reissue_200?` behavior in 1870). Hard-code this limit in the `issue_par` override
  or set `max_reissue_200? = true` in game.rb.

---

## Step 7: `lib/engine/game/g_1832/step/price_protection.rb`

**Reuse:** Subclass `G1850::Step::PriceProtection` directly. No changes needed — 1850's version
already implements the correct behavior (seller cannot protect their own shares, president of
another company can protect even if they sold shares of that company this round).

---

## Step 8: `lib/engine/game/g_1832/step/buy_train.rb`

**Reuse:** Subclass `G1870::Step::BuyTrain` directly. Inherit as-is — the 20% minimum share
holding check for forced sales carries over correctly.

Additional override needed: **WVCF token purchase eligibility** affects emergency money
calculation. The rules say a president cannot sell redeemed shares to raise train purchase
funds (§10.6). Override `can_sell?` to exclude redeemed shares from the forced-sale list.
(Redeemed shares are already marked as not buyable in 1870; verify they are also excluded
from sellable shares in BuyTrain.)

---

## Step 9: `lib/engine/game/g_1832/step/dividend.rb`

**Reuse:** Subclass `G1870::Step::Dividend` directly. No changes needed — 1870 already
implements full/half/withhold with the correct stock price movement rules (right on full,
left on withhold, no movement on half, no movement if $0 dividend declared).

---

## Step 10: `lib/engine/game/g_1832/step/buy_company.rb`

**Reuse:** Subclass `G1850::Step::BuyCompany`.

Override `can_buy_company?`:
- In phase 2, only P5 is purchasable by corporations (at half-to-full face value)
- P4 and P7 can never be purchased by corporations (check sym, return false)
- P6 (Southern Bank) can never be purchased by corporations
- In phases 3–4, all privates except P4, P7, and P6 are purchasable at half-to-double price

The 1832 rules also allow P5 to be purchased during phase 2, which is more permissive than
1850 where only Mesabi/River companies have phase-2 restrictions. The logic is:
```ruby
def can_buy_company?(entity)
  return false if [p4_sym, p7_sym, p6_sym].include?(currently_up_company&.sym)
  return super if @game.phase.name != '2'
  purchasable = @game.purchasable_companies(entity)
  entity == current_entity && !purchasable.empty? && purchasable.map(&:min_price).min <= entity.cash
end
```

---

## Step 11: `lib/engine/game/g_1832/step/track.rb`

**Reuse:** Subclass `G1850::Step::Track` as the base pattern (for the Mesabi-style token
purchase via `process_choose`).

Add two distinct behaviors:

**A. WVCF Token Purchase** (analogous to Mesabi token in 1850):
- Method `can_buy_wvcf_token?(entity)`: corporation is connected to WVCF hex, does not already
  have a WVCF token, `@game.p5_sold_or_closed` is true, `@game.wvcf_token_counter > 0`,
  entity has at least $80 cash, and there is a remaining tile lay available.
- Method `buy_wvcf_token(corp)`: pay $80 total — $40 to P5 owner (or bank if P5 closed/in corp),
  $40 to bank; set `corp.wvcf_token = true`; decrement counter; log; clear token graph for corp.
- Add `'choose'` to actions when `can_buy_wvcf_token?` and include in `choices`.

**B. Medium City upgrade path** (§6.4.2):
- When laying a tile on a medium city hex (identified by a custom attribute in the hex definition),
  offer a choice if the hex has a yellow town tile already placed:
  upgrade to a yellow city tile (#5, #6, #57) OR to a green town tile (#141, #142, #143, #144)
- Mark the medium city token as removed once the first upgrade is placed
- Override `legal_tile_rotation?` or add validation that medium-city hexes cannot accept
  yellow city tiles in phase 2 (yellow town tiles only in phase 2 per §4.2.1)
- The simplest implementation: the hex map definition marks medium city hexes with a custom
  attribute (e.g., `{ type: :medium_city }`). The track step checks for this attribute when
  determining valid upgrade tiles for those hexes.

---

## Step 12: `lib/engine/game/g_1832/step/token.rb`

**Reuse:** Subclass `Engine::Step::Token`.

Add extra token placement actions for P2 (Cotton) and P3 (Port):

- Method `can_place_cotton_token?(entity)`: entity owns P2, cotton token not yet placed,
  entity is connected to a valid non-coastal city hex via train route.
- Method `can_place_port_token?(entity)`: entity owns P3, port token not yet placed,
  entity is connected to a coastal city hex (anchor symbol on map).
- In `actions`, add `'choose'` and `'pass'` if either token can be placed.
- In `choices`, list available token placement options.
- `process_choose`: if choice is cotton token placement, assign hex to corporation and log;
  if port token, assign hex and log (+$20/$10 revenue effect tracked via `revenue_for`
  in game.rb).
- Token placement counts as the token placement step for that OR; it does not cost a
  station token or station token slot.
- Key West Token (FEC only, phases 3–7): Add a separate choice `'Place Key West Token'`
  available when FEC is the entity, the Key West token has not been placed, the current
  phase is 3 or later (and before 8), and FEC is connected to Miami. Placing it sets
  `entity.key_west_placed = true` and counts as the sole token placement for that OR.
  Token is conceptually placed in Miami — assign the Miami hex to FEC for Key West tracking.

---

## Step 13: `lib/engine/game/g_1832/step/initial_auction.rb`

This implements the modified waterfall auction for the Initial Stock Round (§5.7).

**Reuse:** Subclass `Engine::Step::WaterfallAuction` as the foundation, but override
significantly.

Key differences from a standard waterfall:
1. **No selling allowed** during the ISR (enforce in the round state setup)
2. **P7 (Central Rail Road & Canal Co.) triggers CompanyPendingPar** for CoG when purchased
   (see Step 14)
3. **P1 price reduction**: when all players pass before P7 is sold, one private-only OR runs
   (paying private revenues), then P1's minimum bid decreases by $5. When P1 reaches $0,
   the priority player must take it for free as their only action that turn.
4. **After the last private is sold**, the next player may start a public company per normal
   rules (still within the ISR, no selling permitted)
5. **P4 London Investment Company ability**: after any company is started this turn, the P4
   owner may use P4 to buy one share in the just-started company. This counts as a stock action
   for priority purposes. Track this state in the auction step.

Implementation approach:
- Override `all_passed!` to trigger the "private only OR" and reduce P1's price. Use a counter
  or flag to know whether P7 has been sold yet when deciding if the reduction fires.
- Override `setup` to sort companies by value (P1 first, P7 last).
- Override `process_bid` to handle post-ISR public company starts.
- The special private-only OR is best handled by inserting a minimal OR into the round
  sequence from `all_passed!`. Call `@game.payout_companies` and then `@game.or_set_finished`
  with a special flag to re-enter the auction rather than moving to a full stock round.
  (WaterfallAuction's existing `all_passed!` already does something similar — study carefully.)
- P4 ability: add state to the auction round (`pending_london_investment: nil`). After a
  new company's president's share is bought, if P4 is in a player's hand, set
  `pending_london_investment = company`. The P4 owner can then choose to use P4 or pass it.
  This may be cleanest as a separate small step in the ISR round.

---

## Step 14: `lib/engine/game/g_1832/step/company_pending_par.rb`

**Reuse:** Subclass `G1870::Step::CompanyPendingPar`.

Override `process_par` to:
- Set the CoG par value as chosen
- Call `super` (which closes P7 per 1870's version — but 1832's P7 only closes when CoG
  buys its first train OR at the first 5-train, not immediately on par)
- Therefore **do not** call `company.close!` in the override; instead just set the par and log
- P7 closes via `event_close_companies!` at first 5-train, or via `after_buy_train` when
  CoG buys its first train

---

## Step 15: `lib/engine/game/g_1832/round/merger.rb`

Subclass `Engine::Round::Merger`.

```ruby
class Merger < Engine::Round::Merger
  def self.round_name
    'Merger Round'
  end

  def self.short_name
    'MR'
  end
end
```

The round's entity list is all players, in priority order (the merger initiator is whoever
proposes a merger first in priority order, §11.1).

`select_entities`: Return `@game.players` (all players in priority order).

The `G1832::Step::Merger` step drives the actual negotiation and execution.

The final merger round (triggered by first 6-train) uses the same round class but is
constrained: only mergers where one player is president of both companies are permitted
(§11.1 last paragraph).

---

## Step 16: `lib/engine/game/g_1832/step/merger.rb`

This is the most complex new step. It handles both System Formation and Takeover mergers.

### State tracked in the step:
- `@proposer` — the player making a merger proposal
- `@target` — the corporation being proposed for merger
- `@initiator_corp` — the proposer's corporation (or whichever is acting as initiator)
- `@merger_type` — `:system` or `:takeover` (set by initiator)
- `@pending_proposal` — a pending proposal awaiting the other president's response

### actions(entity):
- If no pending proposal and entity is the current player: `['merge', 'pass']`
- If `@pending_proposal` exists and entity is the other president: `['merge', 'pass']`
  (merge = accept, pass = decline)
- Otherwise: `[]`

### `description`: `'Propose or Accept Merger'`

### `process_merge(action)`:
When the initiator proposes:
- Validate merger eligibility (§11.5):
  - Both companies must have operated at least once
  - Must be in phase 4 or 5 (or the special phase-6 round)
  - For the special phase-6 round: only allowed if one player is president of BOTH companies
  - Companies must be connected (can reach each other with a train of unlimited length, or share a city)
  - Each company may only be involved in one merger of each type
- Set `@pending_proposal` and advance to the other president

When the target president responds:
- If accepting:
  - If initiator chose `:system`: call `form_system`
  - If initiator chose `:takeover`: call `execute_takeover`
- If declining: clear state, continue to next player

### `form_system(corp_a, corp_b)` (§11.6):

**1. Choose a System identifier (A–E)**: Select the first unused system from the pre-created
system entities. Assign the system to these two corporations by setting each corp's `system_id`.

**2. Determine new system president** (§11.6.1):
- The merger initiator (or first player clockwise with 40%+ of both companies) receives the
  System president's certificate in exchange for 40% of the component companies' stock
- The 40% must include any president's certificates from the component companies
- Other players' president's certificates of the component companies remain in play as
  "vice-president's" certificates
- If no single player holds 40%, System Formation is not allowed

**3. Modify share certificates** (§11.6.2):
- Change the `percent` of all non-president shares of both corporations to half their printed value
  (each 10% share → 5% of the system)
- Create a new System president's share with `percent: 20` (representing 4 shares)
- Exchange the 40% (4×10% or 2×20%) from the system president for the new system president cert
- Mark the old president's certificates of component companies as "vice-president" certs if other
  players hold them (they are still bought/sold as a unit)

Implementation note: changing `share.percent` on existing share objects is the most practical
approach within the existing engine. It also requires updating `corp.presidents_share` to
point to the new system president cert.

**4. Calculate new share price** (§11.6.3):
- Average both share prices; round to nearest market value (round up if exactly between two values)
- Place the system's token at the new price, on the same row as the leftmost predecessor's token
- Then move the token diagonally down-right until it hits either the soft ledge or the hard ledge

The diagonal movement is: move right, then down repeatedly until a ledge is hit. Implement
as a helper in this step or in game.rb.

**5. Move component company tokens to Systems Display**: Remove both companies' share price
tokens from the stock market grid. The Systems Display is a UI concern — track the merger
history in game state (`@systems` hash mapping system_id to [corp_a_sym, corp_b_sym]).

**6. Merge assets** (§11.6.5):
- Transfer all trains from both companies into the system (system now operates with combined trains)
- Transfer all cash from both companies
- Transfer all placed tokens (they remain on the map; all are now considered system tokens)
- Transfer private companies owned by each component
- If system now has two WVCF tokens, return one to bank (no compensation); log this
- If two tokens exist in the same city, remove one and return to the system charter for $100 re-placement

**7. System train capacity** (§11.6.7): The system has double the per-shell train limit.
In phase 4/5/6+, each shell can hold 2 trains, so the system can hold 4 total. Track this
by checking `corp.system_id` in `train_limit` — return `2 × phase_train_limit` for Systems.

**8. System par value**: Set the system par value to the new share price (§11.6.3, last paragraph
notes par > $275 is reduced to $275).

**9. Logging**: Log the full merger — companies involved, new share price, president.

**10. Certificate limit**: Cert limit is NOT adjusted for System Formation — each component
company still counts as a shell (§11.6).

### `execute_takeover(buyer, target)` (§11.7):

**1. Validate**: Initiator's corporation buys the other. Player cannot go bankrupt; if they
cannot raise sufficient cash, the merger is not allowed.

**2. Purchase all shares** in this order (§11.7):
- Shares in the initial offering (at par value)
- Shares in the open market (at current market price)
- Shares held by players (at current market price)
- Shares redeemed by the target corporation are considered company assets (not purchased)
- Minority shareholders cannot refuse

**3. Funding the takeover** (§11.7):
- Buyer corporation pays from its treasury
- If insufficient: buyer's president contributes personal cash; may sell stock (not stock in the
  target company) subject to 50% open market limit; cannot go bankrupt in this manner
- If president cannot raise enough, the merger is not allowed

**4. Certificate limit adjustment** (§11.7):
- Move the cert limit table one column to the right per shell in the absorbed company
- A regular 10-share company = 1 shell; a System = 2 shells
- Add the absorbed company's sym(s) to `buyer.system_shells`
- Recalculate and update `@cert_limit` immediately

**5. Transfer assets** (§11.7.1):
- Transfer trains (if buyer now exceeds train limit, president discards excess to open market)
- Transfer money
- Transfer placed map tokens (they remain on the map as buyer's tokens)
- Discard any unplaced tokens from the absorbed company
- If two tokens from both companies are in the same city, remove one, return to charter, $100 to replace
- If two WVCF tokens, return one to bank

**6. Place the target company's par value token** in the buyer's treasury (tracks merged shells).

**7. Buyer corporation type does not change** — a 10-share company stays 10-share; a System stays
a 2-shell System (§11.7.1 last paragraph).

**8. Target corporation**: Remove its share price token from the market. Its shares are now retired.
Log closure.

---

## Step 17: Asset icons

Create SVG icons for:
- `public/icons/1832/wvcf.svg` — West Virginia Coal Fields token (small icon for corporation status)
- `public/icons/1832/cotton.svg` — Cotton token (shown on map hex and corporation status)
- `public/icons/1832/port.svg` — Port token (open)
- `public/icons/1832/port_closed.svg` — Port token (closed, after phase 6 event)

Corporate logos (10 + simple versions) are needed before the game can be rendered in the UI.
These can be placeholder SVGs initially and refined later.

---

## Step 18: `spec/lib/engine/game/g_1832/game_spec.rb`

Write game specs using the fixture-based testing pattern. Initially include tests for:
- Game can be instantiated with 2–6 players
- Starting capital is correct
- Initial auction round starts correctly
- Private companies are in the correct order

As fixtures are added (Step 19), expand to fixture-based tests.

---

## Step 19: `public/fixtures/1832/`

Add fixture JSON files as the implementation progresses. Minimum required before merging:
- One fixture that runs to completion (`status: "finished"`) covering the normal game flow
- A fixture specifically exercising System Formation
- A fixture specifically exercising a Takeover
- A fixture that triggers the special phase-6 merger round

Follow the fixture format described in `public/fixtures/README.md` — ensure the file has
`"status": "finished"`, `"loaded": true`, and `"result"` matching the engine output.
Run `make fixture_format` to normalize.

---

## Implementation Order

Work through files in this sequence to allow testing at each stage:

1. `meta.rb` — establishes the game in the registry
2. `entities.rb` (companies and corporations, abilities as stubs) + `corporation.rb`
3. `map.rb` (full hex map and tile list)
4. `game.rb` (no mergers yet — just phases, trains, market, standard rounds)
5. `step/dividend.rb`, `step/price_protection.rb`, `step/buy_sell_par_shares.rb`,
   `step/buy_train.rb` (all simple subclasses; no new logic)
6. `step/buy_company.rb` (phase restriction logic)
7. `step/company_pending_par.rb` (P7 / CoG par)
8. `step/initial_auction.rb` (ISR logic)
9. First playable fixture — run through ISR + a few rounds; validate cert limit, market movement,
   share redemption/reissue
10. `step/track.rb` (WVCF token + medium city)
11. `step/token.rb` (Cotton, Port, Key West tokens)
12. `corporation/status_array` + icon assets
13. `round/merger.rb` + `step/merger.rb` — System Formation first, then Takeover
14. Integrate merger rounds into `next_round!` in game.rb
15. Special phase-6 merger round event handling
16. Full game fixtures
17. Optional rules (`:diesels`, `:southern_bank`, `:finish_on_400`, `:historical_order`,
    `:no_mergers`)
18. P6 Southern Bank mortgage mechanic (complex; implement last)

---

## Key Differences from 1850/1870 to Watch For

| Feature | 1870/1850 | 1832 |
|---|---|---|
| Train set | 2-3-4-5-6-8-10-12 | Same |
| Phases | 8 | Same count, named by train |
| Floatation | 60% (6 of 10 shares) | Same |
| Market | 1850 original market | Identical to 1850 |
| Stock price movement | Right/left/no-move | Same |
| Soft ledge | Yes | Yes (same) |
| Price protection | Yes | Yes (same as 1850) |
| Share redemption | 1 per SR (2 for System) | Same + System rules |
| Share reissue | Yes | Yes, max $200 |
| Half dividend | Yes | Yes |
| WVCF / Mesabi | Mesabi in 1850 | WVCF (5 tokens, same pattern) |
| ISR | Waterfall | Modified waterfall (P1 reduces, P7 brings CoG share) |
| Cert limit | 2D hash, company count | Same but also changes on Takeover |
| Mergers | None | System Formation + Takeover |
| Merger rounds | None | After SR in phases 4-5; special after 1st 6-train |
| Miami $0 first run | N/A | Yes |
| Key West Token | N/A | FEC only, phases 3-7 |
| Medium cities | N/A | Special upgrade path |
| Systems (20-share) | N/A | Two 10-share companies merge |
| Train limit for System | N/A | Double per-shell limit |
| Tile lays | 1 lay + 1 upgrade | Same; Systems get 3 yellow or 1+1; float gets extra lay |
