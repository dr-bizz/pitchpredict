# Knockout TBD Bracket + Admin Team Entry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the placeholder qualifier teams from all knockout fixtures (R32→Final), show them as descriptive "TBD" cards, and give the admin a screen to enter each match's real teams once announced.

**Architecture:** Make `Fixture` team foreign keys nullable and add `home_slot_label` / `away_slot_label` / `match_number`. A new pure-data `KnockoutBracket` module is the single source of truth for the 32-match topology (match numbers + slot labels); seeds, a `KnockoutReset` service (used by a data migration), and tests all consume it. A new admin controller/view assigns teams; player views render a TBD card until both teams are known.

**Tech Stack:** Rails 8.1, ActiveRecord, SQLite (dev/test) / PostgreSQL (prod), Minitest, Turbo, Tailwind/daisyUI.

## Global Constraints

- Ruby/Rails idioms already in the repo: `enum :stage, { group: 0, r32: 1, r16: 2, qf: 3, sf: 4, third_place: 5, final: 6 }, scopes: false` — use `Fixture.by_stage(:group)` / `where(stage: Fixture.stages[:group])`, never `Fixture.group`.
- Group-stage fixtures must ALWAYS keep both real teams. Only `stage != group` fixtures become TBD.
- Match numbers: group = 1–72, knockout = 73–104 (R32 73–88, R16 89–96, QF 97–100, SF 101–102, 3rd place 103, Final 104).
- Tests are Minitest; sign in with `sign_in_as(user)`; fixtures available: teams `spain/france/brazil/canada`, stadia `metlife/azteca`, users `one/two` (both players), fixtures `upcoming_group/finished_group`.
- Run the full suite with `bin/rails test`. Run one file with `bin/rails test test/path/file_test.rb`.
- Commit after each task with a `feat:`/`refactor:`/`test:` message.

---

### Task 1: `KnockoutBracket` topology module

**Files:**
- Create: `app/models/knockout_bracket.rb`
- Test: `test/models/knockout_bracket_test.rb`

**Interfaces:**
- Produces:
  - `KnockoutBracket.specs` → frozen `Array<Hash>` of 32 entries, each `{ stage: Symbol, match_number: Integer, home_label: String, away_label: String }`, ordered by `match_number`.
  - `KnockoutBracket.for(stage, index)` → the Hash for the `index`-th (0-based) match of `stage` (matches seed loop indices), or `nil`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/knockout_bracket_test.rb
require "test_helper"

class KnockoutBracketTest < ActiveSupport::TestCase
  test "defines exactly 32 knockout matches" do
    assert_equal 32, KnockoutBracket.specs.size
  end

  test "match numbers are 73..104, contiguous and unique" do
    numbers = KnockoutBracket.specs.map { |s| s[:match_number] }
    assert_equal (73..104).to_a, numbers.sort
  end

  test "each stage has the right number of matches" do
    counts = KnockoutBracket.specs.group_by { |s| s[:stage] }.transform_values(&:size)
    assert_equal({ r32: 16, r16: 8, qf: 4, sf: 2, third_place: 1, final: 1 }, counts)
  end

  test "R32 labels cover every group winner and runner-up plus eight thirds" do
    labels = KnockoutBracket.specs.select { |s| s[:stage] == :r32 }
                            .flat_map { |s| [ s[:home_label], s[:away_label] ] }
    %w[A B C D E F G H I J K L].each do |g|
      assert_includes labels, "Winner Group #{g}"
      assert_includes labels, "Runner-up Group #{g}"
    end
    assert_equal 8, labels.count { |l| l.start_with?("3rd Place") }
  end

  test "later-round labels only reference real earlier match numbers" do
    numbers = KnockoutBracket.specs.map { |s| s[:match_number] }.to_set
    KnockoutBracket.specs.each do |spec|
      [ spec[:home_label], spec[:away_label] ].each do |label|
        if (m = label.match(/Match (\d+)/))
          referenced = m[1].to_i
          assert_includes numbers, referenced, "#{label} references missing match #{referenced}"
          assert referenced < spec[:match_number], "#{label} must reference an earlier match"
        end
      end
    end
  end

  test "for returns the spec by stage and zero-based index" do
    assert_equal 73, KnockoutBracket.for(:r32, 0)[:match_number]
    assert_equal 88, KnockoutBracket.for(:r32, 15)[:match_number]
    assert_equal 104, KnockoutBracket.for(:final, 0)[:match_number]
    assert_nil KnockoutBracket.for(:r32, 99)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/knockout_bracket_test.rb`
Expected: FAIL with `uninitialized constant KnockoutBracket`.

- [ ] **Step 3: Implement the module**

```ruby
# app/models/knockout_bracket.rb
#
# Single source of truth for the knockout-stage topology. The qualifiers are
# unknown until the group stage ends, so each slot carries a descriptive LABEL
# (e.g. "Winner Group A", "Winner of Match 89") rather than a team. The match
# numbers and the match-to-match feeding form a clean, internally consistent
# single-elimination tree (the actual group pairings are illustrative).
#
# Pure data + lookup — no database access — so it is safe to use from seeds, a
# data migration, and unit tests alike.
module KnockoutBracket
  GROUPS = %w[A B C D E F G H I J K L].freeze

  # R32 slot labels, in the same pairing order the seeds build (home bracket[i]
  # vs away bracket[31-i], where bracket = winners(0-11) + runners(12-23) +
  # thirds(24-31)). Index 0..15 -> match numbers 73..88.
  R32 = begin
    winners = GROUPS.map { |g| "Winner Group #{g}" }
    runners = GROUPS.map { |g| "Runner-up Group #{g}" }
    thirds  = GROUPS.first(8).map { |g| "3rd Place — Group #{g}" }
    bracket = winners + runners + thirds # 32 labels
    (0..15).map { |i| { home_label: bracket[i], away_label: bracket[31 - i] } }
  end.freeze

  def self.specs
    @specs ||= build.freeze
  end

  # The index-th (0-based) match of a stage, matching the seed loop counters.
  def self.for(stage, index)
    by_stage_index[[ stage.to_sym, index ]]
  end

  def self.build
    rows = []
    R32.each_with_index { |labels, i| rows << { stage: :r32, match_number: 73 + i, **labels } }

    # Each round pairs the winners of two consecutive earlier matches.
    pair = ->(stage, base, count, src_start) do
      count.times do |n|
        rows << {
          stage: stage, match_number: base + n,
          home_label: "Winner of Match #{src_start + (2 * n)}",
          away_label: "Winner of Match #{src_start + (2 * n) + 1}"
        }
      end
    end
    pair.call(:r16, 89, 8, 73) # R16 89..96 from R32 73..88
    pair.call(:qf,  97, 4, 89) # QF  97..100 from R16 89..96
    pair.call(:sf, 101, 2, 97) # SF  101..102 from QF 97..100

    rows << { stage: :third_place, match_number: 103,
              home_label: "Loser of Match 101", away_label: "Loser of Match 102" }
    rows << { stage: :final, match_number: 104,
              home_label: "Winner of Match 101", away_label: "Winner of Match 102" }
    rows
  end

  def self.by_stage_index
    @by_stage_index ||= specs
      .group_by { |s| s[:stage] }
      .flat_map { |stage, list| list.each_with_index.map { |s, i| [[ stage, i ], s] } }
      .to_h
  end

  private_class_method :build, :by_stage_index
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/models/knockout_bracket_test.rb`
Expected: PASS (6 runs, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/models/knockout_bracket.rb test/models/knockout_bracket_test.rb
git commit -m "feat: add KnockoutBracket topology source of truth"
```

---

### Task 2: Schema migration — nullable teams + new columns

**Files:**
- Create: `db/migrate/<timestamp>_add_knockout_slots_to_fixtures.rb` (via generator)
- Modify: `db/schema.rb` (regenerated by migrate)

**Interfaces:**
- Produces: `fixtures.home_team_id` / `away_team_id` nullable; new columns `home_slot_label:string`, `away_slot_label:string`, `match_number:integer`.

- [ ] **Step 1: Generate the migration**

Run: `bin/rails g migration AddKnockoutSlotsToFixtures`

- [ ] **Step 2: Write the migration body**

```ruby
# db/migrate/<timestamp>_add_knockout_slots_to_fixtures.rb
class AddKnockoutSlotsToFixtures < ActiveRecord::Migration[8.1]
  def change
    change_column_null :fixtures, :home_team_id, true
    change_column_null :fixtures, :away_team_id, true
    add_column :fixtures, :home_slot_label, :string
    add_column :fixtures, :away_slot_label, :string
    add_column :fixtures, :match_number, :integer
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `bin/rails db:migrate`
Expected: migration runs; `db/schema.rb` now shows `home_team_id` / `away_team_id` without `null: false` and the three new columns.

- [ ] **Step 4: Verify the suite still green (no behavior change yet)**

Run: `bin/rails test`
Expected: PASS (existing tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat: make fixture teams nullable, add slot labels and match number"
```

---

### Task 3: `Fixture` model — optional teams, validations, display helpers

**Files:**
- Modify: `app/models/fixture.rb`
- Test: `test/models/fixture_test.rb`

**Interfaces:**
- Produces (instance methods):
  - `teams_known?` → `Boolean`
  - `open_for_predictions?` → `Boolean` (`teams_known? && !locked?`)
  - `home_display` / `away_display` → `String` (team name, else slot label, else "TBD")
  - `home_flag` / `away_flag` → `String` (team flag emoji, else "🏳️")

- [ ] **Step 1: Write the failing tests** (append inside the existing `FixtureTest` class)

```ruby
# test/models/fixture_test.rb — add these tests
  test "knockout fixture is valid with no teams and slot labels" do
    fixture = Fixture.new(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_slot_label: "Winner Group A",
                          away_slot_label: "Runner-up Group B", match_number: 73)
    assert fixture.valid?, fixture.errors.full_messages.to_sentence
    assert_not fixture.teams_known?
  end

  test "group fixture requires both teams" do
    fixture = Fixture.new(stadium: stadia(:metlife), kickoff_at: 5.days.from_now, stage: :group)
    assert_not fixture.valid?
    assert fixture.errors.added?(:base, "Group fixtures require both teams")
  end

  test "a knockout fixture cannot have only one team" do
    fixture = Fixture.new(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_team: teams(:spain))
    assert_not fixture.valid?
    assert fixture.errors.added?(:base, "Both teams must be set together")
  end

  test "teams_known? and open_for_predictions? reflect team presence" do
    known = fixtures(:upcoming_group)
    assert known.teams_known?
    assert known.open_for_predictions?

    tbd = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_slot_label: "Winner Group A",
                          away_slot_label: "Runner-up Group B", match_number: 73)
    assert_not tbd.open_for_predictions?
  end

  test "display helpers fall back to slot label then TBD" do
    tbd = Fixture.new(stage: :r16, home_slot_label: "Winner of Match 73")
    assert_equal "Winner of Match 73", tbd.home_display
    assert_equal "TBD", tbd.away_display
    assert_equal "🏳️", tbd.home_flag
    assert_equal "Spain", fixtures(:upcoming_group).home_display
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/fixture_test.rb`
Expected: FAIL (`NoMethodError: teams_known?` / validation messages absent).

- [ ] **Step 3: Implement the model changes**

```ruby
# app/models/fixture.rb — replace the belongs_to lines and add methods/validations
class Fixture < ApplicationRecord
  belongs_to :home_team, class_name: "Team", inverse_of: :home_fixtures, optional: true
  belongs_to :away_team, class_name: "Team", inverse_of: :away_fixtures, optional: true
  belongs_to :stadium
  has_many :predictions, dependent: :destroy

  enum :stage, { group: 0, r32: 1, r16: 2, qf: 3, sf: 4, third_place: 5, final: 6 }, scopes: false
  enum :status, { scheduled: 0, live: 1, finished: 2 }

  validates :kickoff_at, presence: true
  validates :home_score, :away_score,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :home_score, :away_score, presence: true, if: :finished?
  validate :teams_must_differ
  validate :group_fixtures_have_teams
  validate :teams_present_together

  scope :upcoming, -> { where(kickoff_at: Time.current..).order(:kickoff_at) }
  scope :past, -> { where(kickoff_at: ...Time.current).order(kickoff_at: :desc) }
  scope :by_stage, ->(stage) { where(stage: stage) }

  def locked?
    kickoff_at <= Time.current || !scheduled?
  end

  # Both qualifiers have been entered (always true for group fixtures).
  def teams_known?
    home_team_id.present? && away_team_id.present?
  end

  def open_for_predictions?
    teams_known? && !locked?
  end

  def home_display = home_team&.name || home_slot_label || "TBD"
  def away_display = away_team&.name || away_slot_label || "TBD"
  def home_flag = home_team&.flag_emoji || "🏳️"
  def away_flag = away_team&.flag_emoji || "🏳️"

  private

  def teams_must_differ
    return if home_team_id.blank? || home_team_id != away_team_id

    errors.add(:away_team, "can't be the same as the home team")
  end

  def group_fixtures_have_teams
    return unless group?

    errors.add(:base, "Group fixtures require both teams") unless teams_known?
  end

  # A knockout match has either both teams or neither — never a half-filled slot.
  def teams_present_together
    return if home_team_id.present? == away_team_id.present?

    errors.add(:base, "Both teams must be set together")
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/models/fixture_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/fixture.rb test/models/fixture_test.rb
git commit -m "feat: support teams-unknown knockout fixtures on Fixture model"
```

---

### Task 4: `Prediction` model — block TBD matches

**Files:**
- Modify: `app/models/prediction.rb`
- Test: `test/models/prediction_test.rb`

**Interfaces:**
- Consumes: `Fixture#teams_known?`, `Fixture#locked?` (Task 3).

- [ ] **Step 1: Write the failing test** (append to `PredictionTest`)

```ruby
# test/models/prediction_test.rb — add this test
  test "cannot predict a knockout fixture whose teams are not yet known" do
    tbd = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_slot_label: "Winner Group A",
                          away_slot_label: "Runner-up Group B", match_number: 73)
    prediction = users(:one).predictions.build(fixture: tbd, home_score: 1, away_score: 0)
    assert_not prediction.valid?
    assert prediction.errors.added?(:base, "Teams for this match haven't been announced yet")
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/prediction_test.rb`
Expected: FAIL (prediction currently considered valid).

- [ ] **Step 3: Implement the guard**

```ruby
# app/models/prediction.rb — replace fixture_must_be_open
  def fixture_must_be_open
    return unless fixture

    if !fixture.teams_known?
      errors.add(:base, "Teams for this match haven't been announced yet")
    elsif fixture.locked?
      errors.add(:base, "Predictions are locked for this match")
    end
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/models/prediction_test.rb`
Expected: PASS (existing "locked" test still green — message unchanged).

- [ ] **Step 5: Commit**

```bash
git add app/models/prediction.rb test/models/prediction_test.rb
git commit -m "feat: reject predictions on knockout matches with unknown teams"
```

---

### Task 5: Seeds — create knockout fixtures as TBD with labels

**Files:**
- Modify: `db/seeds.rb` (lines ~199–247: the knockout placeholder + fixture-creation blocks)

**Interfaces:**
- Consumes: `KnockoutBracket.for(stage, index)` (Task 1), nullable team columns (Task 2).

- [ ] **Step 1: Replace the illustrative bracket block**

Replace the current knockout block (the `winners/runners/thirds/bracket` arrays and the six `specs <<` loops, lines ~199–224) with label-based specs. Each spec now carries `home_label`/`away_label`/`match_number` and NO teams:

```ruby
  # Knockout fixtures — qualifiers are unknown, so teams are nil and each slot
  # carries a descriptive label from KnockoutBracket. The schedule (dates,
  # stadiums) is fixed; an admin fills in teams as the bracket is announced.
  knockout_stadium = ->(i) { stadiums[i % stadiums.length] }
  ko = ->(stage, index, stadium, kickoff) do
    spec = KnockoutBracket.for(stage, index)
    { home: nil, away: nil, stadium:, kickoff:, stage:,
      home_label: spec[:home_label], away_label: spec[:away_label],
      match_number: spec[:match_number] }
  end

  16.times do |i| # Round of 32: June 28 – July 3
    kickoff = Time.zone.local(2026, 6, 28, kickoff_hours[i % 3]) + (i / 3).days
    specs << ko.call(:r32, i, knockout_stadium.call(i), kickoff)
  end
  8.times do |j| # Round of 16: July 4 – 7
    kickoff = Time.zone.local(2026, 7, 4, kickoff_hours[j % 3]) + (j / 2).days
    specs << ko.call(:r16, j, knockout_stadium.call(j + 3), kickoff)
  end
  4.times do |k| # Quarter-finals: July 9 – 10
    kickoff = Time.zone.local(2026, 7, 9, kickoff_hours[k % 2]) + (k / 2).days
    specs << ko.call(:qf, k, knockout_stadium.call(k + 6), kickoff)
  end
  2.times do |s| # Semi-finals: July 14 – 15
    kickoff = Time.zone.local(2026, 7, 14, 19) + s.days
    specs << ko.call(:sf, s, knockout_stadium.call(s + 10), kickoff)
  end
  specs << ko.call(:third_place, 0, stadiums[10], Time.zone.local(2026, 7, 18, 19))
  specs << ko.call(:final, 0, stadiums[5], Time.zone.local(2026, 7, 19, 19))
```

- [ ] **Step 2: Give group fixtures a match number and pass labels through creation**

The group specs are built earlier (the `group_schedule.each` block, ~line 193). Add a sequential `match_number` there:

```ruby
  group_schedule.each_with_index do |(home_code, away_code, (mon, day, hr, min), stadium_idx), idx|
    kickoff = Time.zone.local(2026, mon, day, hr, min)
    specs << { home: team_by_code.fetch(home_code), away: team_by_code.fetch(away_code),
               stadium: stadiums[stadium_idx], kickoff:, stage: :group, match_number: idx + 1 }
  end
```

Then update the single `Fixture.create!` call (~line 243) to pass the new attributes (slot labels default to nil for group specs):

```ruby
    fixture = Fixture.create!(home_team: spec[:home], away_team: spec[:away],
                              stadium: spec[:stadium], kickoff_at: provisional, stage: spec[:stage],
                              home_slot_label: spec[:home_label], away_slot_label: spec[:away_label],
                              match_number: spec[:match_number])
```

- [ ] **Step 3: Run the seeds against a scratch database to verify**

Run: `bin/rails db:reset` (test it actually loads — destructive on dev DB, which is expected for this app)
Expected output includes `Seeded: 48 teams, 16 stadiums, 104 fixtures ...` and NO error. Knockout fixtures have nil teams.

Verify in console:
```bash
bin/rails runner 'puts Fixture.where.not(stage: 0).where(home_team_id: nil).count; puts Fixture.where.not(stage: 0).pluck(:home_slot_label).first(3).inspect'
```
Expected: `32` then three slot-label strings.

- [ ] **Step 4: Commit**

```bash
git add db/seeds.rb
git commit -m "seed: knockout fixtures start as TBD with descriptive slot labels"
```

---

### Task 6: `KnockoutReset` service — bring existing databases in line

**Files:**
- Create: `app/services/knockout_reset.rb`
- Test: `test/services/knockout_reset_test.rb`

**Interfaces:**
- Consumes: `KnockoutBracket.specs` (Task 1).
- Produces: `KnockoutReset.call` → resets every non-group fixture to TBD (nil teams/scores, `scheduled`, slot labels + match number from `KnockoutBracket`), deletes their predictions, and backfills group `match_number`s. Idempotent.

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/knockout_reset_test.rb
require "test_helper"

class KnockoutResetTest < ActiveSupport::TestCase
  setup do
    # A knockout fixture that still has placeholder teams + a prediction, as a
    # pre-migration production database would.
    @ko = Fixture.create!(home_team: teams(:spain), away_team: teams(:canada),
                          stadium: stadia(:metlife), kickoff_at: 25.days.from_now, stage: :r32)
    @prediction = users(:one).predictions.create!(fixture: @ko, home_score: 1, away_score: 0)
  end

  test "clears teams, scores and predictions on knockout fixtures" do
    KnockoutReset.call
    @ko.reload
    assert_nil @ko.home_team_id
    assert_nil @ko.away_team_id
    assert @ko.scheduled?
    assert_not Prediction.exists?(@prediction.id)
  end

  test "assigns slot labels and match numbers from KnockoutBracket" do
    KnockoutReset.call
    assert_equal 32, Fixture.where.not(stage: Fixture.stages[:group]).where.not(home_slot_label: nil).count
    assert_equal (73..104).to_a, Fixture.where.not(stage: Fixture.stages[:group]).pluck(:match_number).sort
  end

  test "leaves group fixtures' teams intact and numbers them" do
    KnockoutReset.call
    assert_equal teams(:spain).id, fixtures(:upcoming_group).reload.home_team_id
    assert Fixture.where(stage: Fixture.stages[:group]).where.not(match_number: nil).exists?
  end

  test "is idempotent" do
    KnockoutReset.call
    assert_nothing_raised { KnockoutReset.call }
    assert_equal 32, Fixture.where.not(stage: Fixture.stages[:group]).count
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/knockout_reset_test.rb`
Expected: FAIL (`uninitialized constant KnockoutReset`).

- [ ] **Step 3: Implement the service**

```ruby
# app/services/knockout_reset.rb
#
# One-time, idempotent normalisation for databases seeded BEFORE knockout
# fixtures were TBD. Used by the backfill migration (and safe to re-run): clears
# the placeholder teams/scores/predictions on every knockout fixture and stamps
# the KnockoutBracket slot labels + match numbers. Also numbers group fixtures.
class KnockoutReset
  GROUP = 0 # Fixture.stages[:group]

  def self.call
    new.call
  end

  def call
    Fixture.transaction do
      number_group_fixtures
      reset_knockout_fixtures
    end
    LeaderboardService.expire_rows if defined?(LeaderboardService)
  end

  private

  def number_group_fixtures
    Fixture.where(stage: GROUP).order(:kickoff_at, :id).each_with_index do |fixture, i|
      fixture.update_columns(match_number: i + 1)
    end
  end

  def reset_knockout_fixtures
    specs = KnockoutBracket.specs.sort_by { |s| s[:match_number] }
    knockouts = Fixture.where.not(stage: GROUP).order(:stage, :kickoff_at, :id).to_a

    knockouts.zip(specs).each do |fixture, spec|
      next unless spec

      Prediction.where(fixture_id: fixture.id).delete_all
      fixture.update_columns(
        home_team_id: nil, away_team_id: nil, home_score: nil, away_score: nil,
        status: 0, # scheduled
        home_slot_label: spec[:home_label], away_slot_label: spec[:away_label],
        match_number: spec[:match_number]
      )
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/knockout_reset_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/knockout_reset.rb test/services/knockout_reset_test.rb
git commit -m "feat: add idempotent KnockoutReset for existing databases"
```

---

### Task 7: Data migration that runs `KnockoutReset`

**Files:**
- Create: `db/migrate/<timestamp>_backfill_knockout_slots.rb` (via generator)

**Interfaces:**
- Consumes: `KnockoutReset.call` (Task 6).

- [ ] **Step 1: Generate the migration**

Run: `bin/rails g migration BackfillKnockoutSlots`

- [ ] **Step 2: Write the migration body**

```ruby
# db/migrate/<timestamp>_backfill_knockout_slots.rb
class BackfillKnockoutSlots < ActiveRecord::Migration[8.1]
  def up
    KnockoutReset.call
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `bin/rails db:migrate`
Expected: completes without error (on a freshly-seeded dev DB it is effectively a no-op since seeds already produce TBD knockouts).

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat: backfill existing databases to TBD knockout bracket"
```

---

### Task 8: Admin knockout-entry controller + routes + shared base controller

**Files:**
- Create: `app/controllers/admin/base_controller.rb`
- Create: `app/controllers/admin/knockout_fixtures_controller.rb`
- Modify: `app/controllers/admin/fixtures_controller.rb` (inherit base, drop duplicate `require_admin`)
- Modify: `config/routes.rb` (add `knockout_fixtures`)
- Test: `test/controllers/admin/knockout_fixtures_controller_test.rb`

**Interfaces:**
- Consumes: `Fixture#home_display` / `away_display` / `teams_known?` (Task 3).
- Produces: routes `admin_knockout_fixtures_path` (index) and `admin_knockout_fixture_path(fixture)` (PATCH update).

- [ ] **Step 1: Write the failing controller test**

```ruby
# test/controllers/admin/knockout_fixtures_controller_test.rb
require "test_helper"

module Admin
  class KnockoutFixturesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(name: "Admin", email_address: "admin-ko@example.com",
                            password: "password", role: :admin)
      @player = users(:one)
      @ko = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 25.days.from_now,
                            stage: :r32, home_slot_label: "Winner Group A",
                            away_slot_label: "Runner-up Group B", match_number: 73)
    end

    test "redirects non-admins" do
      sign_in_as @player
      get admin_knockout_fixtures_path
      assert_redirected_to root_path
    end

    test "index lists knockout fixtures with slot labels" do
      sign_in_as @admin
      get admin_knockout_fixtures_path
      assert_response :success
      assert_includes response.body, "Winner Group A"
    end

    test "assigning both teams makes the match predictable" do
      sign_in_as @admin
      patch admin_knockout_fixture_path(@ko),
            params: { fixture: { home_team_id: teams(:spain).id, away_team_id: teams(:canada).id } }
      assert_redirected_to admin_knockout_fixtures_path
      @ko.reload
      assert @ko.teams_known?
      assert @ko.open_for_predictions?
    end

    test "clearing a team resets the match to TBD" do
      @ko.update!(home_team: teams(:spain), away_team: teams(:canada))
      sign_in_as @admin
      patch admin_knockout_fixture_path(@ko), params: { fixture: { home_team_id: "", away_team_id: "" } }
      assert_redirected_to admin_knockout_fixtures_path
      assert_not @ko.reload.teams_known?
    end

    test "setting only one team is rejected" do
      sign_in_as @admin
      patch admin_knockout_fixture_path(@ko),
            params: { fixture: { home_team_id: teams(:spain).id, away_team_id: "" } }
      assert_redirected_to admin_knockout_fixtures_path
      assert_not @ko.reload.teams_known?
      assert_equal "Both teams must be set together", flash[:alert]
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/admin/knockout_fixtures_controller_test.rb`
Expected: FAIL (`undefined ... admin_knockout_fixtures_path`).

- [ ] **Step 3: Add the route**

```ruby
# config/routes.rb — replace the admin namespace block
  namespace :admin do
    resources :fixtures, only: %i[ index edit update ]
    resources :knockout_fixtures, only: %i[ index update ]
  end
```

- [ ] **Step 4: Create the shared base controller and refactor the existing one**

```ruby
# app/controllers/admin/base_controller.rb
module Admin
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      return if Current.user&.admin?

      redirect_to root_path, alert: "You don't have access to the admin area."
    end
  end
end
```

```ruby
# app/controllers/admin/fixtures_controller.rb — change the class line and delete
# the now-inherited require_admin method.
module Admin
  class FixturesController < BaseController
    before_action :set_fixture, only: %i[ edit update ]

    # ... index / edit / update unchanged ...

    private

    def set_fixture
      @fixture = Fixture.find(params.expect(:id))
    end

    def result_params
      params.expect(fixture: [ :home_score, :away_score ])
    end
  end
end
```

(Remove the `before_action :require_admin` line and the `require_admin` private method from `FixturesController` — they now come from `BaseController`.)

- [ ] **Step 5: Create the knockout controller**

```ruby
# app/controllers/admin/knockout_fixtures_controller.rb
module Admin
  class KnockoutFixturesController < BaseController
    def index
      @fixtures = Fixture.includes(:home_team, :away_team, :stadium)
                         .where.not(stage: Fixture.stages[:group])
                         .order(:match_number, :kickoff_at)
      @teams = Team.order(:group_name, :name)
    end

    def update
      @fixture = Fixture.find(params.expect(:id))
      if @fixture.update(knockout_params)
        redirect_to admin_knockout_fixtures_path,
                    notice: "Saved: #{@fixture.home_display} vs #{@fixture.away_display}."
      else
        redirect_to admin_knockout_fixtures_path, alert: @fixture.errors.full_messages.to_sentence
      end
    end

    private

    # Blank ("") clears a slot back to TBD; presence turns it into a real id.
    def knockout_params
      params.expect(fixture: [ :home_team_id, :away_team_id ]).transform_values(&:presence)
    end
  end
end
```

- [ ] **Step 6: Run both admin tests to verify they pass**

Run: `bin/rails test test/controllers/admin/`
Expected: PASS (existing `FixturesControllerTest` still green after the base-class refactor; new test green).

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin config/routes.rb test/controllers/admin/knockout_fixtures_controller_test.rb
git commit -m "feat: admin knockout team-entry controller + shared admin base"
```

---

### Task 9: Admin knockout view + nil-safe admin fixtures views

**Files:**
- Create: `app/views/admin/knockout_fixtures/index.html.erb`
- Modify: `app/views/admin/fixtures/index.html.erb` (nil-safe team cells + disable "Enter result" until teams known + link to knockout page)
- Modify: `app/views/admin/fixtures/edit.html.erb` (nil-safe header/labels)

**Interfaces:**
- Consumes: `@fixtures`, `@teams` (Task 8); `Fixture#home_display`/`away_display`/`teams_known?`; helpers `stage_label`, `kickoff_label`.

- [ ] **Step 1: Build the knockout admin view**

```erb
<%# app/views/admin/knockout_fixtures/index.html.erb %>
<% content_for :title, "Admin · Knockout bracket · PitchPredict" %>

<div class="space-y-6">
  <header class="flex flex-wrap items-center gap-3">
    <div>
      <h1 class="page-title text-2xl font-extrabold uppercase tracking-tight sm:text-3xl">Knockout bracket</h1>
      <p class="text-sm text-base-content/60">Enter each match's teams as the bracket is announced. A match opens for predictions once both teams are set.</p>
    </div>
    <%= link_to "← Results", admin_fixtures_path, class: "btn btn-ghost btn-sm ml-auto" %>
  </header>

  <div class="alert alert-info rounded-2xl" role="status">
    <span>Leave both as <strong>TBD</strong> until the qualifier is known. Clearing both resets a match to TBD.</span>
  </div>

  <% @fixtures.group_by(&:stage).each do |stage, fixtures| %>
    <section class="space-y-3">
      <h2 class="section-title"><%= stage_label(stage) %></h2>
      <div class="space-y-3">
        <% fixtures.each do |fixture| %>
          <%= form_with model: fixture, url: admin_knockout_fixture_path(fixture), method: :patch,
                        class: "card bg-base-100 shadow-card rounded-2xl" do |form| %>
            <div class="card-body gap-3 p-4">
              <div class="flex items-center justify-between text-xs text-base-content/50">
                <span class="font-mono">Match <%= fixture.match_number %> · <%= stage_label(fixture.stage) %></span>
                <span><%= kickoff_label(fixture) %> · <%= fixture.stadium.name %></span>
              </div>
              <div class="grid items-end gap-3 sm:grid-cols-[1fr_auto_1fr]">
                <label class="form-control">
                  <span class="label label-text text-xs text-base-content/60"><%= fixture.home_slot_label %></span>
                  <%= form.collection_select :home_team_id, @teams, :id, :name,
                        { include_blank: "TBD — not announced", selected: fixture.home_team_id },
                        class: "select select-bordered w-full" %>
                </label>
                <span class="hidden pb-3 text-xs font-semibold uppercase text-base-content/40 sm:block">vs</span>
                <label class="form-control">
                  <span class="label label-text text-xs text-base-content/60"><%= fixture.away_slot_label %></span>
                  <%= form.collection_select :away_team_id, @teams, :id, :name,
                        { include_blank: "TBD — not announced", selected: fixture.away_team_id },
                        class: "select select-bordered w-full" %>
                </label>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-xs <%= fixture.teams_known? ? "text-success" : "text-base-content/40" %>">
                  <%= fixture.teams_known? ? "Open for predictions" : "Awaiting teams" %>
                </span>
                <%= form.submit "Save", class: "btn btn-primary btn-sm" %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </section>
  <% end %>
</div>
```

- [ ] **Step 2: Make the admin fixtures index nil-safe + add the knockout link**

In `app/views/admin/fixtures/index.html.erb`, change the match cell (lines ~69–76) to use display helpers and only show codes when known:

```erb
                  <td>
                    <div class="flex items-center gap-2 font-semibold">
                      <% if fixture.home_team %>
                        <span class="badge badge-ghost badge-sm font-mono"><%= fixture.home_team.code %></span>
                      <% end %>
                      <span><%= fixture.home_display %></span>
                      <span class="font-normal text-base-content/40">vs</span>
                      <span><%= fixture.away_display %></span>
                      <% if fixture.away_team %>
                        <span class="badge badge-ghost badge-sm font-mono"><%= fixture.away_team.code %></span>
                      <% end %>
                    </div>
                    <div class="text-xs text-base-content/50"><%= kickoff_label(fixture) %></div>
                  </td>
```

Change the action cell (lines ~89–95) so result entry is blocked until teams are known:

```erb
                  <td class="text-right whitespace-nowrap">
                    <% if !fixture.teams_known? %>
                      <%= link_to "Set teams", admin_knockout_fixtures_path, class: "btn btn-ghost btn-sm text-base-content/50" %>
                    <% elsif fixture.finished? %>
                      <%= link_to "Done", edit_admin_fixture_path(fixture), class: "btn btn-ghost btn-sm text-base-content/50" %>
                    <% else %>
                      <%= link_to "Enter result", edit_admin_fixture_path(fixture), class: "btn btn-primary btn-sm" %>
                    <% end %>
                  </td>
```

Add a "Knockout bracket" link in the header area (after the `<div>` closing the title block, around line 22):

```erb
    <%= link_to "Knockout bracket", admin_knockout_fixtures_path, class: "btn btn-outline btn-sm ml-auto" %>
```

- [ ] **Step 3: Make the admin edit view nil-safe**

In `app/views/admin/fixtures/edit.html.erb`, the edit page is only reachable for `teams_known?` fixtures, but guard the dereferences anyway. Replace the breadcrumb (line 15) and title (line 28):

```erb
    <li><%= @fixture.home_display %> vs <%= @fixture.away_display %></li>
```
```erb
        <%= @fixture.home_display %> <span class="font-normal text-base-content/40">vs</span> <%= @fixture.away_display %>
```

And the two score labels (lines 51, 56) — use display helpers, dropping the code suffix when absent:

```erb
            <%= form.label :home_score, @fixture.home_display, class: "label label-text font-semibold" %>
```
```erb
            <%= form.label :away_score, @fixture.away_display, class: "label label-text font-semibold" %>
```

- [ ] **Step 4: Strengthen the controller test to assert the view renders**

The Task 8 test `index lists knockout fixtures with slot labels` already renders this view; add an assertion that the form posts to the update path. Append to that test:

```ruby
      assert_select "form[action=?]", admin_knockout_fixture_path(@ko)
      assert_select "select[name='fixture[home_team_id]']"
```

- [ ] **Step 5: Run admin tests**

Run: `bin/rails test test/controllers/admin/`
Expected: PASS (knockout index renders, admin fixtures index no longer crashes on TBD rows).

- [ ] **Step 6: Commit**

```bash
git add app/views/admin test/controllers/admin/knockout_fixtures_controller_test.rb
git commit -m "feat: admin knockout bracket view + nil-safe admin fixtures views"
```

---

### Task 10: Player fixture card TBD state + predictions ordering

**Files:**
- Modify: `app/views/fixtures/_fixture_card.html.erb` (add TBD branch)
- Modify: `app/controllers/fixtures_controller.rb` (order knockout stage tabs by match number)
- Test: `test/controllers/fixtures_controller_test.rb`

**Interfaces:**
- Consumes: `Fixture#teams_known?`, `home_slot_label`/`away_slot_label`, `home_display`/`away_display` (Task 3).

- [ ] **Step 1: Write the failing test** (append to `FixturesControllerTest`)

```ruby
# test/controllers/fixtures_controller_test.rb — add this test
  test "knockout fixture with unknown teams renders as a non-predictable TBD card" do
    sign_in_as users(:one)
    ko = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                         stage: :r32, home_slot_label: "Winner Group A",
                         away_slot_label: "Runner-up Group B", match_number: 73)
    get predictions_path(stage: "r32")
    assert_response :success
    assert_includes response.body, "Winner Group A"
    assert_includes response.body, "Runner-up Group B"
    assert_select "form[action=?]", fixture_prediction_path(ko), count: 0
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/fixtures_controller_test.rb`
Expected: FAIL — currently the card would attempt `fixture.home_team.flag_emoji` on nil and error (500), so the response is not success / labels absent.

- [ ] **Step 3: Add the TBD branch to the card**

In `app/views/fixtures/_fixture_card.html.erb`, insert a new branch immediately AFTER the `<% if fixture.finished? %>` block closes and BEFORE `<% elsif fixture.locked? %>` (i.e. between line 76 `<% end %>`/line 77). Change line 77 from `<% elsif fixture.locked? %>` to start with the TBD branch:

```erb
    <% elsif !fixture.teams_known? %>
      <%# --- Teams not announced yet: descriptive slot labels, no form --- %>
      <div class="flex items-center justify-between gap-3">
        <div class="flex min-w-0 flex-1 flex-col items-center gap-1.5 text-center">
          <span class="text-3xl leading-none" aria-hidden="true">🏳️</span>
          <span class="truncate w-full text-sm font-semibold text-charcoal/60"><%= fixture.home_slot_label || "TBD" %></span>
        </div>
        <div class="shrink-0 px-1 text-xs font-semibold uppercase tracking-wide text-charcoal/40">vs</div>
        <div class="flex min-w-0 flex-1 flex-col items-center gap-1.5 text-center">
          <span class="text-3xl leading-none" aria-hidden="true">🏳️</span>
          <span class="truncate w-full text-sm font-semibold text-charcoal/60"><%= fixture.away_slot_label || "TBD" %></span>
        </div>
      </div>
      <div class="mt-auto flex flex-col items-center gap-1.5">
        <p class="flex items-center gap-1 text-xs text-charcoal/50">
          <svg class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path fill-rule="evenodd" d="M10 1a4.5 4.5 0 0 0-4.5 4.5V9H5a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2h-.5V5.5A4.5 4.5 0 0 0 10 1Zm3 8V5.5a3 3 0 1 0-6 0V9h6Z" clip-rule="evenodd" />
          </svg>
          Teams to be announced
        </p>
      </div>

    <% elsif fixture.locked? %>
```

(The `finished?` and `locked?`/open branches are unchanged; a TBD match is never `finished?`, and the new branch precedes `locked?` so a kickoff-passed match with no teams still shows TBD instead of dereferencing nil.)

- [ ] **Step 4: Order knockout stage tabs by match number**

In `app/controllers/fixtures_controller.rb`, change the non-upcoming branch ordering (line ~16) so knockout rounds list in bracket order:

```ruby
      @fixtures = fixtures.by_stage(@stage).order(:match_number, :kickoff_at).to_a
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bin/rails test test/controllers/fixtures_controller_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/fixtures/_fixture_card.html.erb app/controllers/fixtures_controller.rb test/controllers/fixtures_controller_test.rb
git commit -m "feat: render knockout TBD cards and order rounds by match number"
```

---

### Task 11: Full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the entire test suite**

Run: `bin/rails test`
Expected: all green, 0 failures, 0 errors.

- [ ] **Step 2: Run the system test (browser flow)**

Run: `bin/rails test:system`
Expected: PASS (predict + score flow unaffected). If the environment has no browser driver, note it and skip.

- [ ] **Step 3: Manual smoke (optional, if running the app)**

```bash
bin/rails db:reset
```
Then sign in as admin (`admin@pitchpredict.app` / `worldcup2026` in demo), visit `/admin/knockout_fixtures`, set teams on one R32 match, and confirm it appears predictable at `/predictions?stage=r32` while the others still show "Teams to be announced".

- [ ] **Step 4: Final commit (if any fixups were needed)**

```bash
git add -A
git commit -m "test: verify knockout TBD bracket end-to-end"
```

---

## Self-Review

**Spec coverage:**
- KnockoutBracket source of truth → Task 1. ✓
- Nullable teams + slot/label/match_number columns → Task 2. ✓
- Fixture validations/predicates/display helpers → Task 3. ✓
- Prediction blocks TBD matches → Task 4. ✓
- Seeds create TBD knockouts + labels + numbers → Task 5. ✓
- Data migration for existing DBs (via idempotent KnockoutReset) → Tasks 6 & 7. ✓
- Admin knockout controller + route + shared base → Task 8. ✓
- Admin knockout view + nil-safe admin fixtures views → Task 9. ✓
- Player TBD card + knockout ordering → Task 10. ✓
- Whole-suite verification → Task 11. ✓

**Placeholder scan:** No "TBD/TODO" steps (the user-facing "TBD" text is a real UI string). Every code step shows full code.

**Type consistency:** `teams_known?`, `open_for_predictions?`, `home_display`/`away_display`, `home_flag`/`away_flag`, `KnockoutBracket.specs`/`.for`, `KnockoutReset.call`, `admin_knockout_fixtures_path`/`admin_knockout_fixture_path` are used identically across the tasks that define and consume them.
