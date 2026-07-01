# R16-Onward Second Leaderboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second leaderboard that scores only Round-of-16-onward fixtures, shown as a "From R16" tab beside the existing "Overall" board on `/leaderboard`.

**Architecture:** Make the existing `LeaderboardService` variant-aware (an `:overall` and an `:r16` variant driven by a small config: a stage floor + a champion-bonus flag). The `:r16` variant gates every SQL aggregate on `fixtures.stage >= r16` *inside* the `CASE`/`SUM` expressions (never a `WHERE`, so all players stay listed) and awards no champion bonus. The controller assigns both boards; one shared `_board` partial renders each; a Stimulus `leaderboard-tabs` controller toggles panels and remembers the active tab in the URL hash so it survives the live-update morph.

**Tech Stack:** Rails 8, Ruby 3.3.10, Solid Cache, Hotwire (Turbo morph refresh + Stimulus), daisyUI/Tailwind, Minitest.

## Global Constraints

- Ruby 3.3.10 / Rails 8. Every task's constraints implicitly include this section.
- **Verification gate is `bin/rails test`** (unit + controller + integration). Do **NOT** rely on `bin/rails test:system` — browser/system tests are known-broken locally per `docs/superpowers/specs/2026-06-26-reactive-ui-morphing-design.md`. System tests in this plan are written for CI.
- Run `bin/rubocop` before every commit. Style is `rubocop-rails-omakase`: **spaces inside array/hash literal brackets** — write `[ a, b ]` and `{ a: 1 }`, not `[a, b]`.
- All scoring math stays in `ScoringService`. Leaderboard code only **sums the persisted `points_awarded`** — it never computes points.
- **R16 scope = `fixtures.stage >= Fixture.stages[:r16]`** (integer `2`). This excludes the group stage **and** the Round of 32. The R16 board awards **no** champion bonus.
- Do not break the live-update contract: `leaderboards/show` keeps `turbo_stream_from "results"`; `ScoreFixtureJob` keeps `broadcast_refresh_to("results")`.
- `LeaderboardService.expire_rows` stays **no-arg**. Its callers (`Prediction#after_commit`, `User#after_commit`, `ScoreFixtureJob`, `KnockoutReset`) are **not** modified.

---

### Task 1: Variant-aware `LeaderboardService`

**Files:**
- Modify: `app/services/leaderboard_service.rb`
- Test: `test/services/leaderboard_service_test.rb`

**Interfaces:**
- Produces:
  - `LeaderboardService::VARIANTS` — frozen Hash: `{ overall: { min_stage: nil, champion_bonus: true }, r16: { min_stage: Fixture.stages[:r16], champion_bonus: false } }`.
  - `LeaderboardService.fetch_rows(variant: :overall)` → `Array<Row>` (cached per variant at `"leaderboard/rows/#{variant}"`).
  - `LeaderboardService.new(min_stage: nil, champion_bonus: true)` — keyword-only, both defaulted so `LeaderboardService.new` still means the overall board.
  - `LeaderboardService.expire_rows` → deletes every variant's cache key. No-arg (unchanged signature).
  - `Row` is unchanged: `Data.define(:rank, :user, :total_points, :predictions_count, :exact_count, :diff_count, :tendency_count)`.

- [ ] **Step 1: Write the failing tests**

Append these tests to `test/services/leaderboard_service_test.rb`, immediately **before** the closing `private` section (the `private` / `def with_memory_cache` block stays last):

```ruby
  # --- R16-onward board (variant: :r16) --------------------------------------
  # setup rescored finished_group (a GROUP fixture) to 4 pts for users(:two);
  # those points must never appear on the R16 board.

  test "the r16 board scores only round-of-16-onward fixtures" do
    r16 = Fixture.create!(
      home_team: teams(:brazil), away_team: teams(:france), stadium: stadia(:azteca),
      kickoff_at: 1.day.ago, stage: :r16, status: :finished, home_score: 3, away_score: 1
    )
    # save!(validate: false) mirrors how a YAML fixture loads a prediction on an
    # already-locked fixture — the open-for-predictions validation would block it.
    Prediction.new(user: users(:two), fixture: r16, home_score: 3, away_score: 1).save!(validate: false)
    ScoringService.score_fixture!(r16) # exact 3-1 -> 4 pts

    two = LeaderboardService.new(**LeaderboardService::VARIANTS[:r16]).rows.find { |row| row.user == users(:two) }

    assert_equal 4, two.total_points      # only the R16 fixture, NOT the group's 4
    assert_equal 1, two.predictions_count # the group prediction is excluded from the count
    assert_equal 1, two.exact_count
  end

  test "the r16 board excludes round-of-32 fixtures" do
    r32 = Fixture.create!(
      home_team: teams(:brazil), away_team: teams(:france), stadium: stadia(:azteca),
      kickoff_at: 1.day.ago, stage: :r32, status: :finished, home_score: 2, away_score: 1
    )
    Prediction.new(user: users(:two), fixture: r32, home_score: 2, away_score: 1).save!(validate: false)
    ScoringService.score_fixture!(r32)

    two = LeaderboardService.new(**LeaderboardService::VARIANTS[:r16]).rows.find { |row| row.user == users(:two) }

    assert_equal 0, two.total_points      # R32 is before R16, so it is excluded
    assert_equal 0, two.predictions_count
  end

  test "the r16 board lists every player, at zero when they have no r16 predictions" do
    rows = LeaderboardService.new(**LeaderboardService::VARIANTS[:r16]).rows

    assert_equal User.count, rows.size
    assert(rows.all? { |row| row.total_points.zero? }, "no one has an R16 fixture yet")
  end

  test "the r16 board awards no champion bonus" do
    # Brazil wins the final; users(:two) picked brazil -> +10 on the OVERALL board.
    Fixture.create!(
      home_team: teams(:brazil), away_team: teams(:france), stadium: stadia(:azteca),
      kickoff_at: 1.day.ago, stage: :final, status: :finished, home_score: 2, away_score: 0
    )

    overall = LeaderboardService.new.rows.find { |row| row.user == users(:two) }
    r16 = LeaderboardService.new(**LeaderboardService::VARIANTS[:r16]).rows.find { |row| row.user == users(:two) }

    assert_equal 4 + ScoringService::CHAMPION_BONUS, overall.total_points
    assert_equal 0, r16.total_points # users(:two) did not predict the final, and gets NO bonus
  end

  test "fetch_rows caches each variant independently and expire_rows clears both" do
    with_memory_cache do
      overall_key = "#{LeaderboardService::CACHE_KEY}/overall"
      r16_key = "#{LeaderboardService::CACHE_KEY}/r16"

      LeaderboardService.fetch_rows(variant: :overall)
      LeaderboardService.fetch_rows(variant: :r16)
      assert Rails.cache.exist?(overall_key)
      assert Rails.cache.exist?(r16_key)

      LeaderboardService.expire_rows
      assert_not Rails.cache.exist?(overall_key)
      assert_not Rails.cache.exist?(r16_key)
    end
  end
```

Then update the one existing test that reads the bare cache key so it stays meaningful under per-variant keys. Replace this test body:

```ruby
  test "saving a prediction or creating a user expires the cached rows" do
    with_memory_cache do
      LeaderboardService.fetch_rows
      predictions(:one_upcoming).update!(home_score: 5) # after_commit expires
      assert_nil Rails.cache.read(LeaderboardService::CACHE_KEY)

      LeaderboardService.fetch_rows
      User.create!(name: "Newbie", email_address: "new@example.com", password: "password")
      assert_nil Rails.cache.read(LeaderboardService::CACHE_KEY)
    end
  end
```

with (only the two `read` lines change — they now target the composed `:overall` key):

```ruby
  test "saving a prediction or creating a user expires the cached rows" do
    with_memory_cache do
      overall_key = "#{LeaderboardService::CACHE_KEY}/overall"

      LeaderboardService.fetch_rows
      predictions(:one_upcoming).update!(home_score: 5) # after_commit expires
      assert_nil Rails.cache.read(overall_key)

      LeaderboardService.fetch_rows
      User.create!(name: "Newbie", email_address: "new@example.com", password: "password")
      assert_nil Rails.cache.read(overall_key)
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/services/leaderboard_service_test.rb`
Expected: FAIL — the new r16 tests error with `ArgumentError: wrong number of arguments` (from `LeaderboardService.new(min_stage:…)` and `fetch_rows(variant: :r16)`), and/or `NameError: uninitialized constant LeaderboardService::VARIANTS`.

- [ ] **Step 3: Rewrite the service to be variant-aware**

Replace the entire contents of `app/services/leaderboard_service.rb` with:

```ruby
# Builds a ranked leaderboard in two queries (one grouped aggregate over
# users+predictions, one pluck for champion picks) — no N+1.
#
# Two board variants share this code:
#   :overall — the whole tournament, with the champion bonus.
#   :r16     — Round-of-16-onward fixtures only (stage >= r16, so group AND the
#              Round of 32 are excluded), with NO champion bonus.
class LeaderboardService
  Row = Data.define(:rank, :user, :total_points, :predictions_count, :exact_count, :diff_count, :tendency_count)

  # min_stage: nil means "all stages". champion_bonus toggles the final-winner
  # +10. Referencing Fixture.stages[:r16] keeps the floor in sync with the enum.
  VARIANTS = {
    overall: { min_stage: nil, champion_bonus: true },
    r16: { min_stage: Fixture.stages[:r16], champion_bonus: false }
  }.freeze

  CACHE_KEY = "leaderboard/rows"
  # NOTE: short TTL is only a safety net — Prediction/User after_commit hooks
  # and ScoreFixtureJob expire the keys eagerly on every relevant change.
  CACHE_TTL = 1.minute

  # Cached entry point used by the leaderboard page and the broadcast job.
  # Backed by Solid Cache, so each board is computed once per change (or per
  # minute) instead of on every page view. Keys are per-variant.
  def self.fetch_rows(variant: :overall)
    config = VARIANTS.fetch(variant)
    Rails.cache.fetch("#{CACHE_KEY}/#{variant}", expires_in: CACHE_TTL) { new(**config).rows }
  end

  # Expire every variant. A single prediction/result change can affect either
  # board, and recomputing an unaffected board just reproduces identical rows,
  # so we clear all keys rather than reason about which board changed.
  def self.expire_rows
    VARIANTS.each_key { |variant| Rails.cache.delete("#{CACHE_KEY}/#{variant}") }
  end

  def initialize(min_stage: nil, champion_bonus: true)
    @min_stage = min_stage
    @champion_bonus = champion_bonus
  end

  # Returns an array of Row, ordered by total points (champion bonus included
  # once the final is finished, when this variant awards it) with standard
  # competition ranking ("1224") on equal points. NOTE: assumption — ties share
  # a rank based on total points only; the secondary ordering (exact count desc,
  # then name asc) is for a stable display order and does not affect rank.
  def rows
    bonus_user_ids = @champion_bonus ? champion_bonus_user_ids : Set.new

    ranked = aggregated_users.map do |user|
      bonus = bonus_user_ids.include?(user.id) ? ScoringService::CHAMPION_BONUS : 0
      { user: user, total_points: user.prediction_points + bonus }
    end

    ranked.sort_by! { |row| [ -row[:total_points], -row[:user].exact_count, row[:user].name ] }

    previous = nil
    ranked.each_with_index.map do |row, index|
      rank = (previous && previous[:total_points] == row[:total_points]) ? previous[:rank] : index + 1
      previous = { total_points: row[:total_points], rank: rank }

      user = row[:user]
      Row.new(
        rank: rank,
        user: user,
        total_points: row[:total_points],
        predictions_count: user.predictions_count,
        exact_count: user.exact_count,
        diff_count: user.diff_count,
        tendency_count: user.tendency_count
      )
    end
  end

  private

  # The overall board keeps its lean predictions-only join (the hot path). The
  # r16 board also joins the fixture so aggregates can be gated by stage.
  def aggregated_users
    relation = @min_stage ? User.left_joins(predictions: :fixture) : User.left_joins(:predictions)
    relation.group("users.id").select(
      "users.*",
      sum_where("predictions.points_awarded", as: "prediction_points"),
      count_where("predictions.id IS NOT NULL", as: "predictions_count"),
      count_where("predictions.points_awarded = #{ScoringService::EXACT_POINTS}", as: "exact_count"),
      count_where("predictions.points_awarded = #{ScoringService::DIFFERENCE_POINTS}", as: "diff_count"),
      count_where("predictions.points_awarded = #{ScoringService::TENDENCY_POINTS}", as: "tendency_count")
    )
  end

  # SQL predicate limiting aggregates to in-scope fixtures, or nil for "all".
  # Gating lives inside the SUM/COUNT CASE expressions (below), never in a WHERE,
  # so a player with no in-scope predictions still appears with a correct 0
  # rather than being dropped by the join.
  def stage_gate
    "fixtures.stage >= #{@min_stage}" if @min_stage
  end

  # SUM(expr) over in-scope predictions; 0 when there are none.
  def sum_where(expr, as:)
    inner = stage_gate ? "CASE WHEN #{stage_gate} THEN #{expr} END" : expr
    "COALESCE(SUM(#{inner}), 0) AS #{as}"
  end

  # Count of in-scope predictions matching condition; 0 when there are none.
  def count_where(condition, as:)
    full = [ stage_gate, condition ].compact.join(" AND ")
    "COALESCE(SUM(CASE WHEN #{full} THEN 1 ELSE 0 END), 0) AS #{as}"
  end

  # See ScoringService.champion_team_id for the bonus representation decision.
  def champion_bonus_user_ids
    champion_id = ScoringService.champion_team_id
    return Set.new if champion_id.nil?

    ChampionPick.where(team_id: champion_id).pluck(:user_id).to_set
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services/leaderboard_service_test.rb`
Expected: PASS (all tests, including the existing overall-board, ranking, caching, and N+1 tests, which are unchanged in behavior — `predictions_count` still equals `COUNT(predictions.id)`, and `LeaderboardService.new` still means the overall board).

- [ ] **Step 5: Lint**

Run: `bin/rubocop app/services/leaderboard_service.rb test/services/leaderboard_service_test.rb`
Expected: no offenses.

- [ ] **Step 6: Commit**

```bash
git add app/services/leaderboard_service.rb test/services/leaderboard_service_test.rb
git commit -m "feat: variant-aware leaderboard service (overall + R16-onward)"
```

---

### Task 2: Controller assigns both boards; tabbed views render them

**Files:**
- Modify: `app/controllers/leaderboards_controller.rb`
- Create: `app/views/leaderboards/_board.html.erb`
- Modify: `app/views/leaderboards/_table.html.erb`
- Modify: `app/views/leaderboards/show.html.erb`
- Test: `test/controllers/leaderboards_controller_test.rb`

**Interfaces:**
- Consumes (from Task 1): `LeaderboardService.fetch_rows(variant: :overall)` and `fetch_rows(variant: :r16)`, each returning `Array<Row>`.
- Produces (consumed by Task 3): DOM contract on `/leaderboard` —
  - root `div[data-controller="leaderboard-tabs"]`
  - two tab buttons `button[data-leaderboard-tabs-target="tab"][data-board="overall"|"r16"][data-action="leaderboard-tabs#select"]`
  - two panels `div[data-leaderboard-tabs-target="panel"][data-board="overall"|"r16"]`; the `r16` panel starts with the `hidden` attribute.
  - table root ids: `#leaderboard-table` (overall) and `#leaderboard-table-r16` (R16).
- `_table.html.erb` gains an optional `id:` local (default `"leaderboard-table"`).

- [ ] **Step 1: Write/adjust the failing controller tests**

In `test/controllers/leaderboards_controller_test.rb`, in the test **"renders the leaderboard with the broadcast target and stream subscription"**, replace this block:

```ruby
    assert_select "#leaderboard-table"
    assert_select "#leaderboard-table tbody tr", count: User.count
    # users(:two) has the scored prediction (5 pts fixture data) so appears with points
    assert_select "tr[data-current-user='true']", count: 1
    assert_select "tr[data-current-user='true']", text: /You/
    # Contract with leaderboard_highlight_controller.js: the layout exposes the
    # viewer's id and every row is addressable by user id.
    assert_select "meta[name='current-user-id'][content=?]", users(:two).id.to_s
    assert_select "#leaderboard-table[data-controller='leaderboard-highlight']"
    assert_select "tr[data-user-id=?]", users(:two).id.to_s, count: 1
```

with:

```ruby
    assert_select "#leaderboard-table"
    assert_select "#leaderboard-table tbody tr", count: User.count
    # Own-row assertions are scoped to the Overall table: the viewer's row now
    # appears on both boards, so an unscoped selector would match twice.
    assert_select "#leaderboard-table tr[data-current-user='true']", count: 1
    assert_select "#leaderboard-table tr[data-current-user='true']", text: /You/
    # Contract with leaderboard_highlight_controller.js: the layout exposes the
    # viewer's id and every row is addressable by user id.
    assert_select "meta[name='current-user-id'][content=?]", users(:two).id.to_s
    assert_select "#leaderboard-table[data-controller='leaderboard-highlight']"
    assert_select "#leaderboard-table tr[data-user-id=?]", users(:two).id.to_s, count: 1

    # Second board (From R16) renders alongside the overall board, with tabs.
    assert_select "[data-controller='leaderboard-tabs']"
    assert_select "[data-leaderboard-tabs-target='tab'][data-board='overall']", text: "Overall"
    assert_select "[data-leaderboard-tabs-target='tab'][data-board='r16']", text: "From R16"
    assert_select "[data-leaderboard-tabs-target='panel'][data-board='r16'][hidden]"
    assert_select "#leaderboard-table-r16 tbody tr", count: User.count
    assert_select "#leaderboard-table-r16[data-controller='leaderboard-highlight']"
```

In the test **"ranks users by total points with medal flair for the leader"**, replace:

```ruby
    assert_select "tbody tr:first-child", text: /🥇/
    assert_select "tr[data-current-user='true']", count: 1
```

with (scope both to the Overall table, since two boards now render):

```ruby
    assert_select "#leaderboard-table tbody tr:first-child", text: /🥇/
    assert_select "#leaderboard-table tr[data-current-user='true']", count: 1
```

Leave every other test in this file unchanged (the direct `_table` partial renders pass no `id:`, so they keep the default `#leaderboard-table`; the link/podium tests assert presence/absence that holds on both boards).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/leaderboards_controller_test.rb`
Expected: FAIL — no `[data-controller='leaderboard-tabs']`, no `#leaderboard-table-r16`, and the current single-table page makes the new assertions error.

- [ ] **Step 3: Assign both boards in the controller**

Replace the contents of `app/controllers/leaderboards_controller.rb` with:

```ruby
class LeaderboardsController < ApplicationController
  # NOTE: routes define `resource :leaderboard, only: :show` (singular), so the
  # action is #show rather than #index. Live updates arrive via the "results"
  # Turbo Stream refresh broadcast from ScoreFixtureJob.
  def show
    @overall_rows = LeaderboardService.fetch_rows(variant: :overall)
    @r16_rows = LeaderboardService.fetch_rows(variant: :r16)
  end
end
```

- [ ] **Step 4: Parameterize the table id in `_table.html.erb`**

In `app/views/leaderboards/_table.html.erb`, update the leading comment lines describing the id and locals. Replace:

```erb
    - id="leaderboard-table" is retained ONLY so the leaderboard-highlight
      Stimulus controller can scope to this element (do not add a targeted
      broadcast back).
```

with:

```erb
    - The table root id (default "leaderboard-table"; override with the `id:`
      local) exists so the leaderboard-highlight Stimulus controller can scope to
      this element. Two boards render on one page, so each MUST get a unique id.
```

Then replace:

```erb
    - locals: rows (Array<LeaderboardService::Row>) and current_user. The server
```

with:

```erb
    - locals: rows (Array<LeaderboardService::Row>), current_user, and optional
      id (the table root's DOM id, default "leaderboard-table"). The server
```

Then change the table root element. Replace:

```erb
<div id="leaderboard-table" data-controller="leaderboard-highlight">
```

with:

```erb
<div id="<%= local_assigns.fetch(:id, "leaderboard-table") %>" data-controller="leaderboard-highlight">
```

- [ ] **Step 5: Create the shared `_board.html.erb` partial**

Create `app/views/leaderboards/_board.html.erb`:

```erb
<%# One leaderboard board: top-3 podium (when there are 3+ players) + the
    standings table. Rendered once per tab by leaderboards/show.html.erb.
    locals:
      rows          Array<LeaderboardService::Row> — this board's ranked rows
      current_user  the viewer (for own-row highlight), or nil in a broadcast
      table_id      unique DOM id for the table root (two boards share one page) %>
<% top3 = rows.first(3) %>

<div class="space-y-8">
  <% if top3.size == 3 %>
    <%# Podium — gold, silver, bronze left-to-right, equal height. %>
    <section aria-label="Top three players" class="grid grid-cols-3 gap-3 sm:gap-4">
      <% [ [ top3[0], "podium-gold", "🥇" ], [ top3[1], "podium-silver", "🥈" ], [ top3[2], "podium-bronze", "🥉" ] ].each do |player, klass, medal| %>
        <div class="<%= klass %> p-4 text-center sm:p-5">
          <div class="text-2xl sm:text-3xl" aria-hidden="true"><%= medal %></div>
          <p class="mt-2 truncate text-sm font-bold sm:text-base" title="<%= player.user.name %>"><%= player_predictions_link(player.user, viewer: current_user, name: player.user.name.split.first) %></p>
          <p class="mt-1 leading-none">
            <span class="text-2xl font-extrabold tabular-nums sm:text-3xl"><%= player.total_points %></span>
            <span class="block text-xs font-medium opacity-80">pts</span>
          </p>
        </div>
      <% end %>
    </section>
  <% end %>

  <section class="card bg-base-100 shadow-card rounded-2xl overflow-hidden">
    <div class="card-body p-0">
      <%= render "table", rows: rows, current_user: current_user, id: table_id %>
    </div>
  </section>
</div>
```

- [ ] **Step 6: Rewrite `show.html.erb` with the tab strip and two panels**

Replace the entire contents of `app/views/leaderboards/show.html.erb` with:

```erb
<% content_for :title, "Leaderboard" %>

<%# Subscribe to live updates: ScoreFixtureJob broadcasts a refresh to "results"
    after scoring, so this page re-GETs itself and morphs the new standings. %>
<%= turbo_stream_from "results" %>

<%# Two boards on one page. The leaderboard-tabs controller toggles the panels
    and remembers the active tab in the URL hash so the choice survives the
    morph refresh (the morph resets each panel's `hidden` to its server default). %>
<div class="space-y-8" data-controller="leaderboard-tabs">
  <header class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
    <div>
      <h1 class="page-title text-3xl font-extrabold uppercase tracking-tight sm:text-4xl">Leaderboard</h1>
      <p class="mt-1 text-sm text-base-content/60">
        World Cup 2026 &middot; Live standings
      </p>
    </div>
    <span class="inline-flex items-center gap-2 self-start rounded-full border border-pitch/40 px-3 py-1.5 text-xs font-semibold text-pitch">
      <span class="inline-block h-2 w-2 animate-pulse rounded-full bg-pitch"></span>
      Updates live
    </span>
  </header>

  <div role="tablist" class="tabs tabs-boxed self-start">
    <button type="button" role="tab"
            class="tab tab-active"
            data-leaderboard-tabs-target="tab"
            data-board="overall"
            data-action="leaderboard-tabs#select"
            aria-selected="true">Overall</button>
    <button type="button" role="tab"
            class="tab"
            data-leaderboard-tabs-target="tab"
            data-board="r16"
            data-action="leaderboard-tabs#select"
            aria-selected="false">From R16</button>
  </div>

  <div data-leaderboard-tabs-target="panel" data-board="overall">
    <%= render "board", rows: @overall_rows, current_user: Current.user, table_id: "leaderboard-table" %>
  </div>

  <div data-leaderboard-tabs-target="panel" data-board="r16" hidden>
    <%= render "board", rows: @r16_rows, current_user: Current.user, table_id: "leaderboard-table-r16" %>
  </div>
</div>
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/leaderboards_controller_test.rb`
Expected: PASS (all tests).

- [ ] **Step 8: Run the full suite to confirm no regressions**

Run: `bin/rails test`
Expected: PASS (0 failures, 0 errors). This covers the dashboard, jobs, and other suites that touch `LeaderboardService`.

- [ ] **Step 9: Lint**

Run: `bin/rubocop app/controllers/leaderboards_controller.rb app/views/leaderboards test/controllers/leaderboards_controller_test.rb`
Expected: no offenses. (Note: `.html.erb` files are not covered by rubocop; the command lints the Ruby files. No error if erb paths are simply ignored.)

- [ ] **Step 10: Commit**

```bash
git add app/controllers/leaderboards_controller.rb app/views/leaderboards test/controllers/leaderboards_controller_test.rb
git commit -m "feat: render Overall and From-R16 leaderboards as tabs"
```

---

### Task 3: `leaderboard-tabs` Stimulus controller + tab persistence

**Files:**
- Create: `app/javascript/controllers/leaderboard_tabs_controller.js`
- Create: `test/system/leaderboard_tabs_test.rb`

**Interfaces:**
- Consumes (from Task 2): the DOM contract — `tab`/`panel` targets each carrying `data-board`, tab buttons wired to `leaderboard-tabs#select`, the `r16` panel starting `hidden`, table ids `#leaderboard-table` / `#leaderboard-table-r16`.
- Auto-registration: `eagerLoadControllersFrom("controllers", …)` maps `leaderboard_tabs_controller.js` to `data-controller="leaderboard-tabs"`. No manual registration needed.

- [ ] **Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/leaderboard_tabs_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Two-tab switch for the leaderboard: "Overall" and "From R16".
//
// The active tab lives in the URL hash (#overall / #r16), NOT in the DOM, so it
// survives the live-update morph. ScoreFixtureJob broadcasts a refresh to
// "results"; the page re-GETs itself and Turbo morphs the server HTML back in,
// which resets each panel's `hidden` attribute to its server default (Overall
// shown, R16 hidden). A morph keeps this controller's element in place, so
// connect() does NOT re-run — we re-apply the hash-selected board on every
// turbo:render instead, keeping the player on the tab they chose.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.reapply = this.reapply.bind(this)
    this.reapply()
    document.addEventListener("turbo:render", this.reapply)
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.reapply)
  }

  // Tab click handler.
  select(event) {
    const board = event.currentTarget.dataset.board
    // replaceState (not `location.hash =`) so the browser does not scroll to an
    // element whose id happens to match the fragment.
    history.replaceState(history.state, "", `#${board}`)
    this.show(board)
  }

  reapply() {
    this.show(this.#activeBoard())
  }

  show(board) {
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.board !== board
    })
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.board === board
      tab.classList.toggle("tab-active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })
  }

  // The board named by the URL hash, or "overall" when the hash is absent or
  // does not match a known tab.
  #activeBoard() {
    const fromHash = window.location.hash.replace("#", "")
    const known = this.tabTargets.some((tab) => tab.dataset.board === fromHash)
    return known ? fromHash : "overall"
  }
}
```

- [ ] **Step 2: Create the system test (CI-verified)**

Create `test/system/leaderboard_tabs_test.rb`:

```ruby
require "application_system_test_case"

class LeaderboardTabsTest < ApplicationSystemTestCase
  # NOTE: local system/browser tests are known-broken in this project (see
  # docs/superpowers/specs/2026-06-26-reactive-ui-morphing-design.md). These run
  # in CI; `bin/rails test` is the local verification gate.

  test "switching to From R16 shows the R16 board and records the choice in the URL hash" do
    sign_in_through_ui(users(:two))
    visit leaderboard_path

    # Overall is the default board; the R16 board is hidden.
    assert_selector "#leaderboard-table"
    assert_no_selector "#leaderboard-table-r16"

    click_on "From R16"

    assert_selector "#leaderboard-table-r16"
    assert_no_selector "#leaderboard-table"
    assert_equal "#r16", page.evaluate_script("window.location.hash")
  end

  test "the From R16 tab is restored from the URL hash on load" do
    sign_in_through_ui(users(:two))
    # Landing with #r16 is the state a live-update morph leaves behind; the
    # controller re-selects the R16 board from the hash on connect/render.
    visit "#{leaderboard_path}#r16"

    assert_selector "#leaderboard-table-r16"
    assert_no_selector "#leaderboard-table"
  end
end
```

- [ ] **Step 3: Verify the controller loads (local sanity check without system tests)**

The behavior can't be exercised by `bin/rails test` (no browser). Do a quick manual verification that nothing is broken and the tabs work:

Run: `bin/dev`
Then in a browser at `http://localhost:3000/leaderboard` (sign in as `demo@pitchpredict.app` / `worldcup2026`):
Expected: "Overall" and "From R16" tabs appear; clicking "From R16" swaps the table and the URL gains `#r16`; reloading the page at `…/leaderboard#r16` opens on the From R16 board. Stop with Ctrl-C.

(If a browser isn't available, this step is satisfied by CI running the system test in Step 2. Do not block the task on local `test:system`.)

- [ ] **Step 4: Lint**

Run: `bin/rubocop test/system/leaderboard_tabs_test.rb`
Expected: no offenses. (JS files are not linted by rubocop.)

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/leaderboard_tabs_controller.js test/system/leaderboard_tabs_test.rb
git commit -m "feat: leaderboard tab switching with hash-persisted selection"
```

---

## Self-Review

**Spec coverage** (against `docs/superpowers/specs/2026-07-01-r16-leaderboard-design.md`):
- Scope = R16 onward, excludes group + R32 → Task 1 (`stage_gate` = `fixtures.stage >= Fixture.stages[:r16]`; tests assert R32 excluded). ✅
- No champion bonus on R16 → Task 1 (`champion_bonus: false`; test "awards no champion bonus"). ✅
- All players listed at 0 when no R16 preds → Task 1 (gating inside aggregates, not WHERE; test "lists every player… at zero"). ✅
- Two variants, per-variant cache keys, `expire_rows` clears both, callers unchanged → Task 1 (`VARIANTS`, `fetch_rows(variant:)`, `expire_rows`; caching test). ✅
- Controller assigns both boards → Task 2. ✅
- `_board` partial extraction; `_table` unique id → Task 2. ✅
- Tabs UI on one page → Task 2 (markup) + Task 3 (behavior). ✅
- Tab persists across live-update morph → Task 3 (`turbo:render` re-apply + hash). ✅
- Overall query/hot path unchanged → Task 1 (conditional join; `predictions_count` yields identical values). ✅
- Tests: service, controller, system → Tasks 1–3. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code and every command shows expected output. ✅

**Type/name consistency:** `VARIANTS`, `fetch_rows(variant:)`, `new(min_stage:, champion_bonus:)`, `stage_gate`, `sum_where`, `count_where`, `Row`, the `data-board`/target/id DOM contract, and `select`/`reapply`/`show`/`#activeBoard` are used identically across tasks. ✅
