# All scoring math for PitchPredict lives here. Models, controllers and views
# must never compute points themselves — they call into this service.
#
# Point scale per prediction:
#   4 — exact scoreline
#   3 — correct goal difference, but not the exact score (includes draws
#       predicted as draws with the wrong score, since 0 == 0)
#   2 — correct outcome (home win / draw / away win) only. For knockout
#       matches the "outcome" is which team advances (the higher score, or
#       the shootout winner on a level score) — a wrong advancer scores 0.
#   0 — everything else
class ScoringService
  EXACT_POINTS = 4
  DIFFERENCE_POINTS = 3
  TENDENCY_POINTS = 2
  CHAMPION_BONUS = 10

  class << self
    def points_for(predicted_home:, predicted_away:, actual_home:, actual_away:,
                   predicted_pen_winner: nil, actual_pen_winner: nil)
      # A knockout that ends level is decided by the shootout winner, so the
      # advancer — not the drawn scoreline — is the outcome that must match.
      # For group matches (pen winner always nil) a level score stays a :draw,
      # so this reproduces the original win/draw/loss scoring exactly.
      return 0 unless outcome(predicted_home, predicted_away, predicted_pen_winner) ==
                      outcome(actual_home, actual_away, actual_pen_winner)
      return EXACT_POINTS if predicted_home == actual_home && predicted_away == actual_away
      return DIFFERENCE_POINTS if predicted_home - predicted_away == actual_home - actual_away

      TENDENCY_POINTS
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
              actual_away: fixture.away_score,
              predicted_pen_winner: prediction.penalty_winner,
              actual_pen_winner: fixture.penalty_winner
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
    # hasn't finished. A final level on scores is decided by its penalty_winner
    # (the shootout winner); if that is also unset we return nil and award no
    # bonus rather than guessing.
    def champion_team_id
      final = Fixture.by_stage(:final).finished.first
      return nil if final.nil?

      case outcome(final.home_score, final.away_score, final.penalty_winner)
      when :home then final.home_team_id
      when :away then final.away_team_id
      end # :draw (a level final with no shootout winner recorded) → nil
    end

    private

    # The team that goes through: the higher score, or — on a level score —
    # the shootout winner (nil pen winner means a genuine group-stage draw).
    def outcome(home, away, pen_winner)
      return :home if home > away
      return :away if away > home

      pen_winner.presence&.to_sym || :draw
    end
  end
end
