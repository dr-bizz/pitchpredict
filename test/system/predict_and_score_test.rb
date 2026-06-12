require "application_system_test_case"

class PredictAndScoreTest < ApplicationSystemTestCase
  test "player predicts a match, the result is scored and the leaderboard shows the points" do
    user = users(:two) # has no prediction on the upcoming fixture
    fixture = fixtures(:upcoming_group) # Spain v Canada, kicks off in 7 days

    sign_in_through_ui(user)

    # --- Predict 3-1 from the grid (stepper + direct input) -----------------
    visit predictions_path

    within "#prediction_fixture_#{fixture.id}" do
      fill_in "Spain goals", with: "2"
      click_on "Increase Spain goals" # stepper bumps 2 -> 3
      assert_field "Spain goals", with: "3"
      fill_in "Canada goals", with: "1"
      click_on "Save prediction"

      assert_text "Predicted"
      assert_text "Saved ✓"
      assert_button "Update prediction"
    end

    prediction = user.predictions.find_by!(fixture: fixture)
    assert_equal [ 3, 1 ], [ prediction.home_score, prediction.away_score ]

    # --- Result comes in: 3-1, an exact hit ---------------------------------
    # NOTE: scoring is driven via the model + job rather than a second admin
    # browser session; the admin UI flow itself is covered by
    # test/controllers/admin/fixtures_controller_test.rb. The job is the exact
    # code path Admin::FixturesController#update enqueues.
    fixture.update!(kickoff_at: 1.hour.ago, status: :finished, home_score: 3, away_score: 1)
    ScoreFixtureJob.perform_now(fixture.id)

    # --- The leaderboard reflects the points through the UI -----------------
    visit leaderboard_path

    within "tr[data-current-user='true']" do
      assert_text user.name
      # 5 pts from the seeded finished fixture + 4 pts for the exact hit.
      assert_text "9 pts"
    end
  end
end
