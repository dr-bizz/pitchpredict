# Fix: points not calculating on knockout fixtures (issue #14)

## Problem

Finished knockout fixtures (e.g. Belgium 3–2 Senegal, Portugal 2–1 Croatia) awarded
no points to anyone, even for exact predictions.

## Root cause (verified by reproduction)

The penalty-shootout feature (PR #12) added to `Prediction`:

```ruby
validates :penalty_winner, presence: true, if: :knockout_draw_predicted?
```

Predictions saved **before** that feature shipped have `penalty_winner: nil`. Any such
prediction that picked a **draw on a knockout fixture** is now invalid.

`ScoringService.score_fixture!` persists points with `prediction.update!`, which re-runs
all validations, inside an all-or-nothing transaction over the fixture's predictions.
One legacy draw prediction therefore:

1. raises `ActiveRecord::RecordInvalid: Penalty winner can't be blank`,
2. rolls back points for **every** prediction on that fixture,
3. kills `ScoreFixtureJob` (only `RecordNotFound` is discarded), so the fixture is
   never scored and no refresh is broadcast.

Reproduced locally: a fixture with one exact prediction (should be 4 pts) and one
legacy nil-`penalty_winner` draw prediction scores nobody.

## Secondary defect (same family)

`ScoringService#outcome` maps a legacy draw prediction (nil winner) to `:draw`, while a
finished knockout always resolves to `:home`/`:away`. A player who predicted 1–1 with no
shootout pick on a match that actually finished 1–1 would score **0** instead of 4/3.
They never had the chance to pick an advancer, so scoring them 0 on a correct scoreline
is wrong.

## Design

### 1. Scoring must not be blocked by user-input validations

In `score_fixture!`, persist points with `save!(validate: false)` (assign
`points_awarded`, then save) instead of `update!`. Points are a system write;
validations exist to guard user input. Callbacks (leaderboard cache expiry via
`after_commit`) still run.

### 2. Fair scoring for legacy knockout-draw predictions

In `points_for`, when the prediction is a knockout draw with `predicted_pen_winner:
nil` (only possible for pre-feature rows — the UI and validation now force a pick),
fall back to score-only comparison against the actual scoreline:

- actual result decisive → 0 (a draw pick was wrong under old rules too),
- actual result level → exact scoreline 4, otherwise 3 (goal difference; a draw always
  matches a draw's difference). The 2-point tier is unreachable — it now means
  "correct advancer", which they never picked.

Implementation: only when `predicted_home == predicted_away` and
`predicted_pen_winner` is nil **and** `actual_pen_winner` is present (i.e. a knockout
decided on penalties), compare without the advancer. For decisive actual results the
existing outcome comparison already yields 0. Group fixtures are untouched (both pen
winners always nil ⇒ behavior identical to today).

### 3. Repair already-broken production data automatically

A **data migration** rescoring every finished fixture inline
(`Fixture.finished.find_each { |f| ScoringService.score_fixture!(f) }`). Migrations run
during Render's build (`bin/render-build.sh`), so the repair needs no console access
(free tier has none). Scoring is idempotent, so re-scoring correctly-scored fixtures is
harmless. Expire leaderboard cache afterwards.

### 4. Tests

- Service test: fixture with a decisive result + one valid exact prediction + one
  legacy nil-winner draw prediction (inserted with `save(validate: false)`) → no raise,
  exact prediction gets 4, legacy gets 0.
- Service test: level knockout result decided on pens + legacy draw prediction with the
  exact scoreline → 4; with a different drawn scoreline → 3.
- Service test: post-feature draw prediction with correct/incorrect advancer unchanged
  (regression guard on existing behavior).
- Job test (if present pattern allows): ScoreFixtureJob completes over a mixed set.

## Out of scope

- Backfilling `penalty_winner` on legacy predictions (impossible — the player never picked).
- UI changes.
