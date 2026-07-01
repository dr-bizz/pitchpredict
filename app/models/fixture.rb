class Fixture < ApplicationRecord
  belongs_to :home_team, class_name: "Team", inverse_of: :home_fixtures, optional: true
  belongs_to :away_team, class_name: "Team", inverse_of: :away_fixtures, optional: true
  belongs_to :stadium
  has_many :predictions, dependent: :destroy

  # NOTE: scopes: false because the :group value would otherwise generate a
  # Fixture.group scope that collides with ActiveRecord::Relation#group.
  # Use by_stage(:group) instead; instance predicates (group?, final?, ...) still work.
  enum :stage, { group: 0, r32: 1, r16: 2, qf: 3, sf: 4, third_place: 5, final: 6 }, scopes: false
  enum :status, { scheduled: 0, live: 1, finished: 2 }
  enum :penalty_winner, { home: 0, away: 1 }, prefix: true, scopes: false

  validates :kickoff_at, presence: true
  validates :home_score, :away_score,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  # NOTE: assumption — a finished fixture must have both scores recorded.
  validates :home_score, :away_score, presence: true, if: :finished?
  validate :teams_must_differ
  validate :group_fixtures_have_teams
  validate :teams_present_together
  validate :finished_requires_teams
  validate :penalty_winner_consistency

  scope :upcoming, -> { where(kickoff_at: Time.current..).order(:kickoff_at) }
  scope :past, -> { where(kickoff_at: ...Time.current).order(kickoff_at: :desc) }
  scope :by_stage, ->(stage) { where(stage: stage) }
  # Query-side counterpart to #teams_known?: both qualifiers entered, so a match
  # with a still-TBD slot is excluded (nothing to predict / count yet).
  scope :teams_set, -> { where.not(home_team_id: nil).where.not(away_team_id: nil) }
  # Query-level twin of #locked? — the matches no longer open to prediction.
  # NOTE: status <> scheduled(0) captures live/finished-before-kickoff, so this
  # is intentionally broader than the temporal `past` scope.
  scope :locked, -> { where("kickoff_at <= ? OR status <> ?", Time.current, statuses[:scheduled]) }

  # Predictions lock at kickoff — or earlier, the moment a result exists.
  # NOTE: admins may enter a result before kickoff (abandoned/rescheduled
  # matches, data-entry ahead of time); once the outcome is known (or the match
  # is live) predicting must close, otherwise players could "predict" the known
  # score for full points. Hence the status check on top of the time check.
  def locked?
    kickoff_at <= Time.current || !scheduled?
  end

  # Both qualifiers have been entered (always true for group fixtures).
  def teams_known?
    home_team_id.present? && away_team_id.present?
  end

  # Any non-group match — the stages that can go to a penalty shootout.
  def knockout? = !group?

  def open_for_predictions?
    teams_known? && !locked?
  end

  def home_display = home_team&.name || home_slot_label || "TBD"
  def away_display = away_team&.name || away_slot_label || "TBD"
  def home_flag = home_team&.flag_emoji || "🏳️"
  def away_flag = away_team&.flag_emoji || "🏳️"

  # The team that won the shootout, or nil when the match wasn't decided on pens.
  def penalty_winner_team
    return nil if penalty_winner.blank?

    penalty_winner_home? ? home_team : away_team
  end

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

  # A match can't be marked finished (a result entered) until both qualifiers are
  # known — otherwise a finished knockout fixture could hold nil teams, which the
  # views and scoring assume never happens.
  def finished_requires_teams
    return unless finished?

    errors.add(:base, "Cannot finish a match before both teams are known") unless teams_known?
  end

  # penalty_winner is only meaningful for a knockout decided on a level score:
  # forbidden on group matches and decisive results, required once a knockout is
  # finished level (a knockout can't end level without someone going through).
  def penalty_winner_consistency
    level = home_score.present? && away_score.present? && home_score == away_score

    if penalty_winner.present?
      errors.add(:penalty_winner, "only applies to knockout matches") unless knockout?
      errors.add(:penalty_winner, "only applies when the score is level") unless level
    elsif finished? && knockout? && teams_known? && level
      errors.add(:base, "Enter who won the penalty shootout")
    end
  end
end
