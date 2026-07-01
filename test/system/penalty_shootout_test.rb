require "application_system_test_case"

class PenaltyShootoutTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

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

  test "an admin records the shootout winner inline for a level knockout" do
    admin = User.create!(name: "Admin", email_address: "admin-pens@example.com",
                         password: "password", role: :admin)
    ko = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 1.hour.ago, stage: :sf,
                         match_number: 101, home_team: teams(:spain), away_team: teams(:canada))

    sign_in_through_ui(admin)
    visit admin_fixtures_path

    # NOTE: seeded fixture upcoming_group is also Spain v Canada, so a plain
    # `within "tr", text: "Spain"` would match two rows (Capybara::Ambiguous).
    # Scope to this fixture's own row by dom id instead.
    within "##{dom_id(ko)}" do
      fill_in "Spain goals", with: "2"
      fill_in "Canada goals", with: "2" # level -> picker reveals
      assert_selector "[data-penalty-target='picker']:not(.hidden)"
      # The inline picker's visible text is the team code (e.g. "ESP"); it is
      # aria-labelled with the full team name so `choose "Spain"` resolves via
      # Capybara.enable_aria_label. The radio is visually hidden (sr-only), so
      # allow_label_click is required to click its wrapping label.
      choose "Spain", allow_label_click: true
      click_on "Save"
    end

    assert_text "Result saved"
    assert_equal "home", ko.reload.penalty_winner # Spain is the home team
  end
end
