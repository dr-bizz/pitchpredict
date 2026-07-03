# Data repair for issue #14: fixtures finished while scoring was crashing on
# legacy predictions were never scored. Rescoring is idempotent, so sweeping
# every finished fixture is safe. Runs at deploy time because the Render free
# tier has no console for a manual task.
class RescoreFinishedFixtures < ActiveRecord::Migration[8.1]
  # Data-only migration, so opt out of the wrapping migration transaction.
  # Without this, on production Postgres a DB-level error mid-rescore (e.g. a
  # deadlock with a concurrent ScoreFixtureJob while the old release is still
  # live) would poison that transaction: the rescue below catches the Ruby
  # exception, but the migrator's own schema_migrations insert then fails with
  # PG::InFailedSqlTransaction and blocks the deploy anyway. Atomicity is not
  # lost — score_fixture! wraps each fixture's predictions in its own
  # transaction.
  disable_ddl_transaction!

  def up
    say_with_time "Rescoring all finished fixtures" do
      Fixture.finished.find_each do |fixture|
        ScoringService.score_fixture!(fixture)
      rescue StandardError => e
        # One unscorable fixture must not abandon the sweep for the rest —
        # an admin can re-save that result to rescore it.
        say "Fixture #{fixture.id} skipped: #{e.class}: #{e.message}", true
      end
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
