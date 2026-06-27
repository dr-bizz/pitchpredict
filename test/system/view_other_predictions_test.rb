require "application_system_test_case"

class ViewOtherPredictionsTest < ApplicationSystemTestCase
  test "a player clicks another player's name and sees their locked predictions head-to-head" do
    # users(:two) has a scored prediction on the finished Brazil–France match.
    sign_in_through_ui users(:one)

    visit leaderboard_path
    click_link "User Two"

    assert_text "User Two's predictions"
    assert_text "Brazil"                 # the locked match is shown
    assert_text "France"
    assert_text "+5"                     # the target's pick scored points (their column)
    assert_text "No prediction"          # the viewer's head-to-head column (no pick here)
    # Read-only — none of the editable prediction affordances are present.
    assert_no_button "Save prediction"
    assert_no_button "Update prediction"
  end
end
