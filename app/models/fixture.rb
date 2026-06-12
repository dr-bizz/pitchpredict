class Fixture < ApplicationRecord
  belongs_to :home_team, class_name: "Team", inverse_of: :home_fixtures
  belongs_to :away_team, class_name: "Team", inverse_of: :away_fixtures
  belongs_to :stadium
  has_many :predictions, dependent: :destroy

  # NOTE: scopes: false because the :group value would otherwise generate a
  # Fixture.group scope that collides with ActiveRecord::Relation#group.
  # Use by_stage(:group) instead; instance predicates (group?, final?, ...) still work.
  enum :stage, { group: 0, r32: 1, r16: 2, qf: 3, sf: 4, third_place: 5, final: 6 }, scopes: false
  enum :status, { scheduled: 0, live: 1, finished: 2 }

  validates :kickoff_at, presence: true
  validates :home_score, :away_score,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  # NOTE: assumption — a finished fixture must have both scores recorded.
  validates :home_score, :away_score, presence: true, if: :finished?
  validate :teams_must_differ

  scope :upcoming, -> { where(kickoff_at: Time.current..).order(:kickoff_at) }
  scope :past, -> { where(kickoff_at: ...Time.current).order(kickoff_at: :desc) }
  scope :by_stage, ->(stage) { where(stage: stage) }

  # Predictions lock at kickoff — or earlier, the moment a result exists.
  # NOTE: admins may enter a result before kickoff (abandoned/rescheduled
  # matches, data-entry ahead of time); once the outcome is known (or the match
  # is live) predicting must close, otherwise players could "predict" the known
  # score for full points. Hence the status check on top of the time check.
  def locked?
    kickoff_at <= Time.current || !scheduled?
  end

  private

  def teams_must_differ
    return if home_team_id.blank? || home_team_id != away_team_id

    errors.add(:away_team, "can't be the same as the home team")
  end
end
