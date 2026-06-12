class ChampionPick < ApplicationRecord
  belongs_to :user
  belongs_to :team

  validates :user_id, uniqueness: { message: "already has a champion pick" }
  # NOTE: lock rule — champion picks freeze once the tournament starts, i.e. once
  # the earliest fixture's kickoff_at has passed. Creating a pick or changing the
  # chosen team after that point is rejected; other updates are unaffected.
  validate :tournament_must_not_have_started, if: :team_choice_changed?

  def self.tournament_started?
    first_kickoff = Fixture.minimum(:kickoff_at)
    first_kickoff.present? && first_kickoff <= Time.current
  end

  private

  def team_choice_changed?
    new_record? || will_save_change_to_team_id?
  end

  def tournament_must_not_have_started
    errors.add(:base, "Champion picks are locked once the tournament has started") if self.class.tournament_started?
  end
end
