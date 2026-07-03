# Data repair for issue #14: fixtures finished while scoring was crashing on
# legacy predictions were never scored. Rescoring is idempotent, so sweeping
# every finished fixture is safe. Runs at deploy time because the Render free
# tier has no console for a manual task.
class RescoreFinishedFixtures < ActiveRecord::Migration[8.1]
  def up
    say_with_time "Rescoring all finished fixtures" do
      Fixture.finished.find_each { |fixture| ScoringService.score_fixture!(fixture) }
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
