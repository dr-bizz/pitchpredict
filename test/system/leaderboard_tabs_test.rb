require "application_system_test_case"

class LeaderboardTabsTest < ApplicationSystemTestCase
  # NOTE: local system/browser tests are known-broken in this project (see
  # docs/superpowers/specs/2026-06-26-reactive-ui-morphing-design.md). These run
  # in CI; `bin/rails test` is the local verification gate.

  test "switching to From R16 shows the R16 board and records the choice in the URL hash" do
    sign_in_through_ui(users(:two))
    visit leaderboard_path

    # Overall is the default board; the R16 board is hidden.
    assert_selector "#leaderboard-table"
    assert_no_selector "#leaderboard-table-r16"

    click_on "From R16"

    assert_selector "#leaderboard-table-r16"
    assert_no_selector "#leaderboard-table"
    assert_equal "#r16", page.evaluate_script("window.location.hash")
  end

  test "the From R16 tab is restored from the URL hash on load" do
    sign_in_through_ui(users(:two))
    # Landing with #r16 is the state a live-update morph leaves behind; the
    # controller re-selects the R16 board from the hash on connect/render.
    visit "#{leaderboard_path}#r16"

    assert_selector "#leaderboard-table-r16"
    assert_no_selector "#leaderboard-table"
  end
end
