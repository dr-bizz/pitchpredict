# Reactive UI + Turbo Morphing — Design Spec

**Date:** 2026-06-26
**Branch:** `make-it-fast`
**Status:** Approved for implementation

## Goal

Make PitchPredict feel like a React app: components update and change without
full page reloads, server-driven changes propagate live, and interactions feel
instant. Concretely:

1. **Admin score entry inline** — enter and save a result on the
   `/admin/fixtures` list page itself (edit-in-place), with no navigation to a
   separate `edit` page.
2. **Live, morph-driven updates** — when a result is scored, every open
   player-facing page (dashboard, predictions grid, leaderboard) updates itself
   live via a Turbo **morphing page refresh**, no manual reload.
3. **Perceived speed** — instant loading/disabled feedback on every submit;
   in-progress inputs are never clobbered by a background update.
4. **Real load-time fixes** — remove redundant server work found in the audit.

## Background: the three "no reload" mechanisms

Morphing is already enabled globally in `app/views/layouts/application.html.erb`:

```html
<meta name="turbo-refresh-method" content="morph">
<meta name="turbo-refresh-scroll" content="preserve">
```

Morphing applies **only to full-page refreshes of the same URL**. The three
mechanisms and where we use each:

| Mechanism | Trigger | Morphs? | Used for |
|---|---|---|---|
| **Page refresh** (`broadcast_refresh_to` + `turbo_stream_from`) | Server says "this changed" → client re-GETs its current URL → morphs the diff | ✅ | Live updates to dashboard / predictions / leaderboard |
| **Targeted Turbo Stream** (`turbo_stream.replace "id"`) | Direct controller response | ❌ | Admin inline row edit/save |
| **Turbo Frame** | Scoped lazy replace | ❌ | (existing prediction cards — unchanged) |

**Key property of `broadcast_refresh_to`:** it does not push HTML. It tells each
subscribed browser to re-request *its own* current URL with *its own* session.
So the leaderboard/dashboard re-render server-side **with the correct
`Current.user`** — the per-viewer highlight and "my rank" are correct without
any viewer-specific broadcast. This is strictly better than the current
viewer-agnostic targeted broadcast.

## Architecture

### Stream + broadcast

- One shared stream name: **`"results"`**.
- Player-facing pages subscribe: `turbo_stream_from "results"` on
  `dashboard/show`, `fixtures/index` (predictions grid), `leaderboards/show`.
- `ScoreFixtureJob`, after scoring + cache expiry, broadcasts a single refresh:
  `Turbo::StreamsChannel.broadcast_refresh_to("results")`.
  This **replaces** the current targeted `broadcast_replace_to("leaderboard",
  target: "leaderboard-table", …)`.
- Because the broadcast originates from a background job (no request id), every
  subscribed client refreshes — including the one whose action triggered the
  job. The refresh is idempotent (a morph), so this is fine.

### Admin index page — deliberately NOT subscribed

The admin index uses **direct Turbo Stream responses** for inline editing and is
**not** subscribed to `"results"`. Rationale: a background morph refresh would
clobber a row the admin is mid-typing. A single admin edits one row at a time;
the direct stream response updates that row immediately. This sidesteps the
in-progress-edit clobber problem entirely on the admin side.

### A. Admin inline scoring (edit-in-place via Turbo Streams)

HTML tables can't nest a `<turbo-frame>` across multiple `<td>`s, so we
edit-in-place by **replacing the whole `<tr id="<dom_id(fixture)>">`** via Turbo
Streams. From the admin's point of view it is an in-place toggle: click → row
becomes inputs → save → row becomes the result.

Partials (each renders a complete `<tr id="<dom_id(fixture)>">`):

- `admin/fixtures/_fixture_row.html.erb` — display row: match, stage, status,
  result, and the contextual action button ("Set teams" / "Enter result" /
  "Edit"). Extracted verbatim from the current inline `<tr>` in `index.html.erb`.
- `admin/fixtures/_form_row.html.erb` — edit row: `home_score` / `away_score`
  number inputs + **Save** and **Cancel**, plus inline validation errors.

Controller (`Admin::FixturesController`):

- `index` — unchanged query; view loops `render @fixtures` (the row partial).
- `edit` — `respond_to`: `turbo_stream` → `turbo_stream.replace dom_id(fixture),
  partial: "form_row"`; `html` → existing full `edit.html.erb` (no-JS fallback).
- `update` — on success: keep `ScoreFixtureJob.perform_later`; respond
  `turbo_stream` replacing the row with `_fixture_row` (now finished) **and**
  prepend a flash toast; `html` → redirect as today. On failure: respond
  `turbo_stream` replacing the row with `_form_row` showing errors (status
  `:unprocessable_entity`); `html` → `render :edit`.
- `row` — **new** `GET` member action: responds `turbo_stream` replacing the row
  with `_fixture_row` (display). Backs the **Cancel** link.

Routes:

```ruby
namespace :admin do
  resources :fixtures, only: %i[ index edit update ] do
    get :row, on: :member
  end
  resources :knockout_fixtures, only: %i[ index update ]
end
```

The Cancel link is `link_to "Cancel", row_admin_fixture_path(fixture),
data: { turbo_stream: true }` (Turbo 8 lets a GET link accept a turbo-stream
response). "Enter result" / "Edit" link to `edit_admin_fixture_path(fixture),
data: { turbo_stream: true }`.

Flash toasts on the admin page render into a `turbo_stream_from`-free target:
add an `id="admin-flash"` container to the admin view and prepend messages there
from the `update` stream response.

### B. Load-time fixes

1. **Dashboard double-computes the leaderboard.**
   `DashboardController#show` calls the *uncached* `LeaderboardService.new.rows`,
   while `dashboard/show.html.erb` re-calls the cached
   `LeaderboardService.fetch_rows`. Fix: controller uses `fetch_rows`; view uses
   the already-set `@top_rows` instead of re-calling the service.
2. **Upcoming-fixtures count done in Ruby.**
   `dashboard/show.html.erb` does `Fixture.upcoming.to_a` then
   `.count { |f| … }`. Replace with the single-query form already used in
   `FixturesController#index`:
   `Fixture.upcoming.teams_set.where.not(id: Current.user.predictions.select(:fixture_id)).count`,
   computed in the controller as `@remaining_to_predict`.

### C. Perceived speed

1. **Loading/disabled states** via Turbo 8's built-in `data-turbo-submits-with`
   (no custom JS): add to the prediction submit, admin Save, and champion-pick
   submit buttons, e.g. `data: { turbo_submits_with: "Saving…" }`. Turbo disables
   the button and swaps its label during submission automatically.
2. **In-progress input safety.** Morph (idiomorph) preserves the **focused**
   input's value across a refresh, so a player actively typing a prediction is
   not clobbered by a background `"results"` refresh. No extra work required for
   the common case; documented as a known property. (The admin side is already
   protected by not subscribing.)
3. **Hover prefetch.** Turbo Drive prefetches links on hover by default in this
   Turbo version. Verify it is not disabled globally; nav links are plain
   `link_to`, so prefetch already applies. No code change expected — a
   verification item only.

## Explicitly out of scope (considered, deferred)

- **View-fragment caching of fixture cards / leaderboard rows.** The expensive
  leaderboard computation is already cached at the service layer (Solid Cache).
  Fixture cards include time-dependent state (`locked?` flips at kickoff), so
  naive `cache` blocks risk showing stale "open" cards. Deferred to avoid
  correctness bugs; revisit only if profiling shows a need.
- **Auth / registration / password pages.** Static forms, nothing to gain.
- **`leaderboard_highlight_controller.js`.** With refresh-morph, the highlight is
  now server-rendered correctly per viewer. The controller becomes redundant but
  harmless; leave it in place (optional future cleanup, not part of this work).

## Testing strategy

- `bin/rails test` is the source of truth (system/browser tests are known-broken
  locally per project memory — do not rely on `test:system`).
- **Admin inline scoring** (`test/controllers/admin/fixtures_controller_test.rb`):
  - `edit` with `Accept: text/vnd.turbo-stream.html` returns a stream replacing
    the row with the form.
  - `update` success returns a turbo-stream replacing the row + enqueues
    `ScoreFixtureJob`; HTML format still redirects.
  - `update` failure (e.g. blank score) returns the form row with errors and
    `:unprocessable_entity`.
  - `row` returns the display row stream.
  - Existing redirect-based tests for the HTML format keep passing.
- **ScoreFixtureJob** (`test/jobs/score_fixture_job_test.rb`): asserts a refresh
  is broadcast to `"results"` (replacing the prior assertion about the targeted
  `leaderboard-table` replace).
- **Dashboard** (`test/controllers/dashboard_controller_test.rb`): page renders;
  `@remaining_to_predict` correct; leaderboard service invoked once.
- No regressions in the existing fixtures/leaderboard/predictions controller
  tests (the `turbo_stream_from` additions are inert for plain HTML requests).

## Implementation order

A (admin inline scoring) → B (load-time fixes) → C (perceived speed + live
subscriptions). A is the headline feature; B and C are polish. The
`ScoreFixtureJob` broadcast change pairs with C's page subscriptions.
