# Implementation Plan — Reactive UI + Turbo Morphing

Spec: `2026-06-26-reactive-ui-morphing-design.md`. Tasks are ordered and each
ends with a verification step. Run `bin/rails test` after each task group.

## Task 1 — Admin inline scoring: row partials

**Files:**
- New `app/views/admin/fixtures/_fixture_row.html.erb`
- New `app/views/admin/fixtures/_form_row.html.erb`
- Edit `app/views/admin/fixtures/index.html.erb`

**Details:**
1. Move the entire `<tr class="hover">…</tr>` body (currently
   `index.html.erb` lines ~67–103) into `_fixture_row.html.erb`. The partial's
   local is `fixture:`. The root element MUST be
   `<tr id="<%= dom_id(fixture) %>" class="hover">`.
   - Keep the `status_badge` lambda logic, but inline it (a partial can't see
     the lambda defined in `index`). Replace `status_badge.call(...)` with a
     small helper `admin_status_badge_class(status)` in
     `app/helpers/admin/fixtures_helper.rb` (create if absent) OR an inline
     `case`. Prefer the helper for reuse by both row partials.
   - Action cell: when teams unknown → "Set teams" link (unchanged). When
     `finished?` → "Edit" button: `link_to "Edit",
     edit_admin_fixture_path(fixture), data: { turbo_stream: true },
     class: "btn btn-ghost btn-sm"`. Else → "Enter result":
     `link_to "Enter result", edit_admin_fixture_path(fixture),
     data: { turbo_stream: true }, class: "btn btn-primary btn-sm"`.
2. Create `_form_row.html.erb`, local `fixture:`. Root element
   `<tr id="<%= dom_id(fixture) %>" class="hover bg-base-200">`. Cells:
   - Match cell: reuse the same match markup as the display row (teams + kickoff).
   - Stage + Status cells: same as display row.
   - Result cell: a `form_with model: fixture, url: admin_fixture_path(fixture),
     method: :patch` containing two `number_field`s (`home_score`, `away_score`,
     `min: 0, step: 1, required: true, inputmode: "numeric"`, compact width,
     `tabular-nums`). Render `fixture.errors` inline above/below if present.
     The form's `id` should be stable; put Save inside it.
   - Action cell: `form.submit "Save", data: { turbo_submits_with: "Saving…" },
     class: "btn btn-primary btn-sm"` (inside the form) and a Cancel link:
     `link_to "Cancel", row_admin_fixture_path(fixture),
     data: { turbo_stream: true }, class: "btn btn-ghost btn-sm"`.
   - Because a `<form>` cannot wrap multiple `<td>`s, put the whole form in the
     Result `<td>` (inputs) and reference it from the Save button in the Action
     `<td>` via the `form="<form id>"` attribute, OR — simpler — put both inputs
     **and** Save together in a single wide Result cell and drop the separate
     action cell content for the edit row (use `colspan`). Choose the colspan
     approach: in `_form_row`, the Result `<td colspan="2">` holds the form with
     inputs + Save + Cancel, keeping valid HTML.
3. In `index.html.erb`, replace the inline `<% @fixtures.each %>…<% end %>` with
   `<%= render partial: "fixture_row", collection: @fixtures %>`. Remove the now
   unused `status_badge` lambda. Add an `id="admin-flash"` container above the
   table (empty `div`) for toast prepends.

**Verify:** `bin/rails test` green; visit `/admin/fixtures` renders identically
to before (display rows look the same).

## Task 2 — Admin inline scoring: controller + routes

**Files:**
- Edit `config/routes.rb`
- Edit `app/controllers/admin/fixtures_controller.rb`
- New `app/views/admin/fixtures/edit.turbo_stream.erb`
- New `app/views/admin/fixtures/update.turbo_stream.erb`
- New `app/views/admin/fixtures/row.turbo_stream.erb`

**Details:**
1. Routes: add `get :row, on: :member` to `resources :fixtures` in the `admin`
   namespace (see spec).
2. `edit` action: add `respond_to` — `format.turbo_stream` (renders
   `edit.turbo_stream.erb`), `format.html` (existing full page). Keep
   `set_fixture`.
   - `edit.turbo_stream.erb`:
     `<%= turbo_stream.replace dom_id(@fixture) do %><%= render "form_row",
     fixture: @fixture %><% end %>`.
3. `update` action: keep the `teams_known?` guard (for HTML it redirects; for
   turbo_stream, replace the row with `_form_row` carrying a base error). On
   `@fixture.update(... status: :finished)` success: keep
   `ScoreFixtureJob.perform_later(@fixture.id)`; `respond_to` —
   `format.turbo_stream` renders `update.turbo_stream.erb`, `format.html`
   redirects as today. On failure: `format.turbo_stream` renders
   `update.turbo_stream.erb` (which renders `_form_row` with errors) with
   `status: :unprocessable_entity`; `format.html` `render :edit, status:
   :unprocessable_entity`.
   - `update.turbo_stream.erb`: if `@fixture.errors.any?` →
     `turbo_stream.replace dom_id(@fixture) { render "form_row", fixture: @fixture }`;
     else → `turbo_stream.replace dom_id(@fixture) { render "fixture_row",
     fixture: @fixture }` **plus**
     `turbo_stream.prepend "admin-flash" { render "shared/flash_toast",
     message: "Result saved …", kind: :notice }` (or inline the toast markup if
     no shared partial exists — keep it simple, an `alert alert-success`).
4. `row` action: `set_fixture`-style find; render `row.turbo_stream.erb` →
   `turbo_stream.replace dom_id(@fixture) { render "fixture_row", fixture:
   @fixture }`. Add `:row` to the `set_fixture` `before_action` `only:` list.

**Verify:** controller tests in Task 6; manual: "Enter result" swaps the row to
inputs, Save flips it to the result + toast, Cancel reverts, invalid score shows
inline error.

## Task 3 — ScoreFixtureJob: broadcast a refresh

**File:** `app/jobs/score_fixture_job.rb`

**Details:** Replace the `Turbo::StreamsChannel.broadcast_replace_to("leaderboard",
target: "leaderboard-table", …)` call with
`Turbo::StreamsChannel.broadcast_refresh_to("results")`. Keep
`ScoringService.score_fixture!` and `LeaderboardService.expire_rows`. Update the
comment block (the `CONTRACT with the UI stage` note now describes the refresh).

**Verify:** Task 6 job test asserts a refresh broadcast to `"results"`.

## Task 4 — Subscribe player pages to the results stream

**Files:**
- `app/views/dashboard/show.html.erb`
- `app/views/fixtures/index.html.erb`
- `app/views/leaderboards/show.html.erb`

**Details:** Add `<%= turbo_stream_from "results" %>` near the top of each.
Remove the now-stale comment in `leaderboards/show.html.erb` referencing the
targeted `leaderboard-table` replace and change its existing
`turbo_stream_from "leaderboard"` to `turbo_stream_from "results"`. (Leave the
`id="leaderboard-table"` element in `_table` — harmless.)

**Verify:** pages still render for plain HTML requests; `bin/rails test` green.

## Task 5 — Load-time fixes + submit states

**Files:**
- `app/controllers/dashboard_controller.rb`
- `app/views/dashboard/show.html.erb`
- `app/views/champion_picks/*` (submit button) — locate the champion pick form
  (dashboard partial or its own view) and add `data: { turbo_submits_with: … }`.
- `app/views/fixtures/_fixture_card.html.erb` (prediction submit button)

**Details:**
1. Dashboard controller: change `LeaderboardService.new.rows` →
   `LeaderboardService.fetch_rows`. Add
   `@remaining_to_predict = Fixture.upcoming.teams_set.where.not(id:
   Current.user.predictions.select(:fixture_id)).count`.
2. `dashboard/show.html.erb`: replace the `LeaderboardService.fetch_rows.first(5)`
   call (line ~126) with `@top_rows`. Replace the in-Ruby
   `predicted_fixture_ids`/`upcoming_fixtures`/`remaining_to_predict` block
   (lines ~13–15) with `@remaining_to_predict`. Confirm no other view code
   depends on the removed locals.
3. Add `data: { turbo_submits_with: "Saving…" }` to the prediction submit in
   `_fixture_card.html.erb` (line ~207) and to the champion-pick submit.

**Verify:** dashboard test asserts the service is called once and
`@remaining_to_predict` is correct; `bin/rails test` green.

## Task 6 — Tests

**Files:**
- `test/controllers/admin/fixtures_controller_test.rb`
- `test/jobs/score_fixture_job_test.rb`
- `test/controllers/dashboard_controller_test.rb`

**Details:** Add/adjust tests per the spec's Testing strategy:
- Admin `edit`/`update`/`row` turbo_stream formats; `update` enqueues the job;
  failure path returns `:unprocessable_entity` with the form row; HTML format
  still redirects.
- Job broadcasts a refresh to `"results"` (use
  `assert_turbo_stream_broadcasts` / inspect `Turbo::StreamsChannel`; if a
  matcher is awkward, assert via `perform_enqueued_jobs` + capturing broadcasts).
- Dashboard renders; leaderboard service invoked once (stub/`assert` via a spy
  or count); `@remaining_to_predict` correct.

**Verify:** `bin/rails test` fully green. Do NOT run `bin/rails test:system`
(known-broken locally).

## Global verification

1. `bin/rails test` — all green.
2. `bin/rubocop` if configured — no new offenses on touched files.
3. Manual smoke (if a server is run): admin inline edit cycle; scoring a match
   makes an open leaderboard/dashboard/predictions tab morph-update live.
