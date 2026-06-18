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

  test "shows locked champion pick state once the pick deadline has passed" do
    # Champion picks lock at a fixed deadline (ChampionPick::PICK_DEADLINE), not
    # at first kickoff, so travel past it to exercise the locked state regardless
    # of the wall-clock date the suite runs on.
    sign_in_as(@user)

    travel_to ChampionPick::PICK_DEADLINE + 1.hour do
      get root_path

      assert_response :success
      assert_match "Picks locked", response.body
      assert_match @user.champion_pick.team.name, response.body
      assert_select "select[name='champion_pick[team_id]']", count: 0
    end
  end

  test "shows champion pick chips before the pick deadline" do
    sign_in_as(@user)

    travel_to ChampionPick::PICK_DEADLINE - 1.day do
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
end
