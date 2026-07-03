require "test_helper"
require Rails.root.join("db/migrate/20260703032525_rescore_finished_fixtures.rb")

# The rescore sweep runs at deploy time on production Postgres while the old
# release is still serving traffic. Its "data repair must never block a deploy"
# guarantee only holds if the migration opts out of the adapter's wrapping
# transaction (a DB-level error inside it would poison the transaction and make
# the migrator's own schema_migrations insert fail) and survives one fixture
# failing without abandoning the rest.
class RescoreFinishedFixturesTest < ActiveSupport::TestCase
  setup do
    @previous_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
  end

  teardown do
    ActiveRecord::Migration.verbose = @previous_verbose
  end

  test "runs outside the migration's wrapping DDL transaction" do
    assert RescoreFinishedFixtures.disable_ddl_transaction,
      "data-only migration must disable_ddl_transaction! so a mid-rescore DB error " \
      "cannot poison the transaction that records the migration as run"
  end

  test "one fixture failing to score does not raise or stop the other fixtures" do
    bad = fixtures(:finished_group)
    good = Fixture.create!(
      home_team: teams(:spain), away_team: teams(:canada), stadium: stadia(:metlife),
      kickoff_at: 1.day.ago, stage: :group, status: :finished, home_score: 2, away_score: 0
    )
    prediction = Prediction.new(user: users(:one), fixture: good, home_score: 2, away_score: 0)
    prediction.save!(validate: false) # bypass kickoff lock to seed a post-kickoff prediction

    with_failing_scoring_for(bad) do
      assert_nothing_raised { RescoreFinishedFixtures.new.up }
    end

    assert_equal 4, prediction.reload.points_awarded
  end

  private

  # Minimal hand-rolled stub (no minitest/mock in minitest 6): scoring the
  # given fixture raises a DB-level error; every other fixture scores normally.
  def with_failing_scoring_for(bad_fixture)
    original = ScoringService.method(:score_fixture!)
    ScoringService.define_singleton_method(:score_fixture!) do |fixture|
      raise ActiveRecord::StatementInvalid, "simulated DB error" if fixture == bad_fixture

      original.call(fixture)
    end
    yield
  ensure
    ScoringService.define_singleton_method(:score_fixture!, original)
  end
end
