class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :predictions, dependent: :destroy
  has_one :champion_pick, dependent: :destroy

  enum :role, { player: 0, admin: 1 }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
end
