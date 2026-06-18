# Knockout TBD Bracket + Admin Team Entry — Design

**Date:** 2026-06-18
**Branch:** champion-pick-deadline (feature work continues here or a new branch)
**Status:** Approved design, ready for implementation plan

## Problem

The knockout fixtures (Round of 32, R16, QF, SF, 3rd place, Final) were seeded with
**placeholder qualifiers** — group winners/runners-up/best-thirds copied straight from
the group draw. To users this looks like the bracket teams are already decided, which is
wrong: nobody knows who advances until the group stage finishes. We must remove those
fake team assignments and give the admin a way to fill in each knockout match's teams as
they are announced.

Group-stage fixtures are correct (real teams, real schedule) and must not change.

## Decisions (confirmed with user)

1. **Keep the match slots.** Knockout fixtures stay (date, stadium, round, kickoff) but
   their teams are blanked. The admin fills teams in later.
2. **Show as locked TBD cards.** Knockout matches remain visible to players as
   non-predictable placeholder cards until both teams are entered, then they become
   normal predictable cards.
3. **Descriptive slot labels.** Empty slots read like "Winner Group A",
   "Runner-up Group B", "Winner of Match 89" — not just "TBD". These are *hints*; the
   admin still picks the actual team by hand. Because the official routing of best-third
   teams is only fixed after the group stage, labels encode a clean, internally
   consistent bracket **topology**, not the official seeding table.

## Architecture Overview

A `Fixture` gains the ability to have **no teams yet** (nullable `home_team_id` /
`away_team_id`) plus two descriptive **slot-label** strings and a **match number**. A new
single source of truth, `KnockoutBracket`, defines the 32-match knockout topology (round,
match number, and the two slot labels per match). Seeds and a one-off data migration both
consume `KnockoutBracket` so existing and freshly-seeded databases agree. A new admin
screen lists the knockout matches and lets the admin assign/clear teams. Player-facing
views render a TBD card for any match whose teams are not yet known.

## Components

### 1. `KnockoutBracket` (new) — `app/models/knockout_bracket.rb`

The single source of truth for knockout topology. A frozen array of 32 slot specs, one
per knockout match, in creation order, each: `{ stage:, match_number:, home_label:,
away_label: }`.

- **Match numbers:** group stage is matches 1–72 (creation order); knockout is 73–104.
  - R32: matches 73–88 (16)
  - R16: matches 89–96 (8)
  - QF: matches 97–100 (4)
  - SF: matches 101–102 (2)
  - 3rd place: match 103
  - Final: match 104
- **R32 slot labels** (group-based, meaningful):
  - "Winner Group A" … "Winner Group L"
  - "Runner-up Group A" … "Runner-up Group L"
  - "3rd Place — Group A" … "3rd Place — Group H"
  - Pairings keep the existing seed layout (home `bracket[i]`, away `bracket[31-i]`), now
    expressed as labels instead of teams.
- **Later-round slot labels** reference the feeding matches with a clean single-elimination
  tree: R16 match 89 = "Winner of Match 73" vs "Winner of Match 74", … ; SF = winners of
  the QFs; 3rd place (103) = "Loser of Match 101" vs "Loser of Match 102"; Final (104) =
  "Winner of Match 101" vs "Winner of Match 102". The tree is internally consistent even
  though which group winners actually meet is illustrative.

Lookup helper: `KnockoutBracket.for(stage, index)` returns the spec for the Nth match of a
stage (matching the seed loops' `i/j/k/s` indices), so seeds attach labels without
restating them.

`KnockoutBracket` is pure data + lookup — no DB access — so it is trivially unit-testable
and safe to reference from a migration.

### 2. `Fixture` model — `app/models/fixture.rb`

- `belongs_to :home_team, optional: true` and `belongs_to :away_team, optional: true`.
- New columns used: `home_slot_label`, `away_slot_label` (string, nullable),
  `match_number` (integer, nullable).
- Validations:
  - **Group fixtures always have both teams:** `validate` that if `group?` then
    `home_team` and `away_team` are present.
  - **Teams set together:** a fixture has either both teams or neither (no half-filled
    knockout match).
  - Keep existing `teams_must_differ` (already guards on `home_team_id.blank?`).
- New predicates / helpers:
  - `teams_known?` → both team ids present.
  - `open_for_predictions?` → `teams_known? && !locked?`.
  - `home_display` / `away_display` → team name when known, else slot label, else "TBD".
    (Flag/emoji helpers return team flag when known, else a neutral placeholder glyph.)
- `locked?` is unchanged (time/status). TBD-ness is expressed via `teams_known?` so the
  card can show a dedicated "coming soon" state distinct from "kicked off".

### 3. `Prediction` model — `app/models/prediction.rb`

- `fixture_must_be_open` also rejects when teams are not yet known:
  add `errors.add(:base, "Teams for this match haven't been announced yet")` when
  `fixture && !fixture.teams_known?`. This blocks any create/update against a TBD match at
  the model layer (defence in depth behind the controller/UI).

### 4. Seeds — `db/seeds.rb`

- Knockout fixtures are created with `home_team: nil, away_team: nil` and with
  `home_slot_label`, `away_slot_label`, `match_number` pulled from `KnockoutBracket`.
  Kickoff/stadium/stage logic is unchanged.
- Group fixtures also get `match_number` (1–72 in creation order) for consistency, but
  keep their real teams and blank slot labels.
- Remove the now-unused illustrative `bracket`/`winners`/`runners`/`thirds` team arrays
  (replaced by labels).
- Demo profile: predictions and champion picks are unchanged (group-only). No demo
  predictions are created on knockout matches (they have no teams). The "backdate &
  score past fixtures" phase is unaffected — knockout matches are all in July (future),
  so they stay `scheduled` with nil teams.

### 5. Data migration for existing databases

Production already holds the bad knockout data and **must not be re-seeded** (that would
wipe real users). A data migration brings existing databases in line:

For every fixture with `stage != group`, in deterministic order (`stage`, `kickoff_at`,
`id`) zipped against `KnockoutBracket`:
- delete its predictions (they were placed against placeholder teams),
- null `home_team_id`, `away_team_id`, `home_score`, `away_score`,
- reset `status` to `scheduled`,
- set `home_slot_label`, `away_slot_label`, `match_number`.

Also backfill `match_number` for group fixtures (ordered by `kickoff_at`, `id` → 1–72).
The schema-change migration (nullable columns + new columns) runs first, then this data
migration. Both run automatically on deploy via `db:migrate`.

### 6. Admin "Knockout bracket" view

New nested resource under the existing admin namespace, gated by the existing
`require_admin`.

- Route: `namespace :admin { resources :knockout_fixtures, only: %i[index update] }`
  (path `/admin/knockout_fixtures`), plus a link from the admin fixtures index.
- `Admin::KnockoutFixturesController`:
  - `index` — all non-group fixtures ordered by `match_number`, grouped by round.
  - `update` — assign `home_team_id` / `away_team_id` (each may be set or cleared back to
    nil/TBD). Setting one requires setting both (model validation enforces). On success,
    redirect back with a notice; the match becomes predictable.
- View: a table/cards grouped by round. Each row shows the round, match number, kickoff,
  the two slot labels, and **two team `<select>` dropdowns** (all 48 teams, grouped by
  group letter; blank option = "TBD / not announced"). A clear/"reset to TBD" affordance.
  Once both teams are set the row shows the matchup and a note that it is now live for
  predictions.
- The existing result-entry flow (scores) is unchanged and used **after** teams are set.
  The admin fixtures index and edit views are updated to render `home_display`/
  `away_display` (and codes only when known) so TBD knockout rows don't crash on nil
  teams; the "Enter result" action is disabled/hidden until teams are known.

### 7. Player-facing views

- `app/views/fixtures/_fixture_card.html.erb` gains a **TBD branch**: when
  `!fixture.teams_known?`, render the slot labels ("Winner Group A" vs "Runner-up Group
  B"), the date/stadium/round, a neutral placeholder where flags go, no score inputs, and
  a "Teams to be announced" lock note. No form is rendered. The existing finished / locked
  / open branches are guarded to run only when `teams_known?`.
- The card's team rendering switches to `home_display`/`away_display` and the flag helper
  so the finished/locked/open branches are also nil-safe (defence in depth).
- `FixturesController#index`: the `upcoming` tab already lists all future matches by date,
  so TBD knockout cards appear there automatically. The per-stage knockout tabs (R32…Final)
  list their fixtures ordered by `match_number` then `kickoff_at`. The `group` grouping is
  unchanged (group fixtures always have teams). Empty-state copy unaffected.

### 8. Helpers

- Add `home_display` / `away_display` (and a flag-or-placeholder helper) as **model**
  methods on `Fixture` (above), so views and the admin share them. No new global helper
  needed beyond what already exists (`stage_label`, `kickoff_label`, `STAGE_TABS`).

## Data Flow

1. Deploy runs migrations → knockout fixtures become TBD with slot labels + match numbers;
   their stale predictions are removed.
2. Player visits Predictions → sees group matches (predictable) and knockout matches as
   locked TBD cards with descriptive labels.
3. Group stage finishes → admin opens `/admin/knockout_fixtures`, picks the real two teams
   for each announced match, saves.
4. That match flips to `teams_known?` → players can now predict it; it renders as a normal
   open card until kickoff.
5. After kickoff/result, the admin uses the existing result-entry flow to enter the score;
   scoring runs as today.

## Error Handling / Edge Cases

- **Half-filled match:** model validation forbids one team set without the other.
- **Same team both sides:** existing `teams_must_differ` validation covers it.
- **Predicting a TBD match:** blocked at the model (`fixture_must_be_open`) and not offered
  in the UI (no form rendered).
- **Group fixture with missing team:** forbidden by validation (cannot regress group data).
- **Re-running the data migration:** guarded so it is safe/idempotent (only acts on
  non-group fixtures; setting already-null teams is a no-op).
- **Scoring a TBD match:** impossible — a match cannot be `finished` without teams (it has
  no result-entry path until teams are set), and `score_fixture!` still raises unless
  `finished?`.

## Testing

- **`KnockoutBracket`:** 32 specs, correct match numbers per round, unique match numbers,
  every later-round label references a valid earlier match number, R32 labels cover all 12
  groups' winners/runners-up + 8 thirds.
- **`Fixture` model:** `teams_known?`, `open_for_predictions?`, `home_display`/
  `away_display` fallbacks; group-requires-teams validation; teams-set-together validation;
  knockout fixture valid with nil teams.
- **`Prediction` model:** cannot be created/updated against a TBD fixture; works once teams
  are set.
- **`Admin::KnockoutFixturesController`:** requires admin; assigning both teams succeeds and
  makes the match predictable; clearing resets to TBD; setting one team only is rejected.
- **`FixturesController` / view:** TBD knockout card renders slot labels and no form;
  becomes an open card after teams are assigned; admin fixtures index renders TBD rows
  without error.
- **Seeds smoke (where covered):** knockout fixtures seed with nil teams + labels + match
  numbers; group fixtures keep teams.

## Out of Scope (YAGNI)

- Automatic bracket progression (deriving knockout teams from group results).
- Encoding the official FIFA best-third routing table.
- Per-user time zones.
- Editing knockout dates/stadiums from the admin UI (schedule is fixed by seeds).
