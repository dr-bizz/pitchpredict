require "test_helper"

class ChampionPicksControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "create requires authentication" do
    post champion_pick_path, params: { champion_pick: { team_id: teams(:france).id } }

    assert_redirected_to new_session_path
  end

  test "creates a pick before the tournament starts" do
    unlock_tournament
    @user.champion_pick.destroy!
    sign_in_as(@user)

    assert_difference -> { ChampionPick.count }, 1 do
      post champion_pick_path, params: { champion_pick: { team_id: teams(:france).id } }
    end
    assert_redirected_to root_path
    assert_match(/Champion pick saved/, flash[:notice])
    assert_equal teams(:france), @user.reload.champion_pick.team
  end

  test "create upserts when a pick already exists" do
    unlock_tournament
    sign_in_as(@user)

    assert_no_difference -> { ChampionPick.count } do
      post champion_pick_path, params: { champion_pick: { team_id: teams(:brazil).id } }
    end
    assert_redirected_to root_path
    assert_equal teams(:brazil), @user.reload.champion_pick.team
  end

  test "updates the picked team before the tournament starts" do
    unlock_tournament
    sign_in_as(@user)

    patch champion_pick_path, params: { champion_pick: { team_id: teams(:canada).id } }

    assert_redirected_to root_path
    assert_equal teams(:canada), @user.reload.champion_pick.team
  end

  test "rejects a team change once picks are locked" do
    travel_to ChampionPick::PICK_DEADLINE + 1.hour
    original_team = @user.champion_pick.team
    sign_in_as(@user)

    patch champion_pick_path, params: { champion_pick: { team_id: teams(:france).id } }

    assert_redirected_to root_path
    assert_match(/locked/, flash[:alert])
    assert_equal original_team, @user.reload.champion_pick.team
  end

  test "rejects a blank team" do
    unlock_tournament
    sign_in_as(@user)

    patch champion_pick_path, params: { champion_pick: { team_id: "" } }

    assert_redirected_to root_path
    assert_match(/Team/, flash[:alert])
  end

  private

  # Travel to before the champion-pick deadline so picks are still open
  # (same pattern as test/models/champion_pick_test.rb).
  def unlock_tournament
    travel_to ChampionPick::PICK_DEADLINE - 1.day
  end
end
