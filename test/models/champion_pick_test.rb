require "test_helper"

class ChampionPickTest < ActiveSupport::TestCase
  test "picks_locked? flips at the deadline" do
    travel_to ChampionPick::PICK_DEADLINE - 1.second
    assert_not ChampionPick.picks_locked?

    travel_to ChampionPick::PICK_DEADLINE
    assert ChampionPick.picks_locked?
  end

  test "cannot create a pick or change the team once picks are locked" do
    travel_to ChampionPick::PICK_DEADLINE + 1.hour
    pick = ChampionPick.new(user: users(:one), team: teams(:france))
    assert_not pick.valid?
    assert pick.errors[:base].any?

    existing = champion_picks(:one)
    existing.team = teams(:france)
    assert_not existing.valid?
  end

  test "picks are open before the deadline" do
    travel_to ChampionPick::PICK_DEADLINE - 1.day
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
