class ChampionPick < ApplicationRecord
  belongs_to :user
  belongs_to :team

  validates :user_id, uniqueness: { message: "already has a champion pick" }
  # NOTE: lock rule — champion picks freeze at a fixed deadline (see PICK_DEADLINE
  # below) rather than at the tournament's opening kickoff, giving everyone a
  # window to get their pick in. Creating a pick or changing the chosen team after
  # that point is rejected; other updates are unaffected.
  validate :picks_must_not_be_locked, if: :team_choice_changed?

  # Sat June 20 2026, 6:00 PM US Eastern (EDT, UTC-4) == 22:00 UTC.
  PICK_DEADLINE = Time.utc(2026, 6, 20, 22, 0, 0).freeze

  def self.picks_locked?
    Time.current >= PICK_DEADLINE
  end

  private

  def team_choice_changed?
    new_record? || will_save_change_to_team_id?
  end

  def picks_must_not_be_locked
    errors.add(:base, "Champion picks are locked after the deadline") if self.class.picks_locked?
  end
end
