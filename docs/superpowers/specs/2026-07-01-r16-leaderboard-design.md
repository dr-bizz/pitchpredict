# Second Leaderboard: R16 Onward — Design

- **Date:** 2026-07-01
- **Status:** Approved (brainstorming) — ready for implementation plan
- **Branch:** `r16-leaderboard` (off `main`)

## Goal

Add a second leaderboard that scores **only Round-of-16-onward fixtures**, shown
as a tab alongside the existing full-tournament leaderboard on `/leaderboard`.
It lets players see who is performing best once the bracket narrows, independent
of how they did in the group stage.

## Decisions (locked during brainstorming)

1. **Scope = "R16 onward only."** Stages `r16, qf, sf, third_place, final`
   (`fixtures.stage >= 2`). This deliberately **excludes both the group stage and
   the Round of 32.** World Cup 2026 has a 32-team knockout round *before* the
   Round of 16; "R16 onward" is the literal reading, not "the whole knockout
   stage."
2. **No champion bonus.** The R16 board is a pure sum of `points_awarded` for
   in-scope fixtures. The +10 champion-pick bonus remains exclusive to the
   Overall board.
3. **Presentation = tabs on one page.** `/leaderboard` stays a single page with
   two tabs, **Overall** and **From R16**. One nav link; both tables live-update.

## User-Facing Behavior

- `/leaderboard` shows two tabs: **Overall** (default) and **From R16**.
- Each tab has its own top-3 podium and full standings table, ranked by that
  board's points with the same tie handling as today.
- The **From R16** board lists **every player** (a player with zero R16+
  predictions appears with 0 points), mirroring the Overall board — no one is
  dropped for not having played into the bracket yet.
- Both boards update live: when an admin records a result, the page morphs in the
  new standings with no refresh. **The active tab is preserved across a live
  update** — a result arriving while you view "From R16" does not snap you back to
  "Overall."
- Before any R16+ fixture is scored, the From R16 board simply shows everyone at
  0 points (ranked stably by name).

## Architecture

### Scoring: parameterize `LeaderboardService` (chosen over a subclass)

`LeaderboardService` already performs the correct aggregation; it becomes
*variant-aware* rather than being duplicated. A small config registry drives the
two boards:

```ruby
VARIANTS = {
  overall: { min_stage: nil,                    champion_bonus: true  },
  r16:     { min_stage: Fixture.stages[:r16],   champion_bonus: false }
}.freeze
```

- `fetch_rows(variant: :overall)` — default keeps every existing caller working.
- The instance is constructed with `min_stage` and `champion_bonus` from the
  variant config.

Rejected alternatives:
- **Separate `R16LeaderboardService` subclass** — forks the query + ranking path
  and invites drift; ~90% would be shared code.
- **Compute both boards in one pass** — premature; the two queries are cheap and
  independently cached.

### Aggregation query

- **Overall path is unchanged.** When `min_stage` is nil, the query keeps its
  current form: `User.left_joins(:predictions)` with no fixtures join, so the
  most-viewed board takes no extra join on the hot path.
- **R16 path** joins the fixture (`left_joins(predictions: :fixture)`) and gates
  every aggregate on `fixtures.stage >= min_stage` **inside the `CASE`/`SUM`
  expressions, never in a `WHERE`.** Putting the stage predicate in a `WHERE`
  would turn the `LEFT JOIN` into an effective inner join and silently drop every
  player who has no R16+ prediction. Gating inside the aggregates keeps all users
  present with a correct 0.
- The four count columns (`predictions_count`, `exact_count`, `diff_count`,
  `tendency_count`) and the `prediction_points` sum are all built through small
  helpers that fold in the stage gate when present. `predictions_count` is
  expressed as a gated `COUNT`/`SUM(CASE …)` so it reports **in-scope**
  predictions on the R16 board (not the player's whole prediction total).
- Still two queries total per board (one grouped aggregate + one champion-pick
  pluck), no N+1.

### Champion bonus

The `r16` variant skips `champion_bonus_user_ids` entirely (the set is empty), so
no bonus is added and rank depends only on R16+ fixture points.

### Caching & expiry

- Per-variant cache keys: `leaderboard/rows/overall` and `leaderboard/rows/r16`
  (base key + variant suffix).
- `LeaderboardService.expire_rows` stays **no-arg** and clears **all** variant
  keys. Every existing caller — `Prediction#after_commit`, `User#after_commit`,
  `ScoreFixtureJob`, `KnockoutReset` — keeps working with no change.
- Expiring both boards on any change is intentional: it is simpler than deciding
  which board a given prediction affects, and recomputing the unaffected board
  just reproduces identical rows. Write volume is low (admin result entry) and
  the 1-minute TTL bounds staleness regardless.

### Controller

`LeaderboardsController#show` assigns both:

```ruby
@overall_rows = LeaderboardService.fetch_rows(variant: :overall)
@r16_rows     = LeaderboardService.fetch_rows(variant: :r16)
```

### Views

- **Extract `_board.html.erb`** — takes `rows` and `current_user`, renders the
  top-3 podium + the standings table. Both tabs render this one partial, so the
  two boards can never visually drift.
- **`_table.html.erb` gains an `id:` local** (default `"leaderboard-table"`) so
  the two rendered tables have **unique DOM ids**. The `leaderboard-highlight`
  Stimulus controller scopes to its own root element (`this.element.query…`), so
  two instances coexist; only the duplicate `id` needed fixing.
- **`show.html.erb`** renders the daisyUI tab strip and both boards; both live in
  the DOM, the active one is shown.

### New Stimulus controller: `leaderboard-tabs`

- Toggles which board is visible on tab click.
- **Persists the active tab in `location.hash`** (e.g. `#r16`) and restores it in
  `connect()`. This is what survives the live-update morph: a morph refresh
  re-GETs the page and reconnects Stimulus controllers, so reading the hash on
  connect re-selects the tab the player was on. This mirrors the existing pattern
  where `leaderboard-highlight` re-applies its state on every reconnect rather
  than relying on server-rendered state surviving the morph.
- No server round-trip to switch tabs; the hash is client-only and is not sent to
  the server on the morph re-GET.

## Live-Update Contract (must not break)

The existing mechanism is unchanged: `ScoreFixtureJob` calls
`broadcast_refresh_to("results")`; `/leaderboard` subscribes via
`turbo_stream_from "results"` and re-GETs itself, morphing the diff. Both tables
re-render server-side with the viewer's own session (correct own-row highlight).
The only addition is client-side tab persistence layered on top.

## Testing

- **Service (`test/services/leaderboard_service_test.rb`):**
  - R16 board sums only R16+ `points_awarded`; group and R32 points are excluded.
  - R16 board applies **no** champion bonus even when the final is finished.
  - A player with predictions only in group/R32 appears on the R16 board with
    0 points (not dropped).
  - Tie ranking on the R16 board matches the Overall ranking rules.
  - Per-variant cache keys are independent; `expire_rows` clears both.
- **Controller (`test/controllers/leaderboards_controller_test.rb`):** `show`
  assigns both `@overall_rows` and `@r16_rows`; both tables render with unique
  ids.
- **System (`test/system/…`):** switching to "From R16" shows the R16 standings;
  the selected tab persists across a live-update morph (score a fixture, tab
  stays on "From R16").

## Out of Scope (YAGNI)

- Per-variant "smart" cache expiry (deciding which board a prediction touches).
- A third board or arbitrary stage ranges — only Overall and R16 exist.
- Any change to the scoring math itself (`ScoringService` is untouched).
- Champion bonus on the R16 board.
