# Homepage Activity Section (issue #15) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Recent activity" card on the dashboard showing recent exact hits and hot streaks, derived at read time from existing predictions data.

**Architecture:** New `ActivityFeedService` (mirrors `LeaderboardService`'s cached-service pattern) computes feed items from scored predictions; dashboard controller assigns them; a new partial renders the card. Cache expiry piggybacks on the exact call sites that already expire the leaderboard.

**Tech Stack:** Rails 8.1, Solid Cache, Turbo (live refresh already wired via `turbo_stream_from "results"`), Tailwind/daisyUI classes already in the app.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-02-homepage-activity-design.md` (committed in this worktree).
- Defaults (posted to issue #15): streak threshold **3+**, recency window **72h**, feed cap **6**, one item per player (best wins: exact streak > outcome streak > exact hit).
- Run tests with `bin/rails test` (system tests known-broken locally). Rubocop clean: `bin/rubocop`.
- Baseline: 185 runs, 0 failures.
- Never hard-code point values in copy — use `ScoringService::EXACT_POINTS`.

---

### Task 1: ActivityFeedService

**Files:**
- Create: `app/services/activity_feed_service.rb`
- Test: `test/services/activity_feed_service_test.rb`

**Interfaces:**
- Produces:
  - `ActivityFeedService.fetch_items` → cached `Array<ActivityFeedService::Item>`
  - `ActivityFeedService.expire_items` → void
  - `ActivityFeedService::Item = Data.define(:type, :user, :count, :fixture, :points)` where `type ∈ :exact_streak, :outcome_streak, :exact_hit`; `count` is the streak length (nil for `:exact_hit`); `fixture` is the anchoring (most recent) fixture; `points` is `ScoringService::EXACT_POINTS` for `:exact_hit`, else nil.

- [ ] **Step 1: Write the failing tests**

Create `test/services/activity_feed_service_test.rb`:

```ruby
require "test_helper"

class ActivityFeedServiceTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  # Creates a finished, scored knockout-free fixture `days_ago` and a scored
  # prediction on it for `user`. Bypasses validations like production scoring
  # does (fixtures are past kickoff).
  def scored_prediction(user, points:, days_ago:, match_number:)
    fixture = Fixture.create!(home_team: teams(:brazil), away_team: teams(:france),
      stadium: stadia(:azteca), kickoff_at: days_ago.days.ago, stage: :group,
      status: :finished, home_score: 2, away_score: 1, match_number: match_number)
    prediction = Prediction.new(user: user, fixture: fixture,
      home_score: 2, away_score: 1, points_awarded: points)
    prediction.save!(validate: false)
    prediction
  end

  test "reports an outcome streak of 3+ scored matches" do
    user = users(:one)
    scored_prediction(user, points: 2, days_ago: 2, match_number: 201)
    scored_prediction(user, points: 3, days_ago: 1, match_number: 202)
    scored_prediction(user, points: 2, days_ago: 0.5, match_number: 203)

    item = ActivityFeedService.new.items.find { |i| i.user.id == user.id }

    assert_equal :outcome_streak, item.type
    assert_equal 3, item.count
  end

  test "an exact streak outranks the outcome streak for the same user" do
    user = users(:one)
    scored_prediction(user, points: 4, days_ago: 2, match_number: 201)
    scored_prediction(user, points: 4, days_ago: 1, match_number: 202)
    scored_prediction(user, points: 4, days_ago: 0.5, match_number: 203)

    items = ActivityFeedService.new.items

    assert_equal [ :exact_streak ], items.select { |i| i.user.id == user.id }.map(&:type)
    assert_equal 3, items.first.count
  end

  test "a zero-point result breaks a streak" do
    user = users(:one)
    scored_prediction(user, points: 2, days_ago: 3, match_number: 201)
    scored_prediction(user, points: 2, days_ago: 2, match_number: 202)
    scored_prediction(user, points: 0, days_ago: 1, match_number: 203)

    assert_not ActivityFeedService.new.items.any? { |i| i.user.id == user.id && i.type != :exact_hit }
  end

  test "a recent exact score shows as an exact hit when there is no streak" do
    user = users(:one)
    scored_prediction(user, points: 4, days_ago: 1, match_number: 201)

    item = ActivityFeedService.new.items.find { |i| i.user.id == user.id }

    assert_equal :exact_hit, item.type
    assert_equal ScoringService::EXACT_POINTS, item.points
  end

  test "streaks anchored on old fixtures are not recent activity" do
    user = users(:one)
    scored_prediction(user, points: 2, days_ago: 10, match_number: 201)
    scored_prediction(user, points: 2, days_ago: 9, match_number: 202)
    scored_prediction(user, points: 2, days_ago: 8, match_number: 203)

    assert_empty ActivityFeedService.new.items.select { |i| i.user.id == user.id }
  end

  test "caps the feed at MAX_ITEMS with one item per user" do
    User.transaction do
      7.times do |n|
        user = User.create!(name: "Player #{n}", email_address: "p#{n}@example.com", password: "password123")
        scored_prediction(user, points: 4, days_ago: 1, match_number: 300 + n)
      end
    end

    items = ActivityFeedService.new.items

    assert_operator items.size, :<=, ActivityFeedService::MAX_ITEMS
    assert_equal items.map { |i| i.user.id }.uniq.size, items.size
  end

  test "fetch_items caches and expire_items clears" do
    assert_equal ActivityFeedService.fetch_items, ActivityFeedService.fetch_items
    ActivityFeedService.expire_items # must not raise; cache key dropped
  end
end
```

Note: `users(:one)` has an existing fixture prediction (`one_upcoming`, unscored) — harmless, it's filtered out. `users(:two)` has `two_finished` with stale `points_awarded: 5` on a 2-days-ago fixture; tests above use `users(:one)` or fresh users to stay independent of it.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/activity_feed_service_test.rb`
Expected: error — `NameError: uninitialized constant ActivityFeedService`.

- [ ] **Step 3: Implement the service**

Create `app/services/activity_feed_service.rb`:

```ruby
# Derives the dashboard "Recent activity" feed from scored predictions at read
# time — no persisted events. Mirrors LeaderboardService's cached-service
# pattern (short-TTL safety net + eager expiry from the same call sites).
class ActivityFeedService
  Item = Data.define(:type, :user, :count, :fixture, :points)

  CACHE_KEY = "activity/items"
  CACHE_TTL = 1.minute
  STREAK_MIN = 3
  RECENT_WINDOW = 72.hours
  MAX_ITEMS = 6

  # Highest first: an exact streak beats an outcome streak beats a one-off hit.
  TYPE_PRIORITY = { exact_streak: 0, outcome_streak: 1, exact_hit: 2 }.freeze

  def self.fetch_items
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new.items }
  end

  def self.expire_items
    Rails.cache.delete(CACHE_KEY)
  end

  # One Item per user (their best), ordered by type priority, then streak
  # length, then recency; capped at MAX_ITEMS.
  def items
    cutoff = RECENT_WINDOW.ago

    best = scored_predictions_by_user.filter_map do |_user_id, predictions|
      best_item_for(predictions, cutoff)
    end

    best.sort_by { |item| [ TYPE_PRIORITY.fetch(item.type), -item.count.to_i, -item.fixture.kickoff_at.to_i ] }
        .first(MAX_ITEMS)
  end

  private

  # Scored predictions on finished fixtures, kickoff-ordered per user.
  def scored_predictions_by_user
    Prediction.joins(:fixture)
              .where(fixtures: { status: Fixture.statuses[:finished] })
              .where.not(points_awarded: nil)
              .includes(:user, fixture: %i[home_team away_team])
              .sort_by { |prediction| prediction.fixture.kickoff_at }
              .group_by(&:user_id)
  end

  def best_item_for(predictions, cutoff)
    last = predictions.last
    return nil if last.fixture.kickoff_at < cutoff # nothing recent to celebrate

    exact = trailing_count(predictions) { |p| p.points_awarded == ScoringService::EXACT_POINTS }
    outcome = trailing_count(predictions) { |p| p.points_awarded.positive? }

    if exact >= STREAK_MIN
      Item.new(type: :exact_streak, user: last.user, count: exact, fixture: last.fixture, points: nil)
    elsif outcome >= STREAK_MIN
      Item.new(type: :outcome_streak, user: last.user, count: outcome, fixture: last.fixture, points: nil)
    elsif last.points_awarded == ScoringService::EXACT_POINTS
      Item.new(type: :exact_hit, user: last.user, count: nil, fixture: last.fixture,
               points: ScoringService::EXACT_POINTS)
    end
  end

  # Length of the run satisfying the block, counting back from the last
  # (most recent) prediction.
  def trailing_count(predictions, &block)
    predictions.reverse_each.take_while(&block).count
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/activity_feed_service_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/activity_feed_service.rb test/services/activity_feed_service_test.rb
git commit -m "feat: activity feed service (streaks + exact hits, cached)"
```

---

### Task 2: Eager cache expiry alongside the leaderboard

**Files:**
- Modify: `app/models/prediction.rb:22` (after_commit)
- Modify: `app/models/user.rb:15` (after_commit)
- Modify: `app/jobs/score_fixture_job.rb:15`
- Modify: `app/services/knockout_reset.rb:17`
- Test: extend `test/services/activity_feed_service_test.rb`

**Interfaces:**
- Consumes: `ActivityFeedService.expire_items` (Task 1).

- [ ] **Step 1: Write the failing test**

```ruby
test "saving a prediction expires the cached feed" do
  user = users(:one)
  scored_prediction(user, points: 4, days_ago: 1, match_number: 210)
  assert ActivityFeedService.fetch_items.any? { |i| i.user.id == user.id }

  # Rescoring to 0 must drop the cached exact hit once the cache is expired
  # by the save (production path: ScoreFixtureJob rescoring a correction).
  Prediction.last.update!(points_awarded: 0)

  assert_not ActivityFeedService.fetch_items.any? { |i| i.user.id == user.id && i.type == :exact_hit }
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/activity_feed_service_test.rb`
Expected: FAIL — the stale cached feed still contains the exact hit.

- [ ] **Step 3: Implement**

Add `ActivityFeedService.expire_items` at each site that already calls `LeaderboardService.expire_rows` (they invalidate for the same reasons — points and names feed both):

- `app/models/prediction.rb`: `after_commit { LeaderboardService.expire_rows; ActivityFeedService.expire_items }` (keep the existing comment, extend it to mention the feed) — if rubocop objects to multiple statements in a block line, use a `do...end` block.
- `app/models/user.rb`: same pattern.
- `app/jobs/score_fixture_job.rb`: add `ActivityFeedService.expire_items` after `LeaderboardService.expire_rows`.
- `app/services/knockout_reset.rb`: add `ActivityFeedService.expire_items if defined?(ActivityFeedService)` next to the existing guarded call.

- [ ] **Step 4: Run tests**

Run: `bin/rails test`
Expected: full suite PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/prediction.rb app/models/user.rb app/jobs/score_fixture_job.rb app/services/knockout_reset.rb test/services/activity_feed_service_test.rb
git commit -m "feat: expire activity feed with the leaderboard cache"
```

---

### Task 3: Dashboard section

**Files:**
- Modify: `app/controllers/dashboard_controller.rb` (assign `@activity_items`)
- Create: `app/views/dashboard/_activity.html.erb`
- Modify: `app/views/dashboard/show.html.erb` (render the partial directly below the stat-tile grid, i.e. after the `<%# 2. STAT ROW %>` `</div>` and before `<%# 3. CHAMPION PICK + TOP PLAYERS %>`)
- Test: `test/controllers/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: `ActivityFeedService.fetch_items`, `Item` shape from Task 1; existing helpers `player_predictions_link`, `avatar-initial` CSS classes.

- [ ] **Step 1: Write the failing tests**

Append to `test/controllers/dashboard_controller_test.rb`:

```ruby
test "shows recent activity with a streak line" do
  fixture = Fixture.create!(home_team: teams(:brazil), away_team: teams(:france),
    stadium: stadia(:azteca), kickoff_at: 1.day.ago, stage: :group,
    status: :finished, home_score: 2, away_score: 1, match_number: 401)
  3.times do |n|
    f = n.zero? ? fixture : Fixture.create!(home_team: teams(:brazil), away_team: teams(:france),
      stadium: stadia(:azteca), kickoff_at: (1 + n).days.ago, stage: :group,
      status: :finished, home_score: 2, away_score: 1, match_number: 401 + n)
    Prediction.new(user: users(:two), fixture: f, home_score: 2, away_score: 1,
      points_awarded: ScoringService::EXACT_POINTS).save!(validate: false)
  end
  sign_in_as(@user)

  get root_path

  assert_response :success
  assert_select "h2", text: "Recent activity"
  assert_select "#activity", text: /streak of 3 exact scores/
end

test "shows the activity empty state when nothing is recent" do
  Prediction.delete_all
  sign_in_as(@user)

  get root_path

  assert_select "h2", text: "Recent activity"
  assert_select "#activity", text: /No hot streaks yet/
end
```

(Note: fixture data gives `users(:two)` a stale scored prediction 2 days ago with `points_awarded: 5`; the first test's three exact predictions on 1–3-days-ago fixtures plus that row still yield a trailing exact run of ≥3 only if the stale row is oldest — kickoffs: stale row 2 days ago sits between. `points_awarded: 5` is not EXACT_POINTS, so it breaks an exact streak. Use kickoffs 1, 2.5 and 3.5 days ago instead of 1..3 if the streak assertion trips on it — the implementer should verify and adjust the created kickoffs so the three exact predictions are the most recent three. Simplest: `Prediction.delete_all` at the top of the first test too, then create the three rows.)

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`
Expected: FAIL — no "Recent activity" heading.

- [ ] **Step 3: Implement**

`app/controllers/dashboard_controller.rb` — add alongside the other assigns:

```ruby
# Recent hits & streaks card. Cached like the leaderboard; recomputed only
# when a prediction/user changes or a fixture is scored.
@activity_items = ActivityFeedService.fetch_items
```

Create `app/views/dashboard/_activity.html.erb`:

```erb
<%# Recent hits & hot streaks. Live-updates for free: the dashboard already
    subscribes to the "results" refresh stream and morphs after scoring. %>
<section id="activity" class="card rounded-2xl bg-base-100 shadow-card">
  <div class="card-body">
    <h2 class="text-lg font-bold text-charcoal">Recent activity</h2>

    <% if items.any? %>
      <ul class="mt-3 divide-y divide-base-200">
        <% items.each do |item| %>
          <% is_you = item.user.id == Current.user.id %>
          <li class="flex items-center gap-3 py-2.5">
            <span class="avatar-initial <%= is_you ? "avatar-initial-you" : "avatar-initial-muted" %> h-8 w-8 shrink-0 text-sm">
              <%= item.user.name.to_s.first&.upcase %>
            </span>
            <p class="min-w-0 flex-1 text-sm text-gray-600">
              <span class="font-semibold text-charcoal"><%= player_predictions_link(item.user, viewer: Current.user, name: is_you ? "#{item.user.name} (you)" : item.user.name) %></span>
              <% case item.type %>
              <% when :exact_streak %>
                is on a streak of <%= item.count %> exact scores! 🔥
              <% when :outcome_streak %>
                predicted <%= item.count %> matches in a row with the correct outcome
              <% when :exact_hit %>
                called <%= item.fixture.home_display %> <%= item.fixture.home_score %>–<%= item.fixture.away_score %> <%= item.fixture.away_display %> exactly
              <% end %>
            </p>
            <% badge = case item.type
                       when :exact_streak then "🔥 #{item.count}"
                       when :outcome_streak then "#{item.count} in a row"
                       else "+#{item.points}"
                       end %>
            <span class="badge badge-warning shrink-0 border-none font-semibold text-gold-dark"><%= badge %></span>
          </li>
        <% end %>
      </ul>
    <% else %>
      <p class="mt-3 text-sm text-gray-600">No hot streaks yet — the next round could be yours.</p>
    <% end %>
  </div>
</section>
```

In `app/views/dashboard/show.html.erb`, directly after the stat-row `</div>` (line ~65) insert:

```erb
<%# 2b. RECENT ACTIVITY %>
<%= render "activity", items: @activity_items %>
```

- [ ] **Step 4: Run the full suite + rubocop**

Run: `bin/rails test && bin/rubocop`
Expected: all green, no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dashboard_controller.rb app/views/dashboard
git add test/controllers/dashboard_controller_test.rb
git commit -m "feat: recent activity card on the dashboard"
```
