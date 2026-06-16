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
    # Hero greets the user by first name with a comma + wave (redesigned hero).
    first_name = @user.name.split.first
    assert_select "h1", text: /Hello, #{first_name}/
    # Prediction summary is the PREDICTED stat tile: "<predicted>/<total>".
    assert_select ".stat-tile", text: /Predicted/
    assert_select ".stat-tile-value", text: "1/#{Fixture.count}"
    assert_select "a[href=?]", predictions_path, text: /Continue predicting/
    assert_select "a[href=?]", leaderboard_path
    assert_select "h2", text: "Top Players"
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

  test "shows champion pick chips when tournament has not started" do
    Fixture.update_all(kickoff_at: 3.days.from_now, status: :scheduled, home_score: nil, away_score: nil)
    sign_in_as(@user)

    get root_path

    assert_response :success
    # Unlocked "Change pick" state renders one button_to PATCH form per team
    # (outlined .chip pills) instead of the old <select>.
    assert_select "p", text: "Change pick"
    assert_select "form[action=?][method=post]", champion_pick_path do
      assert_select "input[name=_method][value=patch]"
      assert_select "input[name='champion_pick[team_id]']"
      assert_select "button.chip"
    end
    assert_no_match "Picks locked", response.body
  end
end
