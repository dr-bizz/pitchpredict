# View Another User's Predictions — Design

- **Date:** 2026-06-20
- **Status:** Approved (brainstorming) — ready for implementation plan
- **Branch:** `feature/view-other-users-predictions` (off `main`)

## Goal

Let any logged-in player open another player's prediction history by clicking
their name from the leaderboard. The view shows the target player's predictions
**only for matches no longer open to prediction**, displayed **head-to-head**
against the viewer's own picks, with the actual result and points earned per
match. Matches still open to prediction are never shown — revealing a live guess
would be a cheating vector.

## User-Facing Behavior

- **Entry points:** a player's name is a link wherever it appears on the
  leaderboard surfaces — the main leaderboard table, the top-3 podium, and the
  dashboard top-5 preview. The **viewer's own name is not linked** (plain text,
  as today).
- **Destination:** `/users/:id/predictions` — a read-only page titled with the
  target player's name, their rank, and total points.
- **Per match, the card shows:** the actual result, the target player's
  predicted score + the points they earned (Exact / Diff / Tendency / Miss), and
  the viewer's own predicted score + points, side by side. "No prediction" when
  either player didn't predict that match.
- **Filter tabs:** `Past` (default — every locked match, most recent first) plus
  one tab per knockout/group stage (`Groups, R32, R16, QF, SF, 3rd Place,
  Final`). There is **no** Upcoming/Unpredicted tab — those are editing-oriented
  and meaningless on a read-only foreign view.
- **Read-only:** no forms, no steppers, no submit buttons anywhere on this page.

## Security Model (the core constraint)

A player's predictions on matches still open to prediction must never be visible
to anyone else. The existing app enforces this implicitly: predictions are
private-by-construction (singular routes keyed to `Current.user`, unique
`(user_id, fixture_id)` index), so privacy was never an explicit check. This
feature deliberately opens one player's locked predictions to another, so the
lock boundary becomes an **explicit, tested** concern.

Two independent guarantees:

1. **Query-level filter.** Fixtures are restricted to *locked* ones before any
   prediction is loaded. "No longer open to prediction" is defined by
   `Fixture#locked?` (`app/models/fixture.rb:32-34`):
   `kickoff_at <= Time.current || !scheduled?`. This is **not** the same as the
   temporal `past` scope — an admin can flip a fixture to `live`/`finished` while
   its kickoff is still future, which locks predictions early. We must mirror
   `locked?` exactly, so we add a **new `Fixture.locked` scope** (query twin of
   the predicate). The target player's predictions are then loaded scoped to the
   locked fixture IDs in the current tab, so an open prediction is never even
   fetched from the database.

2. **Render-level safety.** A brand-new read-only partial is used — it contains
   no `<form>`, no inputs, and no prediction submit path. Even a filtering bug
   cannot produce an editable control on another player's data. (The existing
   editable `_fixture_card` partial is deliberately **not** reused, because its
   branch selection is driven by fixture state, not by prediction ownership.)

## Architecture & Components

### 1. `Fixture.locked` scope — `app/models/fixture.rb`
Add alongside the existing `upcoming`/`past`/`by_stage` scopes
(`app/models/fixture.rb:23-25`):

```ruby
scope :locked, -> {
  where(kickoff_at: ..Time.current).or(where.not(status: :scheduled))
}
```

This is the exact query-level equivalent of `locked?`
(`kickoff_at <= now OR status != scheduled`). A unit test pins this equivalence.

### 2. Route — `config/routes.rb`
```ruby
get "users/:id/predictions", to: "user_predictions#index", as: :user_predictions
```
Path helper: `user_predictions_path(user, stage: :past)`. Users have no slug and
no `to_param`, so URLs use the numeric `id` (already present in the leaderboard
DOM as `data-user-id`). Authentication is required by default — do **not** add
`allow_unauthenticated_access`.

### 3. `UserPredictionsController#index` — new `app/controllers/user_predictions_controller.rb`
Mirrors the shape of `FixturesController#index` but for a target user and
read-only:

- `@user = User.find(params[:id])` — Rails raises `RecordNotFound` → 404 on a bad
  id (acceptable; no custom rescue needed unless one already exists app-wide).
- `@stage = params[:stage].presence_in(foreign_prediction_tabs.keys) || "past"`,
  where `foreign_prediction_tabs` is the foreign-view tab set (see helper below).
- Build the locked fixture set:
  - `past` tab → `Fixture.locked.order(kickoff_at: :desc)`
  - stage tab → `Fixture.by_stage(@stage).locked.order(:match_number, :kickoff_at)`
  - eager-load `includes(:home_team, :away_team, :stadium)` to avoid N+1.
- Load both players' predictions, indexed by fixture id, scoped to the locked
  fixtures on screen:
  ```ruby
  fixture_ids = @fixtures.map(&:id)
  @owner_predictions  = @user.predictions.where(fixture_id: fixture_ids).index_by(&:fixture_id)
  @viewer_predictions = Current.user.predictions.where(fixture_id: fixture_ids).index_by(&:fixture_id)
  ```
- Header data: find the target user's row from `LeaderboardService.fetch_rows`
  (cached) to show rank + total points. If the user has no row (no scored
  predictions yet), the header degrades gracefully to just the name.
- Grouping for display mirrors the existing controller: build `@by_date` for the
  `past` tab and `@grouped` (by `home_team.group_name`) for the `group` tab.

### 4. View — new `app/views/user_predictions/index.html.erb`
- Header: target player name, rank, total points, and a clear "vs you" framing.
- Read-only tablist built from the foreign-view tab set, links carrying `stage:`,
  reusing `stage_tab_classes` (`app/helpers/fixtures_helper.rb`).
- Body: reuses the same date-grouped / group-stage layout as the owner grid for
  visual consistency, rendering the new comparison partial per fixture. Empty
  states per tab ("No matches have kicked off yet", etc.).

### 5. Partial — new `app/views/user_predictions/_comparison_card.html.erb` (read-only)
Locals: `fixture`, `owner`, `owner_prediction`, `viewer_prediction`.
Renders three pieces per match:
- Actual result (from `fixture.home_score`/`away_score`, finished matches) or a
  "kicked off / live" state for locked-but-not-yet-finished matches.
- Owner's predicted score + outcome badge.
- Viewer's predicted score + outcome badge.
- "No prediction" placeholder where a player has none.
No interactive elements of any kind.

### 6. Helper — `app/helpers`
- `foreign_prediction_tabs` (or a constant): `STAGE_TABS` minus the `upcoming`
  key, plus a leading `"past" => "Past"`. Lives next to the existing
  `STAGE_TABS` in `FixturesHelper` (or a new `UserPredictionsHelper` that
  references it) to keep one source of truth for stage labels.
- `prediction_outcome` helper mapping `points_awarded` → label + color:
  `4 → Exact`, `3 → Diff`, `2 → Tendency`, `0 → Miss`, `nil → —` (not yet
  scored). Point values are owned by `ScoringService`
  (`EXACT_POINTS`/`DIFFERENCE_POINTS`/`TENDENCY_POINTS`,
  `app/services/scoring_service.rb:11-13`) — reference those constants rather
  than hard-coding numbers. Used by the comparison card for both players.

### 7. Leaderboard link wiring (3 surfaces)
- **Main table** — `app/views/leaderboards/_table.html.erb:56`: wrap the name
  span in `link_to … user_predictions_path(row.user)`, but render plain text when
  `mine` (the partial already computes `mine` at line 42 from the `viewer`/
  `current_user` local — safe in the Turbo Stream broadcast path where
  `Current.user` is nil).
- **Podium** — `app/views/leaderboards/show.html.erb:29`: link `player.user`'s
  name. (Top-3 are never the broadcast-nil case here; still guard against linking
  the viewer's own podium entry for consistency.)
- **Dashboard top-5** — `app/views/dashboard/show.html.erb`: this preview
  re-implements the table inline rather than reusing `_table`; locate its name
  cell and apply the same link + self-suppression.

## Data Flow

1. Viewer clicks a name on a leaderboard surface → `GET /users/:id/predictions`.
2. Controller resolves target user, computes the locked fixture set for the tab,
   loads both players' predictions (scoped to those fixtures), and the target's
   leaderboard row.
3. View renders the read-only comparison cards grouped by date/stage.
4. No writes occur; no Turbo Streams; this page is a plain authenticated GET.

## Edge Cases & Error Handling

- **Unknown / non-numeric id:** `User.find` raises `RecordNotFound` → standard
  404. (Match whatever the app already does for missing records.)
- **Viewing your own page:** harmless (you-vs-you, identical columns). The
  self-link is suppressed on leaderboard surfaces, so this is only reachable by
  typing the URL; render normally rather than special-casing.
- **Target has no predictions on locked matches:** empty state per tab; header
  shows name with rank/points if available, else just the name.
- **Locked-but-not-finished match (live / early-locked):** show the prediction
  with no points badge (points not yet awarded) and a "not yet scored" / live
  indicator instead of a result.
- **Knockout fixture that locked with TBD teams:** extremely unlikely (a finished
  fixture must have teams; an unstarted future knockout isn't locked), but the
  card falls back to `home_display`/`away_display` slot labels and shows no
  prediction.

## Testing Plan (Minitest + fixtures, matching existing conventions)

- **Model** (`test/models/fixture_test.rb`): `Fixture.locked` returns the same
  set as filtering `Fixture.all.select(&:locked?)` across scheduled-future,
  past-kickoff, and live/finished-future cases; excludes open fixtures.
- **Controller / integration** (`test/controllers/user_predictions_controller_test.rb`):
  - redirects to sign-in when unauthenticated;
  - **anti-cheat (critical):** a target's prediction on an *open* fixture does
    NOT appear in the response body, while a prediction on a locked fixture does;
  - renders the target's pick + actual result + points for locked matches;
  - the viewer's own prediction appears head-to-head;
  - unknown id → 404;
  - `stage` param filters to that stage's locked fixtures.
- **Partial** (`ApplicationController.render(partial:, locals:)`, per
  `test/controllers/leaderboards_controller_test.rb`): the comparison card output
  contains neither `<form>`, editable `<input>`, nor any `fixture_prediction`
  submit path.
- **Leaderboard view** (`test/controllers/leaderboards_controller_test.rb`):
  other players' names link to the correct `user_predictions_path`; the current
  user's own row/podium entry is not linked.
- **System** (`test/system`, multi-session via `using_session`): sign in, open
  the leaderboard, click another player's name, and see their past predictions
  head-to-head.

## Out of Scope (YAGNI)

- No slug / `to_param` change — numeric IDs are fine.
- No changes to the editable owner grid or `_fixture_card` beyond (optionally)
  sharing the `prediction_outcome` helper.
- No Upcoming/Unpredicted tabs on the foreign view.
- No live/Turbo updates on the foreign view — it's a static authenticated GET.
- No new authorization roles; any authenticated user may view, and the locked
  filter is the security boundary.

## Resolved Decisions

1. Content per match: prediction **+ actual result + points**.
2. **Head-to-head** — viewer's pick shown beside the target's.
3. **Filter tabs** (Past + per-stage), not a single flat list.
4. Link appears on **all three** leaderboard surfaces (table, podium, dashboard
   top-5).
5. Gate is `locked?` (new `Fixture.locked` scope), **not** the temporal `past`.
6. Dedicated read-only controller/view/partial; existing editable grid untouched.
