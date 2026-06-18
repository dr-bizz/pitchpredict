require "test_helper"

module Admin
  class KnockoutFixturesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(name: "Admin", email_address: "admin-ko@example.com",
                            password: "password", role: :admin)
      @player = users(:one)
      @ko = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 25.days.from_now,
                            stage: :r32, home_slot_label: "Winner Group A",
                            away_slot_label: "Runner-up Group B", match_number: 73)
    end

    test "redirects non-admins" do
      sign_in_as @player
      get admin_knockout_fixtures_path
      assert_redirected_to root_path
    end

    test "index lists knockout fixtures with slot labels" do
      sign_in_as @admin
      get admin_knockout_fixtures_path
      assert_response :success
      assert_includes response.body, "Winner Group A"
    end

    test "assigning both teams makes the match predictable" do
      sign_in_as @admin
      patch admin_knockout_fixture_path(@ko),
            params: { fixture: { home_team_id: teams(:spain).id, away_team_id: teams(:canada).id } }
      assert_redirected_to admin_knockout_fixtures_path
      @ko.reload
      assert @ko.teams_known?
      assert @ko.open_for_predictions?
    end

    test "clearing a team resets the match to TBD" do
      @ko.update!(home_team: teams(:spain), away_team: teams(:canada))
      sign_in_as @admin
      patch admin_knockout_fixture_path(@ko), params: { fixture: { home_team_id: "", away_team_id: "" } }
      assert_redirected_to admin_knockout_fixtures_path
      assert_not @ko.reload.teams_known?
    end

    test "setting only one team is rejected" do
      sign_in_as @admin
      patch admin_knockout_fixture_path(@ko),
            params: { fixture: { home_team_id: teams(:spain).id, away_team_id: "" } }
      assert_redirected_to admin_knockout_fixtures_path
      assert_not @ko.reload.teams_known?
      assert_equal "Both teams must be set together", flash[:alert]
    end
  end
end
