require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "redirects to sign in when unauthenticated" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "shows greeting, prediction summary and top five" do
    sign_in_as(@user)

    get root_path

    assert_response :success
    assert_select "h1", text: /Hello #{@user.name}/
    assert_select "section", text: /1 of #{Fixture.count}\s+matches predicted/m
    assert_select "a[href=?]", predictions_path, text: /Continue predicting/
    assert_select "a[href=?]", leaderboard_path
    assert_select "h2", text: "Top 5 on the leaderboard"
    assert_select "h2", text: "How it works"
  end

  test "shows locked champion pick state when tournament has started" do
    # NOTE: fixture finished_group kicked off in the past, so the tournament
    # counts as started in the test DB.
    sign_in_as(@user)

    get root_path

    assert_response :success
    assert_match "Picks locked", response.body
    assert_match @user.champion_pick.team.name, response.body
    assert_select "select[name='champion_pick[team_id]']", count: 0
  end

  test "shows team select when tournament has not started" do
    Fixture.update_all(kickoff_at: 3.days.from_now, status: :scheduled, home_score: nil, away_score: nil)
    sign_in_as(@user)

    get root_path

    assert_response :success
    assert_select "form[action=?]", champion_pick_path do
      assert_select "select[name='champion_pick[team_id]']"
    end
    assert_no_match "Picks locked", response.body
  end
end
