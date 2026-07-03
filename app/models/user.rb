class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :predictions, dependent: :destroy
  has_one :champion_pick, dependent: :destroy

  enum :role, { player: 0, admin: 1 }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true

  # Every user appears on the leaderboard (even with zero predictions), and the
  # activity feed shows names too, so new signups and renames must drop both
  # cached entries from Solid Cache.
  after_commit do
    LeaderboardService.expire_rows
    ActivityFeedService.expire_items
  end
end
