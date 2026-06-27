require "application_system_test_case"

class PredictAndScoreTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "player predicts a match, an admin scores it and the leaderboard shows the points" do
    user = users(:two) # has no prediction on the upcoming fixture
    fixture = fixtures(:upcoming_group) # Spain v Canada, kicks off in 7 days
    admin = User.create!(name: "Admin", email_address: "admin-system@example.com",
                         password: "password", role: :admin)

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

    # --- Kickoff passes; the admin enters the 3-1 result through the UI -----
    # NOTE: only the clock is moved via the model — the scoring itself is
    # driven end-to-end through the admin screens below, in a second browser
    # session so the player stays signed in.
    fixture.update!(kickoff_at: 1.hour.ago)

    using_session :admin do
      sign_in_through_ui(admin)

      # Scores are entered inline on the list row — no separate edit page.
      visit admin_fixtures_path
      within "tr", text: "Spain" do
        fill_in "Spain goals", with: "3"
        fill_in "Canada goals", with: "1"
      end

      # The controller enqueues ScoreFixtureJob (test adapter); perform it so
      # the predictions are scored just like the Solid Queue worker would.
      perform_enqueued_jobs do
        within "tr", text: "Spain" do
          click_on "Save"
        end
        # The confirmation toast renders in #admin-flash, above the table.
        assert_text "Result saved: Spain 3–1 Canada"
      end
    end

    assert_equal 4, prediction.reload.points_awarded # exact hit

    # --- The player sees the points on the leaderboard ----------------------
    visit leaderboard_path

    within "tr[data-current-user='true']" do
      assert_text user.name
      assert_selector "[data-you-badge]:not([hidden])", text: "You"
      # 5 pts from the seeded finished fixture + 4 pts for the exact hit.
      assert_text "9 pts"
    end
  end
end
