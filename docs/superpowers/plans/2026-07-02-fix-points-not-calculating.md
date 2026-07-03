# Fix Points Not Calculating (issue #14) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scoring a finished fixture must never be blocked by a legacy prediction that fails the new `penalty_winner` validation, legacy knockout-draw picks must score fairly, and already-broken production data must repair itself on deploy.

**Architecture:** All changes live in `ScoringService` (persistence + one scoring rule) plus one data migration. No UI, no schema change to existing columns.

**Tech Stack:** Rails 8.1, Minitest fixtures, SQLite (dev/test) / Postgres (prod).

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-02-fix-points-not-calculating-design.md` (committed in this worktree).
- Run tests with `bin/rails test` (non-system suite; system tests are known-broken locally).
- Rubocop must stay clean: `bin/rubocop`.
- Baseline before starting: 185 runs, 0 failures.

---

### Task 1: Scoring survives legacy invalid predictions

**Files:**
- Modify: `app/services/scoring_service.rb` (`score_fixture!`, lines ~35-46)
- Test: `test/services/scoring_service_test.rb`

**Interfaces:**
- Produces: `ScoringService.score_fixture!(fixture)` — unchanged signature, but now persists `points_awarded` with `save!(validate: false)`.

- [ ] **Step 1: Write the failing test**

Append to `test/services/scoring_service_test.rb` (inside the class, near the other `score_fixture!` tests):

```ruby
test "score_fixture! is not blocked by a legacy knockout-draw prediction without a penalty winner" do
  ko = Fixture.create!(home_team: teams(:brazil), away_team: teams(:france),
    stadium: stadia(:azteca), kickoff_at: 1.day.ago, stage: :r32, status: :finished,
    home_score: 2, away_score: 1, match_number: 102)
  exact = Prediction.new(user: users(:one), fixture: ko, home_score: 2, away_score: 1)
  exact.save!(validate: false)
  # Pre-penalty-feature row: a knockout draw pick with no shootout winner.
  # Invalid under today's validations, but real rows like this exist in prod.
  legacy_draw = Prediction.new(user: users(:two), fixture: ko, home_score: 1, away_score: 1)
  legacy_draw.save!(validate: false)

  ScoringService.score_fixture!(ko)

  assert_equal 4, exact.reload.points_awarded
  assert_equal 0, legacy_draw.reload.points_awarded # wrong outcome on a decisive result
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/scoring_service_test.rb`
Expected: 1 failure/error — `ActiveRecord::RecordInvalid: Validation failed: Penalty winner can't be blank`.

- [ ] **Step 3: Write minimal implementation**

In `app/services/scoring_service.rb`, replace the `prediction.update!(...)` call inside `score_fixture!` with a validation-skipping save (points are a system write; validations guard user input, and a legacy row must not block the whole fixture):

```ruby
fixture.transaction do
  fixture.predictions.find_each do |prediction|
    # save!(validate: false), not update!: a legacy prediction that fails
    # today's validations (e.g. a pre-shootout-feature knockout draw with no
    # penalty_winner) must not abort scoring for the whole fixture. Callbacks
    # (leaderboard cache expiry) still run.
    prediction.points_awarded = points_for(
      predicted_home: prediction.home_score,
      predicted_away: prediction.away_score,
      actual_home: fixture.home_score,
      actual_away: fixture.away_score,
      predicted_pen_winner: prediction.penalty_winner,
      actual_pen_winner: fixture.penalty_winner
    )
    prediction.save!(validate: false)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/scoring_service_test.rb`
Expected: PASS, no other test regressions.

- [ ] **Step 5: Commit**

```bash
git add app/services/scoring_service.rb test/services/scoring_service_test.rb
git commit -m "fix: don't let legacy invalid predictions abort fixture scoring"
```

---

### Task 2: Fair scoring for legacy knockout-draw picks

**Files:**
- Modify: `app/services/scoring_service.rb` (`points_for`)
- Test: `test/services/scoring_service_test.rb`

**Interfaces:**
- Consumes/Produces: `ScoringService.points_for(predicted_home:, predicted_away:, actual_home:, actual_away:, predicted_pen_winner: nil, actual_pen_winner: nil)` — unchanged signature, one new rule.

- [ ] **Step 1: Write the failing tests**

```ruby
test "legacy knockout draw pick without a winner scores the scoreline on a pens-decided match" do
  # Rows from before shootout picks existed: the player never chose an advancer,
  # so score the scoreline alone rather than an automatic 0.
  assert_equal 4, ScoringService.points_for(predicted_home: 1, predicted_away: 1,
    actual_home: 1, actual_away: 1, predicted_pen_winner: nil, actual_pen_winner: "home")
  assert_equal 3, ScoringService.points_for(predicted_home: 2, predicted_away: 2,
    actual_home: 1, actual_away: 1, predicted_pen_winner: nil, actual_pen_winner: "home")
end

test "legacy knockout draw pick still scores 0 on a decisive result" do
  assert_equal 0, ScoringService.points_for(predicted_home: 1, predicted_away: 1,
    actual_home: 2, actual_away: 1, predicted_pen_winner: nil, actual_pen_winner: nil)
end
```

- [ ] **Step 2: Run to verify the first test fails**

Run: `bin/rails test test/services/scoring_service_test.rb`
Expected: first new test FAILS (currently returns 0); second already passes (guards the boundary).

- [ ] **Step 3: Implement**

At the top of `points_for`, before the outcome comparison:

```ruby
# Legacy rows: a knockout draw predicted before shootout picks existed has no
# advancer (post-feature saves are forced to pick one). When the match was
# decided on pens, score the scoreline alone — never 0 for a pick the player
# couldn't make, never the advancer tier (2) for a pick they didn't make.
# actual_pen_winner is only ever set on a level knockout score, so goal
# difference always matches a predicted draw here.
if actual_pen_winner.present? && predicted_home == predicted_away && predicted_pen_winner.nil?
  return predicted_home == actual_home ? EXACT_POINTS : DIFFERENCE_POINTS
end
```

(`predicted_home == actual_home` suffices for exactness: both sides are level.)

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/scoring_service_test.rb`
Expected: PASS, including the pre-existing knockout tests ("decisive prediction with the right advancer earns 2", "exact drawn score but wrong advancer earns 0" — both have a non-nil predicted winner or a decisive prediction, so they don't hit the new branch).

- [ ] **Step 5: Commit**

```bash
git add app/services/scoring_service.rb test/services/scoring_service_test.rb
git commit -m "fix: score legacy no-winner draw picks on the scoreline, not an automatic 0"
```

---

### Task 3: Data-repair migration (rescore all finished fixtures on deploy)

**Files:**
- Create: `db/migrate/<timestamp>_rescore_finished_fixtures.rb` (generate with `bin/rails g migration RescoreFinishedFixtures`)

**Interfaces:**
- Consumes: `ScoringService.score_fixture!` (Task 1/2 behavior), `LeaderboardService.expire_rows`.

- [ ] **Step 1: Generate and write the migration**

```ruby
# Data repair for issue #14: fixtures finished while scoring was crashing on
# legacy predictions were never scored. Rescoring is idempotent, so sweeping
# every finished fixture is safe. Runs at deploy time because the Render free
# tier has no console for a manual task.
class RescoreFinishedFixtures < ActiveRecord::Migration[8.1]
  def up
    say_with_time "Rescoring all finished fixtures" do
      Fixture.finished.find_each { |fixture| ScoringService.score_fixture!(fixture) }
      LeaderboardService.expire_rows
    end
  rescue StandardError => e
    # Data repair must never block a deploy — the code fix alone stops the
    # bleeding, and an admin can re-save any result to rescore it.
    say "Rescore skipped: #{e.class}: #{e.message}"
  end

  def down
    # Recomputing points is not reversible (and doesn't need to be).
  end
end
```

- [ ] **Step 2: Run the migration against dev and test**

Run: `bin/rails db:migrate && RAILS_ENV=test bin/rails db:migrate`
Expected: migration runs, "Rescoring all finished fixtures" logged, `db/schema.rb` version bump only.

- [ ] **Step 3: Full suite + rubocop**

Run: `bin/rails test && bin/rubocop`
Expected: all green (185 + new tests), no offenses.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "chore(data): rescore all finished fixtures on deploy"
```
