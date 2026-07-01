require "application_system_test_case"

class PenaltyShootoutTest < ApplicationSystemTestCase
  test "the advancer picker reveals on a knockout draw and hides otherwise" do
    user = users(:two)
    ko = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 7.days.from_now, stage: :r16,
                         match_number: 89, home_team: teams(:spain), away_team: teams(:canada))

    sign_in_through_ui(user)
    visit predictions_path

    within "#prediction_fixture_#{ko.id}" do
      fill_in "Spain goals", with: "1"
      fill_in "Canada goals", with: "0"
      assert_no_selector "[data-penalty-target='picker']:not(.hidden)"

      fill_in "Canada goals", with: "1" # now level -> picker reveals
      assert_selector "[data-penalty-target='picker']:not(.hidden)"
      choose "Canada", allow_label_click: true
      click_on "Save prediction"
      assert_text "Saved ✓"
    end

    prediction = user.predictions.find_by!(fixture: ko)
    assert_equal [ 1, 1 ], [ prediction.home_score, prediction.away_score ]
    assert_equal "away", prediction.penalty_winner # Canada is the away team
  end
end
