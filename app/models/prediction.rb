class Prediction < ApplicationRecord
  belongs_to :user
  belongs_to :fixture
  enum :penalty_winner, { home: 0, away: 1 }, prefix: true, scopes: false

  validates :home_score, :away_score,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validates :fixture_id, uniqueness: { scope: :user_id, message: "has already been predicted" }
  # NOTE: the lock check only runs when the predicted scores change, so the
  # scoring service can still write points_awarded after kickoff via a normal save.
  validate :fixture_must_be_open, if: :scores_changed?

  scope :scored, -> { where.not(points_awarded: nil) }
  scope :for_stage, ->(stage) { joins(:fixture).where(fixtures: { stage: stage }) }

  # Any prediction change (new pick, edit, points awarded) alters the cached
  # leaderboard rows, so drop them from Solid Cache.
  after_commit { LeaderboardService.expire_rows }

  private

  def scores_changed?
    new_record? || will_save_change_to_home_score? || will_save_change_to_away_score?
  end

  def fixture_must_be_open
    return unless fixture

    if !fixture.teams_known?
      errors.add(:base, "Teams for this match haven't been announced yet")
    elsif fixture.locked?
      errors.add(:base, "Predictions are locked for this match")
    end
  end
end
