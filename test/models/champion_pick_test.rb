require "test_helper"

class ChampionPickTest < ActiveSupport::TestCase
  # NOTE: the fixtures include a finished match, so the tournament counts as
  # started in the test database unless those fixtures are removed or re-dated.
  test "tournament_started? reflects the earliest kickoff" do
    assert ChampionPick.tournament_started?

    Prediction.delete_all
    Fixture.delete_all
    assert_not ChampionPick.tournament_started?
  end

  test "cannot create a pick or change the team once the tournament has started" do
    pick = ChampionPick.new(user: users(:one), team: teams(:france))
    assert_not pick.valid?
    assert pick.errors[:base].any?

    existing = champion_picks(:one)
    existing.team = teams(:france)
    assert_not existing.valid?
  end

  test "picks are open before the first kickoff" do
    fixtures(:finished_group).update_columns(kickoff_at: 1.day.from_now)
    champion_picks(:two).destroy!

    pick = ChampionPick.new(user: users(:two), team: teams(:france))
    assert pick.valid?
  end

  test "one pick per user" do
    duplicate = ChampionPick.new(user: users(:one), team: teams(:spain))
    duplicate.valid?
    assert duplicate.errors[:user_id].any?
  end
end
