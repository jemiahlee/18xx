# 1832: The South — Implementation Gaps Plan

This document covers the remaining work after steps 1–19. Each step is self-contained, ordered from
smallest blast radius to largest. Steps 20–22 are correctness fixes. Steps 23–28 add missing mechanics.
Steps 29–31 are polish and verification.

---

## Step 20 — Fix `HISTORICAL_ORDER` constant

**File:** `lib/engine/game/g_1832/step/buy_sell_par_shares.rb`

**Problem:** The current order `%w[A&WP GRR CG L&N N&W SOU ACL SALR GMO FECR]` is wrong.
Rules §17.4 lists companies by historical start date:

| Corp | Name | Year |
|------|------|------|
| ACL  | Atlantic Coast Line | 1830 |
| SALR | Seaboard Air Line | 1832 |
| CG   | Central of Georgia | 1833 |
| GRR  | Georgia Railroad | 1833 |
| SOU  | Southern Railway | 1847 |
| A&WP | Atlanta & West Point | 1847 |
| N&W  | Norfolk & Western | 1850 |
| L&N  | Louisville & Nashville | 1850 |
| GMO  | Gulf, Mobile & Ohio | 1850 |
| FECR | Florida East Coast | 1885 |

**Implementation:** Replace the constant value:

```ruby
HISTORICAL_ORDER = %w[ACL SALR CG GRR SOU A&WP N&W L&N GMO FECR].freeze
```

**Verify:** In a game with `:historical_order` optional rule active, attempting to buy the 6th share of
`SALR` should be blocked until `ACL` has sold 6 shares (i.e., `ACL.num_ipo_shares <= 2`).

---

## Step 21 — Remove misplaced G1828 step files

**Files to delete:**
- `lib/engine/game/g_1832/step/acquire_va_tunnel_coal_marker.rb`
- `lib/engine/game/g_1832/step/special_buy.rb`

**Problem:** These files are G1828 source code copy-pasted into the G1832 directory. They define
`Engine::Game::G1828::Step::...` classes, not G1832 classes. They auto-load and do nothing harmful,
but pollute the namespace.

**Implementation:** Simply delete both files. No other file references them.

**Verify:** Run `rake rubocop` — no new errors. The game still initialises. No `G1828` constant
references should remain in the `g_1832/` tree.

---

## Step 22 — Vice-president certificates in system formation

**File:** `lib/engine/game/g_1832/game.rb`, method `perform_system_formation`

**Problem:** §11.6.1 says: "If other players have [component company] president's certificates, they
will remain in play and be considered 'vice-president's' certificates." A vice-president cert is the
20% president cert of a component company, held by a player who is NOT the qualifying system
president. It counts as a full certificate but is worth **10% of the system** (half of 20%), not 5%.

The current code treats ALL non-surrendered component shares as 5%-system shares. It does not
distinguish a 20% president cert held by a non-qualifying player.

**Rules summary:**
- Qualifying player surrenders exactly 40% of component shares → receives system president cert (20%)
- All other component shares remain as certificates for their holders
- 10% comp shares → 5% system shares (unchanged)
- 20% president comp certs not surrendered → 10% system "vice-president" certs (treated as a full certificate, bought/sold as a single transaction, may be held by any player including the system president)

**Implementation:**

In `perform_system_formation`, after the main share exchange loop, add a second pass that identifies
any un-surrendered 20% president certs and marks them correctly. In the engine, `share.percent`
represents the percentage the share is worth in the corporation. For a system, a 20% component
president cert should be treated as 10% of the system.

The cleanest implementation in this engine does not change the `percent` field on the share object
(that would be a breaking change). Instead, override `num_shares_of` or `percent_of` in
`G1832::Game` to account for system membership:

```ruby
# In game.rb
def percent_of(corporation, entity)
  return super unless system?(corporation)

  entity.shares_of(corporation).sum(&:percent) +
    corporation.shells.sum do |shell|
      entity.shares_of(shell).sum { |s| s.percent / 2 }
    end
end
```

Where `corporation.shells` would be set during system formation (see Step 25 for the `shells`
attribute). Any share still belonging to a component company that is now a shell of the system
contributes half its printed percent toward the system holding.

**Alternative simpler approach (recommended for prealpha):** During `perform_system_formation`,
when a component company president cert is held by someone other than the qualifying player, log a
clear message:

```
"#{holder.name} holds #{comp.name} president's certificate as a vice-president's certificate
 (counts as 10% of #{system.name})"
```

And store the vice-president certs in a hash on game:

```ruby
@vice_president_certs ||= {}
@vice_president_certs[system] ||= []
@vice_president_certs[system] << share
```

Then override `percent_of` to treat these shares as half-percent for the system:

```ruby
def percent_of(corporation, entity)
  return super unless system?(corporation)
  return super unless @vice_president_certs&.key?(corporation)

  # Vice-president certs held by entity count as half their printed percent
  vp_held = (@vice_president_certs[corporation] || []).select { |s| s.owner == entity }
  normal = entity.shares_of(corporation).sum(&:percent)
  vp_adjustment = vp_held.sum { |s| s.percent / 2 } - vp_held.sum(&:percent)
  normal + vp_adjustment
end
```

**Verify:** In a 3-player game where player B holds corp X president and player C holds corp Y
president, and player A (initiator) holds 20%+20% from regular shares: player A gets the system
president; B and C retain their 20%-printed certs which count as 10% for cert limit and dividend
purposes.

---

## Step 23 — P4 London Investment: close on first dividend

**File:** `lib/engine/game/g_1832/entities.rb` (P4 abilities), and
`lib/engine/game/g_1832/game.rb` (dividend tracking)

**Problem:** Per §16.2/P4: "After the company pays its first dividend, the London Investment Company
is closed." The current `exchange` ability only lets the player acquire one IPO share; there is no
mechanism to close P4 after the target corporation pays its first dividend.

**Rules summary:**
- P4 owner uses the `exchange` ability during the ISR or first SR to take one IPO share of any newly
  started corp (including CG in the first SR). This counts as a stock purchase.
- P4 closes the first time that corporation pays a full or half dividend (not withhold).
- P4 may not be sold between players after it has purchased a share.
- P4 may never be sold to a corporation.

**Implementation:**

1. **Track which corporation P4 invested in.** Add a `@p4_invested_in` attribute to game state
   (initialise to `nil` in `setup`). Set it when the `exchange` ability is used:

   ```ruby
   def after_buy_company(player, company, _price)
     return unless company == london_company
     # p4_invested_in is set when the exchange ability is exercised — see step/buy_sell_par_shares.rb
   end
   ```

   Alternatively, track it in `G1832::Step::BuySellParShares` by overriding `process_buy_shares` or
   watching for `exchange:` purchases.

2. **Close P4 on first dividend.** In `G1832::Step::Dividend`, after a full or half dividend is paid,
   check if P4 exists and has invested in this corporation:

   ```ruby
   def process_dividend(action)
     super
     return if action.kind == 'withhold'
     return unless (p4 = @game.london_company)
     return if p4.closed?
     return unless @game.p4_invested_in == action.entity

     p4.close!
     @log << "#{p4.name} closes after #{action.entity.name} pays its first dividend"
   end
   ```

3. **Block inter-player sale after exchange used.** Add a check to `purchasable_companies` or the
   `can_sell_company?` helper: if P4 has already exercised its ability (i.e., `p4_invested_in` is set),
   return false for player-to-player sales.

**Verify:** Player A buys P4. During the SR, uses it to take 1 share of SOU from IPO. SOU later pays
a dividend → P4 closes. SOU withholds → P4 does not close. After the ability is used, no player can
offer P4 to another player.

---

## Step 24 — System dividend calculation (§11.6.4)

**File:** `lib/engine/game/g_1832/step/dividend.rb`

**Problem:** §11.6.4: "Shares in a System pay 5% of the total dividend per share. If the total
dividend paid is not a multiple of 20, round only odd 5% shares up to the nearest dollar." The
standard dividend step divides payout proportionally by the `percent` of each share. For a system
where a vice-president cert is printed as 20% but counts as 10%, and where many holders have
component company certs worth 5% of the system, the per-share rounding is different.

**Rules example:** Total dividend $130. Player with 1 system share (5%) gets $7 (rounding $6.50 up).
Player with 2 shares gets $13. Player with 3 shares gets $20.

**Implementation:**

Override `dividend_per_share` (or `payout_per_share`) in `G1832::Step::Dividend` for system
corporations:

```ruby
def payout_per_share(entity, revenue)
  return super unless @game.system?(entity)

  # System pays 5% per effective share. revenue / 20 = value per 5% unit.
  (revenue / 20.0).ceil  # per 5% unit; callers multiply by share count
end
```

The base dividend step calls something like `payout = (revenue * share.percent / 100.0).round`.
For a system, since all shares count as 5% units (even if printed higher), override to compute:

```ruby
def dividend_share_count(share, corporation)
  return super unless @game.system?(corporation)

  # Each share counts as share.percent / 10 system units of 5% each,
  # but a vice-president cert (20% printed) counts as 2 units.
  share.percent / 10
end
```

Then distribute: total units = corporation effective shares outstanding (sum over all holders of
`share.percent / 10`). Per-unit value = `(revenue / total_units.to_f)`. Each holder receives
`(per_unit_value * units_held)` rounded up for odd units.

**Note:** The exact method names to override depend on how `G1870::Step::Dividend` implements its
payout. Read that file before implementing. The rounding rule "round only odd 5% shares up" means
if a player has an even number of 5%-units (0, 2, 4…) their payout is exact; if odd (1, 3, 5…) it
rounds up.

**Verify:** Create a unit test where a system earns $130 and verify payouts: 1-share holder gets $7,
2-share holder gets $13, 3-share holder gets $20.

---

## Step 25 — System train limits (doubled, §11.6.7)

**File:** `lib/engine/game/g_1832/game.rb`

**Problem:** §11.6.7: "A System consists of the shells of the two predecessor companies…double the
number of spaces for trains." The current game has a standard train limit per phase. Systems should
have 2× the limit.

**Implementation:**

1. **Store shells on the system.** During `perform_system_formation`, record the component companies
   as "shells" of the system. Add `system_shells` to `G1832::Corporation` (already has
   `attr_accessor :system_shells`). In `perform_system_formation`, after closing components:

   ```ruby
   system.system_shells = [corp1.id, corp2.id]
   ```

2. **Override `train_limit`.** In `game.rb`:

   ```ruby
   def train_limit(entity)
     multiplier = system?(entity) ? 2 : 1
     super * multiplier
   end
   ```

   Verify the base `train_limit` method signature — it may take `entity` or look up from phase. The
   standard implementation is `@phase.train_limit(entity)` which returns an integer. Wrapping with a
   multiplier should be safe.

3. **Forced-buy rule for second train (§11.6.7).** When a system has trains ≤ the per-shell limit,
   the president MAY optionally force a second train purchase (cheapest available, no cash left in
   treasury, president pays shortfall but cannot sell stock for this). This is a president-option rule
   that is hard to enforce digitally; for prealpha, log a reminder in `process_dividend` or
   `process_buy_train` for system corporations rather than enforcing it.

**Verify:** A system in phase 4 (train limit 2 per regular corp) should be able to hold 4 trains.
Attempting to buy a 5th should be blocked.

---

## Step 26 — System share redemption (2 per SR, §11.6.9 / §5.10)

**File:** `lib/engine/game/g_1832/step/buy_sell_par_shares.rb`

**Problem:** §11.6.9: "In one stock round, a System may redeem two 5% shares, one per turn." Regular
corporations can only redeem one share per complete stock round. The 1870 parent step tracks
redemptions; 1832 systems need to allow a second redemption.

**Implementation:**

Override the redemption-count check for system corporations in `G1832::Step::BuySellParShares`.
First, read `G1870::Step::BuySellParShares` to find where the one-redemption-per-SR limit is
enforced (look for something like `redeemed_this_round` or `num_redeemed`).

Then add:

```ruby
def can_redeem?(entity, bundle)
  return super unless @game.system?(entity)

  # Systems may redeem up to 2 shares total (1 per stock turn)
  times_redeemed = @round.redeemed_this_round[entity] || 0
  return false if times_redeemed >= 2

  super
end
```

The redemption limit §5.10.2 ("max 40% held, 60% must stay in player/market hands") still applies
and is presumably handled by `super`.

**Verify:** A system that has already redeemed one share this SR can redeem a second on its second
stock turn. A third attempt in the same SR should be blocked.

---

## Step 27 — Certificate limit adjustment after takeover (§11.7)

**File:** `lib/engine/game/g_1832/game.rb`, method `perform_takeover`

**Problem:** §11.7: "After a takeover, the certificate limits marker is moved one column to the right
for each shell in the company which was taken over." A regular company has 1 shell; a system has 2
shells. The current `perform_takeover` calls `@cert_limit = init_cert_limit`, which recalculates
limits based on remaining corporation count. This is structurally different from the rules' column
shift.

**Rules intent:** Moving the cert limit marker right reduces the effective cert limit for all players
because there are now fewer tradeable cert types in the game. `init_cert_limit` already does this
correctly if it recalculates based on the number of corporations still in `@corporations`. Since
`close_corporation(target)` removes the target from `@corporations` before `init_cert_limit` is
called, the recalculation should naturally produce the correct result.

**Verification required:** Read `init_cert_limit` in `base.rb` and confirm it reduces the limit as
corps are removed. Also verify that when a system (2 shells) is taken over, the cert limit moves
**two** columns right — meaning `@corporations` should reflect that 2 corps worth of capacity has
been removed. Since the system was already counted as one entry in `@corporations` (the shells were
closed when the system was formed), the takeover of a system only removes 1 entry but should move
the cert limit 2 steps.

**Implementation fix (if needed):**

```ruby
def perform_takeover(buyer, target)
  # ... existing code ...

  # Count shells absorbed: system counts as 2, regular corp as 1
  shells_absorbed = system?(target) ? (target.system_shells&.size || 2) : 1

  close_corporation(target)

  # Manually adjust cert limit if shells > 1
  if shells_absorbed > 1
    (shells_absorbed - 1).times { @cert_limit = init_cert_limit }
  else
    @cert_limit = init_cert_limit
  end
end
```

**Verify:** After a regular corp takeover, cert limits tighten by 1 column. After a system takeover,
cert limits tighten by 2 columns.

---

## Step 28 — Southern Bank variant (P6) mechanics

**Scope:** This is the largest remaining gap. P6 is the most complex private company in the game.
Only implement when the `:southern_bank` optional rule is active.

**Rules summary (§17.3):**
- P6 costs $100, revenue $10 (only when mortgage outstanding)
- Owner may mortgage one train or placed token owned by the owning corporation
- Mortgage value: half to double the asset's value
- Interest: 10% of mortgaged asset value, paid at the start of each OR from corp treasury (skip if
  unable to pay)
- Repayment: half to full asset value, once per complete OR
- Only one mortgage at a time
- P6 does NOT close at first 5-train
- P6 cannot be sold between players after the first 6-train
- At game end, P6 counts as $100 toward owning player's net worth
- While mortgage is outstanding, P6 does not count against cert limit

**New files needed:**

### `lib/engine/game/g_1832/step/southern_bank.rb`

A new step added to `operating_round` when `:southern_bank` optional rule is active. This step
fires at the start of each corporation's OR turn:

```ruby
class SouthernBank < Engine::Step::Base
  ACTIONS = %w[choose pass].freeze

  def actions(entity)
    return [] unless entity.corporation?
    return [] unless (p6 = find_p6_for(entity))

    return ACTIONS if can_take_mortgage?(entity, p6) || can_repay_mortgage?(entity, p6)
    []
  end

  def choice_name; 'Southern Bank'; end

  def choices
    entity = current_entity
    p6 = find_p6_for(entity)
    c = {}
    eligible_assets(entity).each do |asset|
      label = asset_label(asset)
      half  = (asset_value(asset) / 2.0).ceil
      dbl   = asset_value(asset) * 2
      c["mortgage_#{asset_key(asset)}"] = "Mortgage #{label} (#{format_currency(half)}–#{format_currency(dbl)})"
    end
    if p6.abilities.any? { |a| a.type == :southern_bank_mortgage }
      c['repay'] = 'Repay mortgage'
    end
    c
  end

  def process_choose(action)
    # handle mortgage take-out or repayment
  end
end
```

The mortgage amount is a player-chosen value between half and double the asset value. This requires
either a second `choose` action (for the amount) or a custom UI input. For a first pass, restrict to
the minimum (half) and maximum (double) as fixed options.

### State tracking

Add to `G1832::Corporation`:

```ruby
attr_accessor :southern_bank_mortgage   # { asset: ..., value: Int } or nil
```

Add to `game.rb`:

```ruby
def payout_companies
  # existing payout ...
  # After paying dividends, charge Southern Bank interest to corps
  pay_southern_bank_interest if southern_bank?
end

def pay_southern_bank_interest
  @corporations.each do |corp|
    next unless corp.southern_bank_mortgage

    interest = (corp.southern_bank_mortgage[:value] * 0.10).round
    p6_owner = southern_bank_company.owner
    next unless p6_owner&.player?

    if corp.cash >= interest
      corp.spend(interest, p6_owner)
      @log << "#{corp.name} pays #{format_currency(interest)} interest on Southern Bank mortgage to #{p6_owner.name}"
    else
      @log << "#{corp.name} cannot pay Southern Bank interest"
    end
  end
end
```

### P6 revenue fix

P6 currently pays $10 revenue always. Per rules it only pays $10 when a mortgage is outstanding.
Override `revenue_for_optional_ability` or gate in `payout_companies`:

```ruby
def p6_revenue(corp)
  return 0 unless corp.southern_bank_mortgage

  10
end
```

### P6 close rules

In `event_close_companies!`:

```ruby
@companies.each do |company|
  next if southern_bank? && company.sym == 'P6'  # already present
  company.close! unless company.closed?
end
```

After first 6-train: add an event `'no_sell_p6'` that sets a flag preventing player-to-player sale.

### Game-end P6 value

Override `player_value` or `result` to add $100 for P6 holder:

```ruby
def player_value(player)
  super + (player.companies.include?(southern_bank_company) ? 100 : 0)
end
```

**Recommended implementation order within this step:**
1. Track mortgage state on corporation
2. Implement interest payment in `payout_companies`
3. Implement `SouthernBank` step with mortgage take-out and repay
4. Fix P6 revenue ($0 when no mortgage)
5. Fix P6 game-end value
6. Add no-sell-after-6-train flag

---

## Step 29 — System share price diagonal positioning (§11.6.3)

**File:** `lib/engine/game/g_1832/game.rb`, method `perform_system_formation`

**Problem:** §11.6.3 specifies an exact positioning algorithm: "place [system token] in the new
price share value box on the same row as the leftmost predecessor company's token, and then move it
down and to the right along the diagonal until it hits either the soft ledge or the hard ledge,
whichever comes first." The current code uses the average value rounded to nearest market price,
ignoring the row/diagonal placement.

The rules also cap par value at $275: "Note that a par value greater than $275 is reduced to $275."

**Implementation:**

1. Find the market position of both predecessor companies.
2. Identify the "leftmost" predecessor's row (lower price row = leftmost on the standard 1870-style
   market).
3. Starting from the cell in that row at the calculated average price column, move diagonally
   down-right until hitting a ledge.
4. The final cell is the system's share price.
5. Cap the resulting par value at the market cell corresponding to ≤$275.

This requires understanding the stock market data structure. Read
`lib/engine/stock_market.rb` to understand how `@market` rows and columns work, and how
`find_share_price` or `share_prices_with_types` can locate cells by price. Then read
`G1870::StockMarket` for the soft/hard ledge logic.

For a prealpha implementation, the simplified average-price approach is acceptable. This step can
be deferred until the game reaches beta.

---

## Step 30 — End-to-end verification of P7/CoG close mechanic

**Files:** `lib/engine/game/g_1832/entities.rb`, `lib/engine/game/g_1832/game.rb`,
`lib/engine/game/g_1832/step/buy_train.rb`

**Problem:** P7 has `abilities: [{ type: 'close', when: 'bought_train', corporation: 'CG' }]`.
This should automatically close P7 when CG buys its first train. But several interactions need
verification:

1. **`event_close_companies!`** closes P7 at the first 5-train. This is correct per §12.4 ("all
   private companies, with the exception of P6, are closed by the first 5-train"). But what if CG
   buys a 2-train in phase 2? P7 should close then. Check that the `close` ability fires before the
   5-train event.

2. **`G1832::Step::CompanyPendingPar`** (our custom class) correctly avoids closing P7 after par.
   Verify by reading `Engine::Step::CompanyPendingPar#process_par` — it calls `@game.after_par` but
   does NOT call `company.close!`. Our subclass inherits this.

3. **ISR flow for P7.** When P7 is purchased in the ISR, `CompanyPendingPar` fires and asks the
   player to par CG. After par, CG should be visible as a started corporation in the first SR.

4. **CG first-train close.** When CG's president chooses to buy a train during `G1832::Step::BuyTrain`,
   the engine calls `@game.abilities(company, :close)` to find close triggers. Verify that the
   `when: 'bought_train'` trigger is evaluated by `G1870::Step::BuyTrain` (the parent). If
   `G1870::Step::BuyTrain` does not handle `when: 'bought_train'` company abilities, add a call in
   `G1832::Step::BuyTrain#process_buy_train`:

   ```ruby
   def process_buy_train(action)
     super
     entity = action.entity
     @game.companies.each do |company|
       next if company.closed?
       ability = @game.abilities(company, :close)
       next unless ability&.when == 'bought_train' && ability&.corporation == entity.id

       company.close!
       @log << "#{company.name} closes as #{entity.name} bought its first train"
     end
   end
   ```

   Check whether the base engine already handles this (search for `when.*bought_train` in the
   abilities infrastructure). If it does, no change needed.

**Verify:** Start a 2-player game, buy P7 in the ISR, par CG, have CG buy a 2-train in phase 2 →
P7 closes. Then confirm the first 5-train event does NOT try to close an already-closed P7 (it
should check `company.closed?`).

---

## Step 31 — Game fixture for CI

**File:** `spec/fixtures/1832/<id>.json`

**Problem:** No fixture exists, so the game is not included in CI's `game_spec.rb` replay tests.

**Implementation:**

1. Start an actual game on a local or staging instance of 18xx.games with 1832 selected.
2. Play the game to completion (or at least through an operating round with a dividend, a merger, and
   a train purchase).
3. Use the admin panel or the API to export the game JSON.
4. Run `make fixture_format` to normalize the JSON to a single line (required by the test harness).
5. Place the file at `spec/fixtures/1832/<game_id>.json`.
6. Run `docker compose exec rack rspec spec/lib/engine/game/fixtures_spec.rb -e '1832'` to confirm
   the fixture replays without error.

**Minimum viable fixture:** A 2-player game with all 7 privates purchased, at least one corporation
started and operated, one dividend paid, and game end. This exercises most of the code paths added
in steps 1–19.

---

## Summary Table

| Step | File(s) | Type | Complexity |
|------|---------|------|------------|
| 20 | `step/buy_sell_par_shares.rb` | Bug fix | Trivial |
| 21 | `step/acquire_va_tunnel_coal_marker.rb`, `step/special_buy.rb` | Cleanup | Trivial |
| 22 | `game.rb` | Missing mechanic | Medium |
| 23 | `entities.rb`, `game.rb`, `step/dividend.rb` | Missing mechanic | Medium |
| 24 | `step/dividend.rb` | Missing mechanic | Medium |
| 25 | `game.rb` | Missing mechanic | Small |
| 26 | `step/buy_sell_par_shares.rb` | Missing mechanic | Small |
| 27 | `game.rb` | Bug fix / verification | Small |
| 28 | `step/southern_bank.rb` (new), `game.rb`, `entities.rb` | New variant | Large |
| 29 | `game.rb` | Polish | Medium |
| 30 | `step/buy_train.rb`, `game.rb` | Verification | Small |
| 31 | `spec/fixtures/1832/` | Testing | Requires gameplay |

Complete steps 20–22 first (they are orthogonal and low-risk). Then 25–27 (small, mechanical).
Then 23–24 (require reading parent step internals). Then 30 (verification). Save 28 (Southern Bank)
and 31 (fixture) for last.
