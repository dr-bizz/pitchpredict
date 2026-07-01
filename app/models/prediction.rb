class Prediction < ApplicationRecord
  belongs_to :user
  belongs_to :fixture
  enum :penalty_winner, { home: 0, away: 1 }, prefix: true, scopes: false

  before_validation :normalize_penalty_winner
  validates :penalty_winner, presence: true, if: :knockout_draw_predicted?

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

  # The team the player picked to go through on penalties, or nil.
  def penalty_winner_team
    return nil if penalty_winner.blank?

    penalty_winner_home? ? fixture.home_team : fixture.away_team
  end

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

  # A shootout only happens on a knockout draw, so a winner is meaningless
  # anywhere else — strip it rather than reject, keeping non-draw saves clean.
  def normalize_penalty_winner
    self.penalty_winner = nil unless knockout_draw_predicted?
  end

  def knockout_draw_predicted?
    fixture&.knockout? && home_score.present? && away_score.present? &&
      home_score == away_score
  end
end
