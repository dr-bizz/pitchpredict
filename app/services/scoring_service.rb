# All scoring math for PitchPredict lives here. Models, controllers and views
# must never compute points themselves — they call into this service.
#
# Point scale per prediction:
#   4 — exact scoreline
#   3 — correct goal difference, but not the exact score (includes draws
#       predicted as draws with the wrong score, since 0 == 0)
#   2 — correct outcome (home win / draw / away win) only
#   0 — everything else
class ScoringService
  EXACT_POINTS = 4
  DIFFERENCE_POINTS = 3
  TENDENCY_POINTS = 2
  CHAMPION_BONUS = 10

  class << self
    def points_for(predicted_home:, predicted_away:, actual_home:, actual_away:)
      return EXACT_POINTS if predicted_home == actual_home && predicted_away == actual_away
      return DIFFERENCE_POINTS if predicted_home - predicted_away == actual_home - actual_away
      return TENDENCY_POINTS if (predicted_home <=> predicted_away) == (actual_home <=> actual_away)

      0
    end

    # Recomputes and persists points_awarded for every prediction of the fixture.
    # Idempotent: safe to run again if the result is corrected later.
    def score_fixture!(fixture)
      # NOTE: assumption — scoring an unfinished fixture is a caller bug, so we
      # raise rather than silently no-op (a retried job would mask the problem).
      raise ArgumentError, "Fixture #{fixture.id} is not finished" unless fixture.finished?

      # All-or-nothing: a mid-loop failure must not leave some predictions on
      # new points and others stale (the standings would be silently wrong
      # until an admin re-saves the result).
      fixture.transaction do
        fixture.predictions.find_each do |prediction|
          prediction.update!(
            points_awarded: points_for(
              predicted_home: prediction.home_score,
              predicted_away: prediction.away_score,
              actual_home: fixture.home_score,
              actual_away: fixture.away_score
            )
          )
        end
      end
    end

    # NOTE: champion-bonus representation decision — the bonus is NOT persisted
    # anywhere. LeaderboardService derives it at read time: once the final is
    # finished, every ChampionPick whose team matches champion_team_id earns
    # CHAMPION_BONUS on top of their prediction points. This keeps predictions'
    # points_awarded purely per-fixture and makes result corrections free.
    #
    # Returns the winning team id of the finished final, or nil if the final
    # hasn't finished. NOTE: assumption — a World Cup final cannot end level;
    # admins record the post-extra-time/penalties deciding score. If scores are
    # somehow level we return nil and award no bonus.
    def champion_team_id
      final = Fixture.by_stage(:final).finished.first
      return nil if final.nil? || final.home_score == final.away_score

      final.home_score > final.away_score ? final.home_team_id : final.away_team_id
    end
  end
end
