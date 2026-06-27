# View Another User's Predictions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any logged-in player click another player's name on the leaderboard and see that player's predictions — head-to-head against their own — for matches no longer open to prediction, with results and points.

**Architecture:** A new read-only `UserPredictionsController#index` at `GET /users/:id/predictions` reuses the existing fixtures/grid layout patterns but renders a brand-new read-only comparison partial (no forms). Fixtures are restricted to a new `Fixture.locked` scope (the query-level twin of `Fixture#locked?`) before any prediction is loaded, so a player's still-open guesses can never leak. Leaderboard surfaces (table, podium, dashboard top-5) link each non-self player name to their page.

**Tech Stack:** Rails 8.1, Hotwire (Turbo/Stimulus), Tailwind + DaisyUI, custom session auth (`Current.user`), Minitest + YAML fixtures.

## Global Constraints

- **Security boundary:** only fixtures where `Fixture#locked?` is true may expose another user's prediction. Definition (verbatim, `app/models/fixture.rb:32-34`): `kickoff_at <= Time.current || !scheduled?`. Never use the temporal `past` scope for this — it misses early-locked (live/finished-before-kickoff) matches.
- **Authentication required:** the new controller must NOT add `allow_unauthenticated_access`.
- **User identity in URLs:** numeric `id` (no slug / `to_param` exists).
- **Read-only:** the new view/partials contain no `<form>`, no editable `<input>`, and no `fixture_prediction` submit path.
- **DRY stage labels:** reuse `FixturesHelper::STAGE_TABS` rather than re-listing stage labels.
- **Points scale (verbatim, `app/services/scoring_service.rb:11-13`):** `EXACT_POINTS = 4`, `DIFFERENCE_POINTS = 3`, `TENDENCY_POINTS = 2`, else `0`. Reference these constants — never hard-code the numbers.
- **Score separator:** use the en-dash `–` (U+2013) between scores, matching `_fixture_card.html.erb`.

---

### Task 1: `Fixture.locked` scope

**Files:**
- Modify: `app/models/fixture.rb` (add a scope near lines 23-25)
- Test: `test/models/fixture_test.rb` (add one test method)

**Interfaces:**
- Produces: `Fixture.locked` — an `ActiveRecord::Relation` returning exactly the fixtures for which `locked?` is true (`kickoff_at <= now OR status != scheduled`).

- [ ] **Step 1: Write the failing test**

Add this method inside `class FixtureTest` in `test/models/fixture_test.rb`:

```ruby
  test "locked scope matches the locked? predicate and excludes open fixtures" do
    # Before any mutation: finished_group is past+finished (locked); upcoming_group
    # is future+scheduled (open).
    assert_includes Fixture.locked, fixtures(:finished_group)
    refute_includes Fixture.locked, fixtures(:upcoming_group)

    # Equivalence with the instance predicate across every fixture, including a
    # live-before-kickoff one (locked even though its kickoff is in the future).
    fixtures(:upcoming_group).update!(status: :live)
    expected = Fixture.all.select(&:locked?).map(&:id).sort
    assert_equal expected, Fixture.locked.pluck(:id).sort
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/fixture_test.rb -n "/locked scope/"`
Expected: FAIL with `NoMethodError: undefined method 'locked' for ... Fixture` (or relation).

- [ ] **Step 3: Add the scope**

In `app/models/fixture.rb`, add directly below the existing `by_stage` scope (line 25):

```ruby
  # Query-level twin of #locked? — the matches no longer open to prediction.
  # NOTE: status <> scheduled(0) captures live/finished-before-kickoff, so this
  # is intentionally broader than the temporal `past` scope.
  scope :locked, -> { where("kickoff_at <= ? OR status <> ?", Time.current, statuses[:scheduled]) }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/fixture_test.rb -n "/locked scope/"`
Expected: PASS (1 runs, ... 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/models/fixture.rb test/models/fixture_test.rb
git commit -m "feat: add Fixture.locked scope (query twin of locked?)"
```

---

### Task 2: `UserPredictionsHelper` — tabs + outcome labels

**Files:**
- Create: `app/helpers/user_predictions_helper.rb`
- Test: `test/helpers/user_predictions_helper_test.rb`

**Interfaces:**
- Produces:
  - `UserPredictionsHelper::PREDICTION_TABS` → ordered `Hash<String,String>` `{ "past" => "Past", "group" => "Groups", "r32" => "R32", "r16" => "R16", "qf" => "QF", "sf" => "SF", "third_place" => "3rd Place", "final" => "Final" }` (i.e. `STAGE_TABS` minus `upcoming`, prefixed with `past`).
  - `prediction_outcome_label(points)` → `String|nil` ("Exact"/"Diff"/"Tendency"/"Miss"; `nil` for unknown/`nil`).
  - `prediction_outcome_badge_class(points)` → `String` DaisyUI badge class (defaults to `"badge-warning"`).

- [ ] **Step 1: Write the failing test**

Create `test/helpers/user_predictions_helper_test.rb`:

```ruby
require "test_helper"

class UserPredictionsHelperTest < ActionView::TestCase
  test "tabs start with Past and drop the editable Upcoming tab" do
    tabs = UserPredictionsHelper::PREDICTION_TABS
    assert_equal "past", tabs.keys.first
    assert_equal "Past", tabs.values.first
    refute_includes tabs.keys, "upcoming"
    assert_includes tabs.keys, "group"
    assert_includes tabs.keys, "final"
  end

  test "outcome label maps points to its tier, nil for unknown" do
    assert_equal "Exact", prediction_outcome_label(ScoringService::EXACT_POINTS)
    assert_equal "Diff", prediction_outcome_label(ScoringService::DIFFERENCE_POINTS)
    assert_equal "Tendency", prediction_outcome_label(ScoringService::TENDENCY_POINTS)
    assert_equal "Miss", prediction_outcome_label(0)
    assert_nil prediction_outcome_label(5)
    assert_nil prediction_outcome_label(nil)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/helpers/user_predictions_helper_test.rb`
Expected: FAIL with `NameError: uninitialized constant UserPredictionsHelper`.

- [ ] **Step 3: Create the helper**

Create `app/helpers/user_predictions_helper.rb`:

```ruby
module UserPredictionsHelper
  # Tabs for the read-only "another player's predictions" view: the owner grid's
  # stage tabs (single source of truth in FixturesHelper) minus the editing-only
  # "upcoming" tab, with a leading "past" catch-all for all locked matches.
  PREDICTION_TABS = { "past" => "Past" }.merge(FixturesHelper::STAGE_TABS.except("upcoming")).freeze

  # Maps a prediction's points_awarded to a short outcome tier + badge colour.
  # Unknown values (or nil = not yet scored) yield no label.
  PREDICTION_OUTCOMES = {
    ScoringService::EXACT_POINTS      => [ "Exact",    "badge-success" ],
    ScoringService::DIFFERENCE_POINTS => [ "Diff",     "badge-info" ],
    ScoringService::TENDENCY_POINTS   => [ "Tendency", "badge-warning" ],
    0                                 => [ "Miss",     "badge-ghost" ]
  }.freeze

  def prediction_outcome_label(points)
    PREDICTION_OUTCOMES.dig(points, 0)
  end

  def prediction_outcome_badge_class(points)
    PREDICTION_OUTCOMES.dig(points, 1) || "badge-warning"
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/helpers/user_predictions_helper_test.rb`
Expected: PASS (2 runs, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/helpers/user_predictions_helper.rb test/helpers/user_predictions_helper_test.rb
git commit -m "feat: add UserPredictionsHelper tabs and outcome labels"
```

---

### Task 3: Route, controller, view, and read-only comparison partials

**Files:**
- Modify: `config/routes.rb` (add a route after the leaderboard route, ~line 20)
- Create: `app/controllers/user_predictions_controller.rb`
- Create: `app/views/user_predictions/index.html.erb`
- Create: `app/views/user_predictions/_comparison_card.html.erb`
- Create: `app/views/user_predictions/_pick.html.erb`
- Test: `test/controllers/user_predictions_controller_test.rb`

**Interfaces:**
- Consumes: `Fixture.locked` (Task 1); `UserPredictionsHelper::PREDICTION_TABS`, `prediction_outcome_label`, `prediction_outcome_badge_class` (Task 2); `LeaderboardService.fetch_rows` → `Array<Row(rank:, user:, total_points:, ...)>`; `Fixture#home_display/#away_display/#home_flag/#away_flag`, `kickoff_label(fixture)`.
- Produces: route helper `user_predictions_path(user, stage:)`; controller ivars `@user`, `@stage`, `@fixtures`, `@by_date`, `@grouped`, `@owner_predictions` (Hash fixture_id→Prediction), `@viewer_predictions` (same), `@user_row` (Row|nil).
- The `_comparison_card` partial locals: `fixture:`, `owner:` (User), `owner_prediction:` (Prediction|nil), `viewer_prediction:` (Prediction|nil).
- The `_pick` partial locals: `who:` (String), `prediction:` (Prediction|nil), `finished:` (Boolean).

- [ ] **Step 1: Write the failing controller + partial tests**

Create `test/controllers/user_predictions_controller_test.rb`:

```ruby
require "test_helper"

class UserPredictionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @viewer = users(:one)
    @target = users(:two)
    @locked_fixture = fixtures(:finished_group)  # Brazil 2–1 France, finished (locked)
    @open_fixture = fixtures(:upcoming_group)     # Spain v Canada, scheduled (open)
  end

  test "requires authentication" do
    get user_predictions_path(@target)
    assert_redirected_to new_session_path
  end

  test "returns 404 for an unknown user" do
    sign_in_as @viewer
    get user_predictions_path(id: 999_999)
    assert_response :not_found
  end

  test "shows the target's prediction, the result and the points for a locked match" do
    sign_in_as @viewer
    get user_predictions_path(@target)

    assert_response :success
    assert_match "User Two", response.body  # whose predictions we're viewing
    assert_match "Brazil", response.body    # the locked fixture is shown
    assert_match "2–1", response.body       # their pick and the actual result
    assert_match "+5", response.body        # points earned (two_finished fixture)
  end

  test "never reveals the target's prediction on a match still open to predict" do
    # The target has an OPEN prediction. It must never appear on a foreign view —
    # this is the anti-cheat boundary.
    @target.predictions.create!(fixture: @open_fixture, home_score: 1, away_score: 1)

    sign_in_as @viewer
    get user_predictions_path(@target, stage: "group")

    assert_response :success
    assert_match "Brazil", response.body   # locked group match present
    refute_match "Canada", response.body   # open group match absent entirely
  end

  test "shows the viewer's own prediction head-to-head" do
    # Seed the viewer's pick on the locked match, bypassing the kickoff lock that
    # a normal save would reject (YAML fixtures bypass validations the same way).
    own = @viewer.predictions.build(fixture: @locked_fixture, home_score: 0, away_score: 3)
    own.save!(validate: false)

    sign_in_as @viewer
    get user_predictions_path(@target)

    assert_response :success
    assert_match "User Two", response.body  # the target's column
    assert_match "0–3", response.body       # the viewer's own pick
  end

  test "defaults to the Past tab and marks it current" do
    sign_in_as @viewer
    get user_predictions_path(@target)
    assert_select "a[aria-current=page]", text: "Past"
  end

  test "comparison card is read-only — no form, inputs or submit path" do
    html = ApplicationController.render(
      partial: "user_predictions/comparison_card",
      locals: {
        fixture: @locked_fixture,
        owner: @target,
        owner_prediction: predictions(:two_finished),
        viewer_prediction: nil
      }
    )

    assert_includes html, "User Two"       # owner column label
    assert_includes html, "No prediction"  # viewer column (nil prediction)
    refute_includes html, "<form"
    refute_includes html, "<input"
    refute_includes html, "fixture_prediction"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/user_predictions_controller_test.rb`
Expected: FAIL — `NameError: undefined ... user_predictions_path` (route missing).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, add immediately after the leaderboard route (line 20):

```ruby
  # Read-only: view another player's predictions for matches no longer open to
  # predict (linked from the leaderboard). Numeric id; auth required.
  get "users/:id/predictions", to: "user_predictions#index", as: :user_predictions
```

- [ ] **Step 4: Create the controller**

Create `app/controllers/user_predictions_controller.rb`:

```ruby
class UserPredictionsController < ApplicationController
  # GET /users/:id/predictions — a read-only, head-to-head view of another
  # player's predictions, restricted to matches no longer open to prediction
  # (Fixture.locked) so a player's still-open guesses can never leak.
  def index
    @user = User.find(params[:id])
    @stage = params[:stage].presence_in(UserPredictionsHelper::PREDICTION_TABS.keys) || "past"

    fixtures = Fixture.includes(:home_team, :away_team, :stadium).locked

    if @stage == "past"
      @fixtures = fixtures.order(kickoff_at: :desc).to_a
      @by_date = @fixtures.group_by { |fixture| fixture.kickoff_at.in_time_zone.to_date }
    else
      @fixtures = fixtures.by_stage(@stage).order(:match_number, :kickoff_at).to_a
      @grouped = @fixtures.group_by { |fixture| fixture.home_team.group_name }.sort_by(&:first) if @stage == "group"
    end

    # Two queries, indexed by fixture id, scoped to the locked fixtures on screen
    # — the target's open predictions are never even fetched.
    fixture_ids = @fixtures.map(&:id)
    @owner_predictions = @user.predictions.where(fixture_id: fixture_ids).index_by(&:fixture_id)
    @viewer_predictions = Current.user.predictions.where(fixture_id: fixture_ids).index_by(&:fixture_id)

    # Header context (rank + points); nil if the target has no scored predictions.
    @user_row = LeaderboardService.fetch_rows.find { |row| row.user.id == @user.id }
  end
end
```

- [ ] **Step 5: Create the `_pick` partial**

Create `app/views/user_predictions/_pick.html.erb`:

```erb
<%# locals: (who:, prediction:, finished:) — one player's pick in the head-to-head. -%>
<div class="rounded-lg bg-base-200/50 px-3 py-2">
  <p class="font-semibold uppercase tracking-wide text-charcoal/50"><%= who %></p>
  <% if prediction %>
    <p class="mt-1 flex flex-wrap items-center gap-1.5">
      <span class="font-bold tabular-nums text-charcoal/80"><%= prediction.home_score %>–<%= prediction.away_score %></span>
      <% if finished && prediction.points_awarded.present? %>
        <span class="badge badge-sm <%= prediction_outcome_badge_class(prediction.points_awarded) %>">
          +<%= prediction.points_awarded %><% if (label = prediction_outcome_label(prediction.points_awarded)) %> · <%= label %><% end %>
        </span>
      <% end %>
    </p>
  <% else %>
    <p class="mt-1 italic text-charcoal/40">No prediction</p>
  <% end %>
</div>
```

- [ ] **Step 6: Create the `_comparison_card` partial**

Create `app/views/user_predictions/_comparison_card.html.erb`:

```erb
<%# locals: (fixture:, owner:, owner_prediction:, viewer_prediction:) — read-only. -%>
<article class="card bg-base-100 shadow-card rounded-2xl h-full">
  <div class="card-body flex h-full flex-col gap-4 p-5">
    <header class="flex items-start justify-between gap-3">
      <div class="min-w-0 text-xs text-charcoal/60">
        <p class="truncate font-medium text-charcoal/70"><%= fixture.stadium.name %> · <%= fixture.stadium.city %></p>
        <p class="mt-0.5">
          <time datetime="<%= fixture.kickoff_at.iso8601 %>"><%= kickoff_label(fixture) %></time>
        </p>
      </div>
      <div class="flex shrink-0 items-center gap-1.5">
        <% if fixture.live? %>
          <span class="badge badge-error animate-pulse">Live</span>
        <% elsif fixture.finished? %>
          <span class="badge badge-ghost">Full time</span>
        <% end %>
      </div>
    </header>

    <div class="flex items-center justify-between gap-3">
      <div class="flex min-w-0 flex-1 flex-col items-center gap-1.5 text-center">
        <span class="text-3xl leading-none" aria-hidden="true"><%= fixture.home_flag %></span>
        <span class="truncate w-full text-sm font-bold text-charcoal"><%= fixture.home_display %></span>
      </div>
      <div class="shrink-0 px-1 text-center">
        <% if fixture.finished? %>
          <div class="text-3xl font-bold tabular-nums text-pitch">
            <%= fixture.home_score %><span class="px-1 text-charcoal/30">–</span><%= fixture.away_score %>
          </div>
        <% else %>
          <div class="text-xs font-semibold uppercase tracking-wide text-charcoal/40">vs</div>
        <% end %>
      </div>
      <div class="flex min-w-0 flex-1 flex-col items-center gap-1.5 text-center">
        <span class="text-3xl leading-none" aria-hidden="true"><%= fixture.away_flag %></span>
        <span class="truncate w-full text-sm font-bold text-charcoal"><%= fixture.away_display %></span>
      </div>
    </div>

    <footer class="mt-auto grid grid-cols-2 gap-2 border-t border-base-200 pt-3 text-xs">
      <%= render "user_predictions/pick", who: owner.name, prediction: owner_prediction, finished: fixture.finished? %>
      <%= render "user_predictions/pick", who: "You", prediction: viewer_prediction, finished: fixture.finished? %>
    </footer>
  </div>
</article>
```

- [ ] **Step 7: Create the index view**

Create `app/views/user_predictions/index.html.erb`:

```erb
<% content_for :title, "#{@user.name}'s Predictions" %>

<div class="space-y-6">
  <header>
    <p class="text-sm text-charcoal/60">
      <%= link_to "← Leaderboard", leaderboard_path, class: "link link-hover" %>
    </p>
    <h1 class="page-title mt-1"><%= @user.name %>'s predictions</h1>
    <p class="mt-1 text-sm text-charcoal/60">
      <% if @user_row %>
        Rank #<%= @user_row.rank %> · <%= @user_row.total_points %> pts · their picks vs yours
      <% else %>
        Their picks vs yours
      <% end %>
    </p>
  </header>

  <nav role="tablist" class="tabs tabs-box flex-wrap gap-1 bg-base-200 p-1" aria-label="Prediction stages">
    <% UserPredictionsHelper::PREDICTION_TABS.each do |stage, label| %>
      <%= link_to label, user_predictions_path(@user, stage: stage),
                  role: "tab",
                  class: "tab #{'tab-active' if stage == @stage}",
                  aria: { current: stage == @stage ? "page" : nil } %>
    <% end %>
  </nav>

  <% if @fixtures.empty? %>
    <div class="card bg-base-100 shadow-card rounded-2xl">
      <div class="card-body items-center text-center text-sm text-base-content/60">
        No matches here yet — predictions appear once a match kicks off.
      </div>
    </div>
  <% elsif @by_date %>
    <% @by_date.each do |date, fixtures| %>
      <section class="space-y-3">
        <h2 class="section-title"><%= date.strftime("%A %-d %B") %></h2>
        <div class="grid gap-4 min-[851px]:grid-cols-2">
          <% fixtures.each do |fixture| %>
            <%= render "user_predictions/comparison_card",
                       fixture: fixture, owner: @user,
                       owner_prediction: @owner_predictions[fixture.id],
                       viewer_prediction: @viewer_predictions[fixture.id] %>
          <% end %>
        </div>
      </section>
    <% end %>
  <% elsif @grouped %>
    <% @grouped.each do |group_name, fixtures| %>
      <section class="space-y-3">
        <h2 class="section-title">Group <%= group_name %></h2>
        <div class="grid gap-4 min-[851px]:grid-cols-2">
          <% fixtures.each do |fixture| %>
            <%= render "user_predictions/comparison_card",
                       fixture: fixture, owner: @user,
                       owner_prediction: @owner_predictions[fixture.id],
                       viewer_prediction: @viewer_predictions[fixture.id] %>
          <% end %>
        </div>
      </section>
    <% end %>
  <% else %>
    <div class="grid gap-4 min-[851px]:grid-cols-2">
      <% @fixtures.each do |fixture| %>
        <%= render "user_predictions/comparison_card",
                   fixture: fixture, owner: @user,
                   owner_prediction: @owner_predictions[fixture.id],
                   viewer_prediction: @viewer_predictions[fixture.id] %>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bin/rails test test/controllers/user_predictions_controller_test.rb`
Expected: PASS (6 runs, 0 failures).

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/user_predictions_controller.rb app/views/user_predictions test/controllers/user_predictions_controller_test.rb
git commit -m "feat: read-only head-to-head view of another player's locked predictions"
```

---

### Task 4: Link player names from leaderboard surfaces

**Files:**
- Modify: `app/views/leaderboards/_table.html.erb:56`
- Modify: `app/views/leaderboards/show.html.erb:29`
- Modify: `app/views/dashboard/show.html.erb:150-152`
- Test: `test/controllers/leaderboards_controller_test.rb` (add 2 methods), `test/controllers/dashboard_controller_test.rb` (add 1 method)

**Interfaces:**
- Consumes: `user_predictions_path(user)` (Task 3); the `_table` partial's existing `mine` boolean (line 42) and `viewer` local; the dashboard's existing `is_you` boolean (line 140); `Current.user` in the podium.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/leaderboards_controller_test.rb` inside the class:

```ruby
  test "links other players' names to their predictions but not the viewer's own" do
    sign_in_as users(:two)
    get leaderboard_path

    assert_select "a[href=?]", user_predictions_path(users(:one))
    assert_select "a[href=?]", user_predictions_path(users(:two)), count: 0
  end

  test "podium links other players but not the viewer" do
    # The podium only renders with at least three players.
    User.create!(name: "User Three", email_address: "three@example.com", password: "password")
    sign_in_as users(:two)
    get leaderboard_path

    assert_select "section[aria-label='Top three players']" do
      assert_select "a[href=?]", user_predictions_path(users(:one))
      assert_select "a[href=?]", user_predictions_path(users(:two)), count: 0
    end
  end
```

Add to `test/controllers/dashboard_controller_test.rb` inside the class:

```ruby
  test "top-five player names link to their predictions, except the viewer" do
    sign_in_as(@user)  # @user is users(:one)
    get root_path

    assert_select "a[href=?]", user_predictions_path(users(:two))
    assert_select "a[href=?]", user_predictions_path(@user), count: 0
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/leaderboards_controller_test.rb test/controllers/dashboard_controller_test.rb -n "/links|podium|top-five/"`
Expected: FAIL — the expected `<a href>` elements are not found (names are plain text).

- [ ] **Step 3: Link the name in the main table**

In `app/views/leaderboards/_table.html.erb`, replace line 56 (`<span><%= row.user.name %></span>`) with:

```erb
                  <% if mine %>
                    <span><%= row.user.name %></span>
                  <% else %>
                    <%= link_to row.user.name, user_predictions_path(row.user), class: "link link-hover" %>
                  <% end %>
```

- [ ] **Step 4: Link the name in the podium**

In `app/views/leaderboards/show.html.erb`, replace line 29 (the `<p ... title=...>` with `player.user.name.split.first`) with:

```erb
          <% if Current.user && player.user.id == Current.user.id %>
            <p class="mt-2 truncate text-sm font-bold sm:text-base" title="<%= player.user.name %>"><%= player.user.name.split.first %></p>
          <% else %>
            <p class="mt-2 truncate text-sm font-bold sm:text-base" title="<%= player.user.name %>">
              <%= link_to player.user.name.split.first, user_predictions_path(player.user), class: "link link-hover" %>
            </p>
          <% end %>
```

- [ ] **Step 5: Link the name in the dashboard top-5**

In `app/views/dashboard/show.html.erb`, replace the name span at lines 150-152:

```erb
                        <span class="font-medium text-charcoal">
                          <%= row.user.name %><%= " (you)" if is_you %>
                        </span>
```

with:

```erb
                        <span class="font-medium text-charcoal">
                          <% if is_you %>
                            <%= row.user.name %> (you)
                          <% else %>
                            <%= link_to row.user.name, user_predictions_path(row.user), class: "link link-hover" %>
                          <% end %>
                        </span>
```

- [ ] **Step 6: Run tests to verify they pass (and nothing regressed)**

Run: `bin/rails test test/controllers/leaderboards_controller_test.rb test/controllers/dashboard_controller_test.rb`
Expected: PASS (all runs, 0 failures) — including the pre-existing broadcast/nil-current_user and rank tests.

- [ ] **Step 7: Commit**

```bash
git add app/views/leaderboards/_table.html.erb app/views/leaderboards/show.html.erb app/views/dashboard/show.html.erb test/controllers/leaderboards_controller_test.rb test/controllers/dashboard_controller_test.rb
git commit -m "feat: link leaderboard player names to their predictions"
```

---

### Task 5: End-to-end system test

**Files:**
- Test: `test/system/view_other_predictions_test.rb` (create)

**Interfaces:**
- Consumes: `sign_in_through_ui(user)` (`test/application_system_test_case.rb:12`); the leaderboard page and the new predictions page.

- [ ] **Step 1: Write the system test**

Create `test/system/view_other_predictions_test.rb`:

```ruby
require "application_system_test_case"

class ViewOtherPredictionsTest < ApplicationSystemTestCase
  test "a player clicks another player's name and sees their locked predictions head-to-head" do
    # users(:two) has a scored prediction on the finished Brazil–France match.
    sign_in_through_ui users(:one)

    visit leaderboard_path
    click_link "User Two"

    assert_text "User Two's predictions"
    assert_text "Brazil"        # the locked match is shown
    assert_text "France"
    assert_text "You"           # the head-to-head column for the viewer
    assert_no_selector "form"   # read-only — no prediction forms anywhere
  end
end
```

- [ ] **Step 2: Run the system test**

Run: `bin/rails test:system TEST=test/system/view_other_predictions_test.rb`
Expected: PASS (1 runs, 0 failures). (Requires headless Chrome, same as `predict_and_score_test.rb`.)

- [ ] **Step 3: Commit**

```bash
git add test/system/view_other_predictions_test.rb
git commit -m "test: system test for viewing another player's predictions"
```

---

### Task 6: Full-suite verification

- [ ] **Step 1: Run the entire test suite**

Run: `bin/rails test`
Expected: PASS — 0 failures, 0 errors. Confirms no regression in leaderboard, dashboard, or fixtures tests.

- [ ] **Step 2: Run the system suite**

Run: `bin/rails test:system`
Expected: PASS — 0 failures, 0 errors.

- [ ] **Step 3: Lint (matches CI)**

Run: `bin/rubocop` (if present) and `bin/brakeman -q` (if present).
Expected: no new offenses / no new warnings. The new route exposes another user's locked predictions by design — confirm Brakeman raises no auth/authorization warning on `UserPredictionsController`.

---

## Self-Review

**Spec coverage:**
- Security gate `locked?` via `Fixture.locked` → Task 1. ✓
- Route with numeric id → Task 3 (route step). ✓
- Read-only controller/view/partial, head-to-head, result + points → Task 3. ✓
- Filter tabs (Past + per-stage, minus upcoming/unpredicted) → Task 2 (`PREDICTION_TABS`) + Task 3 (view tablist). ✓
- Links on all three leaderboard surfaces, self-suppressed → Task 4. ✓
- Tests: scope, anti-cheat (open prediction hidden), locked shown read-only, head-to-head, no-form partial, link targets, system flow → Tasks 1,3,4,5. ✓
- "No longer open" defined as `locked?` not `past`; live/finished-before-kickoff captured → Task 1 scope + its test. ✓
- Out-of-scope items (no slug, no owner-grid changes, no upcoming/unpredicted tabs, no Turbo) → honored; no task touches them. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to" — every step has complete code. ✓

**Type consistency:** `PREDICTION_TABS` keys drive both the controller's `presence_in` (Task 3) and the view tablist (Task 3), defined in Task 2. `prediction_outcome_label`/`prediction_outcome_badge_class` defined in Task 2, consumed in Task 3's `_pick`. Controller ivars `@owner_predictions`/`@viewer_predictions`/`@by_date`/`@grouped`/`@user_row` (Task 3 controller) match the index view's usage (Task 3 view). `user_predictions_path(user, stage:)` defined in Task 3, consumed in Tasks 3,4,5. `Row#user` used (not `user_id`) in the controller's `@user_row` lookup, matching `LeaderboardService::Row` (`leaderboard_service.rb:4`). ✓

**Edge cases:** `@user_row` nil → header degrades (view `if @user_row`). Locked-but-not-finished → `_comparison_card` shows "vs"/Live and `_pick` omits the points badge (guarded by `finished && points_awarded.present?`). Unknown id → `User.find` raises `RecordNotFound` → 404 (tested). ✓
