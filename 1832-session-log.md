# 1832 Development Session Log
Date: 2026-05-03

---

## User
`/init`

Please analyze this codebase and create a CLAUDE.md file, which will be given to future instances of Claude Code to operate in this repository.

What to add:
1. Commands that will be commonly used, such as how to build, lint, and run tests. Include the necessary commands to develop in this codebase, such as how to run a single test.
2. High-level code architecture and structure so that future instances can be productive more quickly. Focus on the "big picture" architecture that requires reading multiple files to understand.

---

## Assistant

Created `CLAUDE.md` with the key information a future Claude instance will need:

- **Dev commands** for starting the stack, running tests, and formatting
- **Architecture overview** covering the engine's Round/Step pattern, how per-game modules are structured, and the Opal isomorphic Ruby/JS setup
- **Fixture test system** — how snapshots work, what the tests verify, and the single-line JSON formatting requirement
- **Action replay model** — the critical constraint that all action processing must stay backwards-compatible with stored game logs
- **Useful dev routes** for tile/map development

---

## User

read 1832-rules.pdf in this directory to gain context

---

## Assistant

`pdftoppm` isn't installed, which is needed to render PDFs. You can install it with:

```bash
brew install poppler
```

After that, I'll be able to read the PDF. Alternatively, if you can export it as text or share the rules another way, I can work with that too.

---

## User

`brew install poppler`

---

## Assistant

(ran `brew install poppler`, which succeeded)

`pdftoppm` is installed at `/opt/homebrew/bin/pdftoppm` but the Read tool isn't finding it — likely a PATH issue with how the tool resolves binaries. Let me try reading it via pdftotext instead.

(ran `pdftotext /Users/jdl/projects/18xx/1832-rules.pdf -` and read the full output)

I've read the full rules. Here's a summary of **1832: The South** (v4.2c, by W.R. Dixon):

---

## Overview

1832 is a merger-focused 18xx game set in the American South. It's closest in style to 1850/1870, with 2–6 players and a $12,000 bank. The central mechanic distinguishing it from most 18xx games is its **merger system**.

---

## Key Mechanics

### Phases & Trains
Eight phases triggered by first purchase of each train type: 2 ($80×7), 3 ($180×6), 4 ($300×4), 5 ($450×3), 6 ($630×3), 8 ($800×3), 10 ($950×2), 12 ($1100, unlimited). Operating rounds: 1 OR (phases 2–3), 2 ORs (phases 4–5), 3 ORs (phases 5+). Train limits drop from 4 → 3 → 2 through the phases.

### Stock Market
7 colored zones (upper/lower areas, soft ledge, yellow/green/brown/black areas). Yellow/green/brown don't count against certificate limits; brown allows buying all open-market shares of one company in one turn. Black = company closed. Share price moves right (full dividend), left (no dividend), not moved (half dividend or didn't operate). **Share Price Protection**: president can buy back sold shares at market price, restoring price as if sale never happened.

### Floatation
Company floats at 6 of 10 shares sold; receives 10× par value as treasury. Par values: $68–$100.

### Track Laying
2 yellow tiles or 1 upgrade per OR (Systems get 3 yellow or 1 yellow + 1 upgrade). Medium cities start as towns and can upgrade to city tiles OR green town tiles. Special city tiles: Charleston/Jacksonville (#611), Savannah (#193), Atlanta (#190/#191).

### Special Locations
- **West Virginia Coal Fields**: Grey hex requiring $80 token to run through; 5 tokens total, max 1 per company.
- **Miami**: Worth $0 the first time any company runs there (pre-phase 5); normal after.
- **Key West Token** (FEC only): +$50 to Miami value, phases 3–7 only.

### Mergers (Phases 4–5, last chance at first 6-train)
Two types:
1. **Systems Formation**: Two 10-share companies merge into a 20-share System. New share price = average of both companies'. System gets double train capacity, 3 yellow tiles/OR, and can redeem 2 shares/round.
2. **Takeover**: One company buys all outstanding shares of the other (at market/par). Certificate limit tightens. Buyer stays same type (10-share or System).

Companies must have operated and be able to reach each other to merge.

### Private Companies (P1–P7)
- P1 Carolina Stage Coach ($20, $5 revenue, no ability)
- P2 Cotton Warehouse ($40, $10 revenue, +$10 cotton token for non-coastal city)
- P3 Atlantic Shipping ($50, $10 revenue, +$20/$10 port token for coastal city)
- P4 London Investment ($70, $10 revenue, buys one share in any newly started company; can't be sold to public company)
- P5 West Virginia Coal Fields ($80, $15 revenue, WVCF token; can be sold in phase 2 at ½–1× face, phases 3–4 at ½–2×)
- P6 Southern Bank ($100, variant only)
- P7 Central Rail Road & Canal ($200, $30 revenue, comes with CoG president's share; can't be sold to public company)

### 10 Public Companies
A&WP (Atlanta, 2 tokens), ACL (Charleston, 3), CoG (Savannah, 3), FEC (Jacksonville, 2+KW), GRR (Atlanta, 2), GM&O (New Orleans, 3), L&N (Nashville, 3), N&W (Norfolk, 3), SAL (Raleigh, 3), Southern (Knoxville, 3).

### Game End
Bank runs out of money or player bankruptcy. Winner: highest cash + shares at market value + privates at face value.

---

## User

`git checkout 1832_dev`

---

## Assistant

(attempted `git checkout 1832_dev` — failed with shell environment error `_safe_eval: command not found`)

(attempted with `/usr/bin/git checkout 1832_dev` — rejected by user)

Looks like there's a shell environment issue causing `_safe_eval: command not found` errors. It may be a conflict with a shell function defined in your profile. Do you want me to try a different approach, or would you prefer to run the checkout yourself?

---

## User

create a plan to implement the rules of the 1832 game as described in the document using the provided codebase. the 1832 implementation should be as analogous to other code patterns within this codebase. as 1832 is a derivative of 1850 and 1870, those files may be used in reference instead of reimplemting some features if that makes sense to do. I do not want you to write any code, just create a markdown document in this directory with a file-by-file, step-by-step plan on what would need to be implemented. When utilizing 1850 or 1870 code, please call that out. This document should be specific enough that Claude or a human could implement the game from the document.

---

## Assistant

(read 1850 and 1870 source files extensively, including:
- `lib/engine/game/g_1850/game.rb`, `meta.rb`, `entities.rb`, `map.rb`, `corporation.rb`
- `lib/engine/game/g_1850/step/buy_company.rb`, `buy_train.rb`, `track.rb`, `token.rb`, `price_protection.rb`, `special_track.rb`
- `lib/engine/game/g_1870/game.rb`, `meta.rb`, `entities.rb`, `stock_market.rb`
- `lib/engine/game/g_1870/step/buy_sell_par_shares.rb`, `price_protection.rb`, `dividend.rb`, `buy_train.rb`, `buy_company.rb`, `company_pending_par.rb`, `track.rb`
- `lib/engine/game/g_1870/round/stock.rb`, `round/operating.rb`
- `lib/engine/round/merger.rb`
- `lib/engine/step/waterfall_auction.rb`
- `lib/engine/game/g_1817/round/merger.rb`, `step/acquire.rb`
- `lib/engine/game/base.rb` (cert_limit, next_round!, initial_auction_companies)
- `lib/engine/game/g_1889/game.rb`, `meta.rb`, `map.rb`, `entities.rb`)

Created `1832-implementation-plan.md` with a 19-step file-by-file plan covering:

- All files to create under `lib/engine/game/g_1832/`
- Which steps/rounds to subclass from 1870 and 1850 vs. implement from scratch
- Detailed logic for the merger system (System Formation and Takeover)
- The modified Initial Stock Round
- WVCF token (modeled on 1850's Mesabi Range)
- Cotton/Port tokens (modeled on 1870's SCC/GSC tokens)
- Key West Token and Miami first-run rule
- Medium city upgrade path
- Certificate limit table and how it changes on Takeover
- The `next_round!` override to insert merger rounds
- The special mid-OR merger round triggered by the first 6-train
- Optional variants

---

## User

can you please write all of our interactions and all of the thinking output to a log file in this directory

---

## Assistant

I don't have access to my own thinking output after the fact — those internal reasoning traces aren't stored anywhere I can read them back from.

What I *can* do is write a log file containing the full conversation transcript — every user message and every assistant response, verbatim. Want me to do that?

---

## User

what?

---

## Assistant

I don't have access to my own thinking output after the fact — those internal reasoning traces aren't stored anywhere I can read them back from.

What I *can* do is write a log file containing the full conversation transcript — every user message and every assistant response, verbatim. Want me to do that?

---

## User

yes

---

## Assistant

(wrote this file)

---

## User

perform step 1 and step 1 only please

---

## Assistant

Read `lib/engine/game/g_1832/meta.rb`. The file already existed with partial content (wrong designer name, wrong publisher, wrong player range, only 2 optional rules). Updated the file with:
- `GAME_DESIGNER = 'W. R. Dixon'`
- `GAME_PUBLISHER = :deep_thought_games`
- `PLAYER_RANGE = [2, 6].freeze`
- All 5 optional rules: `:finish_on_400`, `:diesels`, `:southern_bank`, `:historical_order`, `:no_mergers`
- Correct `GAME_RULES_URL` and `GAME_INFO_URL`

---

## User

please perform step 2

---

## Assistant

Read `lib/engine/game/g_1832/corporation.rb`. The file existed with only `attr_accessor :coal_token`. Updated to add the missing attributes from the plan, preserving `coal_token` (the existing codebase uses "coal" naming for the WVCF token):

```ruby
attr_accessor :coal_token, :cotton_token, :port_token, :key_west_placed,
              :system_shells, :system_id, :operated_once
```

---

## User

please proceed to steps 3 and 4

---

## Assistant

**Step 3 — entities.rb:**
Read the file. Found:
- GRR name typo: "Georgia Railraod" — fixed to "Georgia Railroad"
- P6 (Southern Bank) missing entirely — added full definition with description of mortgage mechanic; implementation deferred to game.rb/step files
- Corporations (10 majors + 5 systems) already complete
- P1–P5 and P7 already present

**Step 4 — map.rb:**
Read the file. Found two tile label bugs:
- Tile `191` had `label=S` (Savannah's label) but it's Atlanta's brown upgrade — fixed to `label=Atl`
- Tile `193` had no label but it's Savannah's brown upgrade (confirmed by `future_label=label:S,color:brown` on H16) — added `label=S`

No layout change: existing `:pointy` is correct and consistent with both 1870 and 1850 (the implementation plan incorrectly stated `:flat`).

---

## User

please proceed to step 5

---

## Assistant

Read the plan sections for step 5, existing game.rb, plus split-out market.rb, phases.rb, trains.rb, and all existing step files. Found several bugs and missing implementations.

**Changes made:**

**phases.rb:**
- Added `'mergers_allowed'` to phase 4 status (was only `'can_buy_companies'`)
- Added `status: %w[mergers_allowed]` to phase 5

**trains.rb:**
- Added `{ 'type' => 'final_merger_chance' }` event to the 6-train

**step/price_protection.rb:**
- Fixed critical namespace bug: module was `G1850` instead of `G1832`

**game.rb (14 additions/fixes):**
- Added missing constants: `BANK_CASH = 12_000`, `CAPITALIZATION = :full`, `FLOAT_PERCENT = 60`, `CURRENCY_FORMAT_STR = '$%s'`, `SOUTHERN_BANK_STARTING_CASH`, `VARIANT_GAME_END_CHECK`
- Added `'final_merger_chance'` to `EVENTS_TEXT`
- Added `@miami_first_run`, `@final_merger_triggered`, `@recently_floated` to `setup`
- Fixed `event_close_companies!` bug: `company.close!` (undefined variable) → iterate all companies, skipping P6 when Southern Bank variant is active
- Added `event_final_merger_chance!` (sets `@final_merger_triggered = true`)
- Added `event_remove_key_west_token!` (clears FEC's key west placement)
- Updated `revenue_for`: added Miami first-run rule (deducts Miami's revenue on first run ever) and Key West +$50 bonus for FEC
- Added `float_corporation` / `track_action_processed` (1850 pattern for `@recently_floated` list)
- Added `mergers_allowed?`, `southern_bank?`, `no_mergers_variant?`
- Added `game_end_check_values` (handles `:finish_on_400` variant → stock_market end check)
- Added `init_starting_cash` override (uses `SOUTHERN_BANK_STARTING_CASH` when variant active)
- Added `next_round!` with merger round insertion: after SR in phases 4–5, after OR if final_merger_triggered
- Added `new_merger_round`, `merge_corporations`
- Updated `status_array` to also show Key West Token status
- Added helper accessors: `london_company` (P4), `southern_bank_company` (P6), `central_rr_company` (P7), `fec_corporation` (FECR), `cog_corporation` (CG)

---

## User

please proceed to steps 6 through 10 and write a log file of your output for all steps

---

## Assistant

Read plan sections for steps 6–10. Read 1870's `buy_sell_par_shares.rb`, `buy_train.rb`, `dividend.rb`; read 1850's `buy_company.rb`; read all existing G1832 step files.

Found additional bugs:
- `step/price_protection.rb` had wrong parent class (G1870 instead of G1850 per plan) — now fixed
- `step/acquire_va_tunnel_coal_marker.rb` and `step/special_buy.rb` are copy-pasted from G1828 with wrong module namespace — noted but left for separate cleanup

**Step 6 — step/buy_sell_par_shares.rb (updated):**
Already existed as a minimal stub with `visible_corporations`. Added:
- `HISTORICAL_ORDER` constant listing the 10 major corporations in historical founding order (TODO: verify against physical game §17.4)
- `can_buy?` override for the `:historical_order` optional rule: blocks purchase of the 6th share of a corporation until all predecessor corporations have ≤2 IPO shares remaining (meaning they've sold 6+)
- Added `max_reissue_200?` to `game.rb` returning `true` — the 1870 step already checks `@game.respond_to?(:max_reissue_200?) && @game.max_reissue_200?` to enforce $200 reissue cap

**Step 7 — step/price_protection.rb (updated):**
Updated to subclass `G1850::Step::PriceProtection` directly per the plan. The overridden methods (`price_protection_seller`, `can_buy?`) were identical to 1850's implementation, so they were removed — the class is now a clean empty subclass. Updated `require_relative` to point to g_1850.

**Step 8 — step/buy_train.rb (created):**
New file. Subclasses `G1870::Step::BuyTrain`. Adds one override:
- `can_sell?`: calls super (which checks the 20% minimum hold) AND requires `bundle.shares.all?(&:buyable)` — prevents presidents from selling redeemed shares (where `buyable: false`) to fund emergency train purchases (§10.6).

**Step 9 — step/dividend.rb (created):**
New file. Subclasses `G1870::Step::Dividend` with no overrides. Inherits full/half/withhold dividend types with correct stock price movement: right on full, left on withhold, no movement on half or $0 declared.

**Step 10 — step/buy_company.rb (updated):**
Changed parent from `Engine::Step::BuyCompany` to `G1850::Step::BuyCompany`. The existing `can_buy_company?` override was identical to 1850's implementation and was removed — 1850's version handles the phase-2 restriction correctly. P4 and P7 are already excluded via their `no_buy` abilities in entities.rb.

**game.rb (round wiring updated):**
Updated `operating_round` and `stock_round` to use the new G1832 steps:
- `G1870::Step::Dividend` → `G1832::Step::Dividend`
- `G1870::Step::BuyTrain` → `G1832::Step::BuyTrain`
- `G1850::Step::PriceProtection` → `G1832::Step::PriceProtection` (both in OR and SR)

**Outstanding items / known issues noted during steps 6–10:**
- `HISTORICAL_ORDER` in buy_sell_par_shares needs verification against the physical game's §17.4
- `step/acquire_va_tunnel_coal_marker.rb` and `step/special_buy.rb` are G1828 code files incorrectly placed in the G1832 directory — they will auto-load but define G1828 classes, not causing 1832 errors but adding noise
- `step/token.rb` references `MIAMI_HEX` as a bare constant (not qualified) and uses `includes?` instead of `include?` — these are bugs to fix in step 12
- `round/merger.rb` calls `@game.merge_corporations` which is now implemented in game.rb
- P6 (Southern Bank) exclusion from corporate purchase: P4 and P7 use `no_buy` ability; P6 does not — if P6 should never be corporately owned, add `no_buy` to its entity definition in step 12/13 when implementing the Southern Bank mechanic

---

## User

please proceed to steps 11 through 14 and write a log file of all of your output

---

## Assistant

Read current state of `step/track.rb`, `step/token.rb`, `game.rb`, `step/buy_company.rb`, `step/dividend.rb`. Read `Engine::Step::CompanyPendingPar` and `Engine::Step::WaterfallAuction` for parent class details. Read FECR entity definition for Key West ability cost and hexes.

**Step 11 — step/track.rb (updated):**
`pass!` method added between `process_choose` and `hex_neighbors`:
```ruby
def pass!
  super
  @game.track_action_processed(current_entity)
end
```
This calls `game.rb`'s `track_action_processed` which removes the entity from `@recently_floated`. The medium city upgrade path was already handled by the existing boomtown mechanism (`all_potential_upgrades` in game.rb + boomtown hex assignment in `process_lay_tile`). Parent class remains `Engine::Step::Track` — NOT `G1850::Step::Track`, because 1850's `update_token!` references `@game.cbq_corp` which does not exist in 1832.

**Step 12 — step/token.rb (fixed bugs):**
Fixed four bugs:

1. `MIAMI_HEX` bare constant (undefined in step scope) → `@game.class::MIAMI_HEX` in both `place_miami_token` and `can_place_miami_token?`
2. `includes?` (Rails method, not plain Ruby) → `include?` in both `place_miami_token` and `can_place_miami_token?`
3. Missing `corporation.key_west_placed = true` in `place_miami_token` — added after `ability.use!`
4. Missing guard in `can_place_miami_token?` — added `return false if entity.key_west_placed` as the first check to prevent re-offering the option after placement

Cotton/Port token placement is NOT in token.rb — those use `G1870::Step::Assign` which is already wired into `operating_round`.

**Step 13 — step/initial_auction.rb (created):**
New file subclassing `Engine::Step::WaterfallAuction`. Overrides `all_passed!`:

```ruby
def all_passed!
  @game.payout_companies

  if @companies.include?(@cheapest)
    increase_discount!(@cheapest, 5)
  elsif @companies.empty?
    @game.or_set_finished
  end

  entities.each(&:unpass!)
end
```

Key differences from standard `WaterfallAuction#all_passed!`:
- Always calls `@game.payout_companies` (fake OR every time all pass, not only at end)
- Uses `@companies.empty?` as the end condition instead of `!@companies.include?(@cheapest)` — this means the ISR continues until ALL companies are sold, not just until P1 is sold
- Standard behavior would incorrectly end the ISR after P1 sold even if P2–P7 remain

**Step 14 — step/company_pending_par.rb (created):**
New empty subclass of `Engine::Step::CompanyPendingPar` (NOT `G1870::Step::CompanyPendingPar`):

```ruby
class CompanyPendingPar < Engine::Step::CompanyPendingPar
end
```

G1870's version calls `company.close!` after par. For 1832, P7 (West Virginia Central & Pittsburgh) must remain open after par so CoG can receive its private company benefit. P7 closes naturally via `event_close_companies!` at the first 5-train.

**game.rb `new_auction_round` (updated):**
Updated to use the new 1832-specific steps:
```ruby
def new_auction_round
  Engine::Round::Auction.new(self, [
    G1832::Step::CompanyPendingPar,
    G1832::Step::InitialAuction,
  ])
end
```

**Outstanding items for steps 15+:**
- Step 15: `round/merger.rb` — merge/takeover step logic (currently a stub calling `@game.merge_corporations`)
- Step 16: merger enhancements — system formation, shell corporations
- Step 17: icons (boomtown token SVG, FECR Key West SVG, cotton token SVG)
- Step 18: RSpec specs
- Step 19: fixture JSON for action replay tests

---

## User

please proceed to steps 15 through 19 and continue to log your output

---

## Assistant

Read `round/merger.rb` (existing stub), `lib/engine/round/merger.rb` (base class), `lib/engine/action/merge.rb`, `lib/engine/share.rb` (Share#transfer), `lib/engine/share_pool.rb` (transfer_shares, move_share), `lib/engine/bank.rb` (includes ShareHolder). Read 1867 merger step for structural reference. Extracted merger rules from PDF (§11.1–11.8) via `pdftotext`.

**Step 15 — `step/merge.rb` (created):**
New step subclassing `Engine::Step::Base`. Manages a two-stage merger flow stored in `@round.merging`:

1. **Stage 1** — `merge` action: records `{initiator:, target:}` in `@round.merging`
2. **Stage 2** — `choose` action: picks merger type from a choices hash:
   - `"system_<id>"` → `@game.perform_system_formation(initiator, target, system)`
   - `"takeover"` → `@game.perform_takeover(initiator, target)`

`mergeable_corporations(corp)` filters to: operated, floated, non-system, connected to initiator via `@game.corps_connected?`. Uses `round_state: { merging: nil }` so state persists across action replay.

**Step 15 cont. — `round/merger.rb` (updated):**
Added `after_process` (unpasses players, calls `next_entity!`), `next_entity!` (advances entity index, resets steps, handles wrap-around). Added `force_next_entity!` as a **no-op** — this prevents `close_corporation` inside `perform_system_formation` from double-advancing the entity when corp1 (the current entity) is closed mid-merger. Pattern borrowed from 1867's merger round. Updated `game.rb`'s `new_merger_round` to include `G1832::Step::Merge`.

**Step 16 — `game.rb` merger helpers (added):**

`available_systems`: returns all `type: :system` corps that haven't floated yet.

`can_form_system?(corp1, corp2)`: true if any player holds ≥40% combined.

`corps_connected?(corp_a, corp_b)`: checks co-location in a city, or reachability via `graph.connected_nodes`.

`perform_system_formation(corp1, corp2, system)`:
1. Sets system par price = average of two component share prices, rounded to nearest market value
2. Finds qualifying president (initiator's owner first, then clockwise) requiring ≥40% combined
3. Collects exactly 40% from qualifying player (president certs first, then regular shares)
4. Uses `share.transfer(entity)` to exchange: surrendered shares → `@bank`, system president cert → qualifying player
5. Exchanges remaining component shares 1:1 with system 5% shares (each holder's 10% comp share → system 5% share)
6. Transfers cash, trains, companies to system
7. Handles duplicate coal tokens (returns one to bank, increments counter)
8. `system_merge_tokens(comp1, comp2, system)`: replaces component map tokens with system tokens, removing duplicates in shared cities
9. Calls `close_corporation` on both components — no-ops on assets (already transferred), share cleanup handled automatically
10. Calls `system.float!` and `clear_token_graph_for_entity(system)`

`perform_takeover(buyer, target)`:
1. Calculates total cost: IPO shares at par, bank pool + player shares at market
2. President contributes if buyer is short on cash
3. Pays players at market price, bank for remainder
4. Transfers assets (cash, trains, companies)
5. Handles coal tokens (returns duplicate)
6. Replaces target tokens on map with buyer tokens (removes duplicates)
7. Calls `close_corporation(target)` for cleanup

**Step 17 — Icons (created):**
- `public/icons/1832/boomtown_token.svg`: gold circle with "BT" label — referenced in `ASSIGNMENT_TOKENS['boomtown']`
- `public/icons/1832/cotton_token.svg`: white circle with "CO" label — referenced in `ASSIGNMENT_TOKENS['P3']`
- `public/icons/1832/FECR_key_west.svg`: already existed (white circle with "FECR" label)

**Step 18 — `spec/lib/engine/games/g_1832_spec.rb` (created):**
Tests basic game initialization:
- Bank cash = $12,000 (BANK_CASH)
- Player cash correct for 3p ($700), 2p ($1050), Southern Bank variant ($800 with 3p)
- Round is `Engine::Round::Auction`
- 10 major + 5 system corporations
- 7 private companies
- 5 coal tokens
- FECR has `assign_hexes` ability for N16
- `BOOMTOWN_HEXES` not empty

**Step 19 — Fixture directory (created):**
`spec/fixtures/1832/` directory created. No fixture JSON added — game fixture files require a complete game action log from actual gameplay. The `game_spec.rb` test harness auto-discovers fixtures; a fixture can be added once a full game is played on the platform.

**All files pass Ruby syntax check** (`ruby -c`).

**Outstanding items for future steps:**
- Verify HISTORICAL_ORDER constant against physical game §17.4
- `step/acquire_va_tunnel_coal_marker.rb` and `step/special_buy.rb` are still G1828 code in G1832 directory
- System formation edge cases not yet covered: vice-president certificates (component president certs held by non-qualifying players)
- Post-merger share buying round (§11.6 implies some share dealing after system formation) — not yet implemented
- P7 (WVC&P) / CoG relationship: CoG (CG) closes when it buys its first train — not yet implemented
- Southern Bank (P6) variant: full mechanics beyond starting cash not yet implemented

---

## User

create a plan and generate a new document with a step-by-step description on how to cover those gaps. Assume Claude will implement, but the instructions should be good enough for a human to be able to implement

---

## Assistant

Read rules §11.6.1–11.6.9 (system formation details including vice-president certs and share redemption), §17.3 (Southern Bank), §17.4 (Historical Order), §16.2 (P4/P7 attributes), §5.7 (ISR), §5.10–5.11 (share redemption/reissue), §11.8 (merged company operations). Read current code for `buy_sell_par_shares.rb`, `entities.rb`, `buy_train.rb`.

Created `1832-implementation-gaps.md` covering 12 steps (20–31):

**Steps 20–22 (correctness bugs):**
- Step 20: Fix `HISTORICAL_ORDER` constant — current order is wrong; correct order per §17.4 is `[ACL, SALR, CG, GRR, SOU, A&WP, N&W, L&N, GMO, FECR]`
- Step 21: Delete misplaced G1828 step files (`acquire_va_tunnel_coal_marker.rb`, `special_buy.rb`)
- Step 22: Vice-president certificates — component president certs held by non-qualifying players become 10%-system certs (not 5%); implement `@vice_president_certs` hash + override `percent_of`

**Steps 23–27 (missing mechanics):**
- Step 23: P4 London Investment close trigger — closes when invested corporation pays first dividend; requires tracking which corp P4 invested in, checking in `Step::Dividend`
- Step 24: System dividend calculation — 5% per system share, round odd-unit holders up; override payout per share in `Step::Dividend` for system corporations
- Step 25: System train limits — systems have 2× train spaces; override `train_limit` in game.rb; store `system_shells` during formation; note optional forced second-train purchase rule
- Step 26: System share redemption — systems redeem 2 shares per SR (1 per turn); override redemption limit check in `BuySellParShares` for system corporations
- Step 27: Cert limit after takeover — verify `init_cert_limit` handles this correctly; fix if system takeover (2 shells) needs double adjustment

**Step 28 (large — Southern Bank variant):**
New `step/southern_bank.rb` step; mortgage state on corporation; interest payment in `payout_companies`; fix P6 revenue ($0 when no mortgage); game-end $100 P6 value; no-sell-after-6-train flag. Recommended implementation order given.

**Steps 29–31 (polish/verification):**
- Step 29: System share price diagonal positioning per §11.6.3 (start at leftmost predecessor's row, move diagonally down-right to ledge; cap par at $275) — deferred to beta
- Step 30: End-to-end P7/CoG close mechanic — verify `when: 'bought_train'` ability fires correctly; add explicit close logic in `BuyTrain#process_buy_train` if engine doesn't handle it natively
- Step 31: Game fixture for CI — requires actual gameplay; place at `spec/fixtures/1832/<id>.json`; normalize with `make fixture_format`

Summary table included showing file(s), type, and complexity for each step. Recommended order: 20–22 first, then 25–27, then 23–24, then 30, save 28 and 31 for last.

---

## User

please proceed with steps 20-21

---

## Assistant

**Step 20 — Fix `HISTORICAL_ORDER`:**
Updated constant in `step/buy_sell_par_shares.rb` from the incorrect `%w[A&WP GRR CG L&N N&W SOU ACL SALR GMO FECR]` to the correct chronological order per §17.4: `%w[ACL SALR CG GRR SOU A&WP N&W L&N GMO FECR]`.

**Step 21 — Remove misplaced G1828 files:**
The shell was non-functional (snapshot initialization error), so the two files could not be deleted via `rm`. Instead, their contents were replaced with a single-line `# TODO: delete this file` comment so they are harmless no-ops when auto-loaded and clearly marked for deletion:
- `step/acquire_va_tunnel_coal_marker.rb`
- `step/special_buy.rb`

**Action required:** Run `rm lib/engine/game/g_1832/step/acquire_va_tunnel_coal_marker.rb lib/engine/game/g_1832/step/special_buy.rb` from the repo root when shell access is available.

