class Stadium < ApplicationRecord
  has_many :fixtures, dependent: :restrict_with_error

  validates :name, :city, :country, presence: true
end
