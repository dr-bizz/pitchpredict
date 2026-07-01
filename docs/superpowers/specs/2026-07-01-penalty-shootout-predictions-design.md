# Penalty Shootout Predictions — Design

**Date:** 2026-07-01
**Status:** Approved, ready for implementation plan

## Problem

Players can predict a scoreline (`home_score`/`away_score`) for every fixture, but
have no way to express what happens when a knockout match ends level. In the World
Cup a drawn knockout match (r32 → final) is decided by a penalty shootout — one team
advances. Today the model captures none of this: a drawn knockout result records only
the level scoreline, there is no record of who went through, and players cannot say
who they think advances.

This feature lets a player, when predicting a knockout match, also pick **who wins the
shootout** if the match ends level, and makes that pick the thing that decides their
points for the match.

## Domain constraints

- Only **knockout** fixtures (`stage` ≠ `group`) can go to a shootout. Group matches
  can end level and stay level, so this feature never applies to them.
- A shootout only happens on a **level scoreline**. "Predicting penalties" therefore
  means predicting a draw *and* naming the team that advances.
- Team advancement in the bracket is already entered manually by admins (setting the
  next match's `home_team_id`/`away_team_id`), so this feature does **not** add any
  automatic advancement. It only records the shootout winner and uses it for scoring.

## Scoring rule (the core decision)

For a knockout match, **"who advances" replaces "home win / draw / away win" as the
outcome**, because a knockout never really ends in a draw — someone always goes through.

Define the **advancer** of a (home, away, pen_winner) triple:

- home score > away score → `home`
- away score > home score → `away`
- level score → the recorded/predicted shootout winner (`home` or `away`)
- level score with no shootout winner → `draw` (only reachable for group matches or
  invalid states)

Scoring a prediction against the actual result:

1. If **predicted advancer ≠ actual advancer → 0** (you named the wrong team to go
   through — same as calling the wrong winner today).
2. Otherwise, right advancer, award on scoreline accuracy exactly as today:
   - `4` — exact scoreline
   - `3` — correct goal difference
   - `2` — correct advancer only

Group matches are untouched: `pen_winner` is always nil, a level score yields the
`draw` outcome, and the behaviour is identical to today.

### Worked examples (actual result: `1–1`, France advance on penalties)

| Prediction | Points | Reason |
|---|---|---|
| `1–1`, France on pens | 4 | right advancer + exact score |
| `1–1`, Portugal on pens | 0 | wrong advancer (exact score does not save it) |
| `0–1` (France win) | 2 | right advancer, score off |
| `2–1` (Portugal win) | 0 | wrong advancer |
| `2–2`, France on pens | 3 | right advancer, goal difference (0 = 0) |

### Equivalence with current scoring

For group matches and **decisive** knockout results (`pen_winner` nil on both sides)
this rule produces scores identical to the current algorithm. Same goal difference
implies the same outcome sign, and an exact scoreline implies the same difference, so
the new "wrong advancer → 0" gate never fires in a case where today's code awards 4 or
3. It changes behaviour **only** for knockout matches that end level. Existing scoring
tests must continue to pass unchanged.

## Data model

Add a nullable `penalty_winner` column to **both** tables, as an enum
`{ home: 0, away: 1 }`:

- `predictions.penalty_winner` — the team the player thinks wins the shootout. Set only
  when the player predicts a knockout draw.
- `fixtures.penalty_winner` — the actual shootout winner. Set only on a finished
  knockout that ended level.

Storing a **side** (`home`/`away`) rather than a team id keeps it simple, matches how
the cards already render (home on the left, away on the right), and needs no foreign
key or "is this one of the two teams" validation. Teams are always known by the time a
prediction can be made or a result entered (`open_for_predictions?` already requires
`teams_known?`), so the side is never ambiguous.

## Validation

**Prediction** (`app/models/prediction.rb`)

- A `before_validation` normalizes: clear `penalty_winner` unless the fixture is a
  knockout **and** the predicted scores are equal. A stray value can never persist on a
  non-draw or a group match.
- When the fixture is a knockout **and** the predicted scores are equal,
  `penalty_winner` is **required** — the pick decides the player's entire score for the
  match, so an incomplete draw prediction is rejected with a clear message.

**Fixture** (`app/models/fixture.rb`)

- `penalty_winner` may only be present for non-group fixtures.
- For a **finished, non-group** fixture with a **level** score, `penalty_winner` is
  **required** (a knockout can't end level without someone advancing).
- For a decisive score, `penalty_winner` must be blank.
- Group fixtures: `penalty_winner` always blank.

This means an admin entering a level knockout result must record the shootout winner,
enforced with a friendly error via the existing turbo-stream error path.

## Scoring service (`app/services/scoring_service.rb`)

- Remove any notion of a penalty bonus. Introduce a private `outcome(home, away,
  pen_winner)` helper implementing the advancer rule above.
- `points_for` gains `predicted_pen_winner:`/`actual_pen_winner:` keyword args
  (defaulting to nil so existing call sites and group scoring are unaffected). It
  returns `0` when the advancers differ, else `4/3/2` on scoreline accuracy.
- `score_fixture!` passes `predicted_pen_winner: prediction.penalty_winner` and
  `actual_pen_winner: fixture.penalty_winner`.
- `champion_team_id` reuses `outcome` so a final decided on penalties correctly yields
  the shootout winner instead of returning nil (today it silently awards no champion
  bonus when the final ends level).

`points_awarded` still stores the single per-fixture total, so `LeaderboardService`
needs no changes.

## Prediction card UI (`app/views/fixtures/_fixture_card.html.erb`, open state)

For **knockout fixtures only**, render a "— goes to penalties —" section with a
two-option winner picker (home team / away team) after the score steppers, bound to
`prediction[penalty_winner]` with values `home`/`away` and pre-selected from an existing
prediction.

A small Stimulus `penalty` controller wraps the form:

- Targets the two score inputs and the picker.
- `change`/`input` actions on the score inputs (the existing `stepper` controller
  already dispatches a bubbling `change` on increment/decrement, so stepper clicks are
  caught too).
- Reveals the picker when the two scores are equal, hides it otherwise.
- When hidden, the picker radios are **disabled** (so a stale value is never submitted)
  and not required; when shown, they are enabled and **required** (a draw prediction
  must name an advancer).

## Admin result entry (`app/views/admin/fixtures/_fixture_row.html.erb` inline form,
plus the `edit.html.erb` full-page fallback)

Same reveal behaviour for non-group fixtures: when the admin's two score inputs are
equal, a required shootout-winner picker appears (reusing the `penalty` Stimulus
controller). Add `penalty_winner` to `result_params` in
`app/controllers/admin/fixtures_controller.rb`. A missing winner on a level knockout
result is rejected by the fixture validation and surfaced through the existing
turbo-stream error flow.

## Result & comparison display

- Finished knockout cards (`_fixture_card` finished state) show the shootout outcome,
  e.g. `1–1 · France win on penalties`.
- The head-to-head comparison (`_comparison_card` / `_pick`) shows each player's called
  advancer alongside their scoreline.
- The `4/3/2/0` outcome labels (Exact/Diff/Tendency/Miss) in
  `UserPredictionsHelper` are unchanged — there is no bonus, so `points_awarded` stays
  in the existing range.

## Testing

- **Prediction model**: `penalty_winner` cleared on non-draw / group; required on a
  knockout draw; accepted on a valid knockout draw.
- **Fixture model**: `penalty_winner` required on a finished level knockout; rejected on
  a decisive score; rejected on a group fixture.
- **ScoringService**: the five worked examples above; regression cases proving group and
  decisive-knockout scores are unchanged; `champion_team_id` for a final decided on
  penalties.
- **Predictions controller**: upsert persists `penalty_winner` on a knockout draw and
  ignores it on a non-draw.
- **System test**: on a knockout card, entering equal scores reveals the picker and a
  non-draw hides it; saving a draw + advancer round-trips.

## Out of scope (YAGNI)

- Predicting the actual shootout scoreline (e.g. 4–3 on pens).
- Automatic bracket advancement — teams are still set manually by admins.
- Any penalty concept for group-stage matches.
