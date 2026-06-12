class Team < ApplicationRecord
  # NOTE: 2026 format has 12 groups, A through L.
  GROUPS = ("A".."L").to_a.freeze

  has_many :home_fixtures, class_name: "Fixture", foreign_key: :home_team_id,
           inverse_of: :home_team, dependent: :restrict_with_error
  has_many :away_fixtures, class_name: "Fixture", foreign_key: :away_team_id,
           inverse_of: :away_team, dependent: :restrict_with_error
  has_many :champion_picks, dependent: :restrict_with_error

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true,
            format: { with: /\A[A-Z]{3}\z/, message: "must be exactly 3 uppercase letters" }
  validates :group_name, presence: true, inclusion: { in: GROUPS }
end
