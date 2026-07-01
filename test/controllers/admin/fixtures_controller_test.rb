require "test_helper"

module Admin
  class FixturesControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper
    include ActionView::RecordIdentifier

    setup do
      # NOTE: built here instead of editing the shared users.yml fixture file,
      # since other (parallel) stages also rely on those fixtures.
      @admin = User.create!(name: "Admin", email_address: "admin-test@example.com",
                            password: "password", role: :admin)
      @player = users(:one)
      @fixture = fixtures(:upcoming_group)
    end

    test "redirects guests to sign in" do
      get admin_fixtures_path
      assert_redirected_to new_session_path
    end

    test "redirects non-admin users to root with an alert" do
      sign_in_as @player
      get admin_fixtures_path
      assert_redirected_to root_path
      assert_equal "You don't have access to the admin area.", flash[:alert]
    end

    test "index lists fixtures for admins" do
      sign_in_as @admin
      get admin_fixtures_path
      assert_response :success
      assert_select "h1", text: "Admin panel"
      assert_select "td", text: /Spain/
    end

    test "index filters by status" do
      sign_in_as @admin
      get admin_fixtures_path(status: "finished")
      assert_response :success
      assert_select "td", text: /Brazil/
      assert_select "td", text: /Spain/, count: 0
    end

    test "index ignores invalid filter params" do
      sign_in_as @admin
      get admin_fixtures_path(stage: "bogus", status: "nope")
      assert_response :success
      assert_select "td", text: /Spain/
    end

    test "index shows inline score inputs for a scoreable fixture, with no Enter result button" do
      sign_in_as @admin
      get admin_fixtures_path
      assert_response :success
      assert_select "tr##{dom_id(@fixture)} input[name='fixture[home_score]']"
      assert_select "tr##{dom_id(@fixture)} input[name='fixture[away_score]']"
      assert_select "tr##{dom_id(@fixture)} form[action=?]", admin_fixture_path(@fixture)
      assert_select "a", text: "Enter result", count: 0
    end

    test "edit renders the full-page result form fallback" do
      sign_in_as @admin
      get edit_admin_fixture_path(@fixture)
      assert_response :success
      assert_select "form[action=?]", admin_fixture_path(@fixture)
      assert_select "input[name='fixture[home_score]']"
    end

    test "update as turbo_stream swaps the row to the result and enqueues scoring" do
      sign_in_as @admin

      assert_enqueued_with job: ScoreFixtureJob, args: [ @fixture.id ] do
        patch admin_fixture_path(@fixture), params: { fixture: { home_score: 3, away_score: 1 } }, as: :turbo_stream
      end

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_select "turbo-stream[action=replace][target=?]", dom_id(@fixture)
      assert_select "turbo-stream[action=prepend][target=admin-flash]"
      assert @fixture.reload.finished?
    end

    test "update as turbo_stream re-renders the row inputs with an error toast on failure" do
      sign_in_as @admin

      assert_no_enqueued_jobs only: ScoreFixtureJob do
        patch admin_fixture_path(@fixture), params: { fixture: { home_score: "", away_score: 2 } }, as: :turbo_stream
      end

      assert_response :unprocessable_entity
      assert_select "turbo-stream[action=replace][target=?]", dom_id(@fixture)
      assert_select "turbo-stream template input[name='fixture[home_score]']"
      assert_select "turbo-stream[action=prepend][target=admin-flash] .alert-error"
      assert @fixture.reload.scheduled?
    end

    test "update saves the result, finishes the fixture and enqueues scoring" do
      sign_in_as @admin

      assert_enqueued_with job: ScoreFixtureJob, args: [ @fixture.id ] do
        patch admin_fixture_path(@fixture), params: { fixture: { home_score: 3, away_score: 1 } }
      end

      assert_redirected_to admin_fixtures_path
      @fixture.reload
      assert @fixture.finished?
      assert_equal 3, @fixture.home_score
      assert_equal 1, @fixture.away_score
    end

    test "update rejects missing scores and does not enqueue scoring" do
      sign_in_as @admin

      assert_no_enqueued_jobs only: ScoreFixtureJob do
        patch admin_fixture_path(@fixture), params: { fixture: { home_score: "", away_score: 2 } }
      end

      assert_response :unprocessable_entity
      assert @fixture.reload.scheduled?
    end

    test "update rejects negative scores" do
      sign_in_as @admin
      patch admin_fixture_path(@fixture), params: { fixture: { home_score: -1, away_score: 2 } }
      assert_response :unprocessable_entity
      assert_nil @fixture.reload.home_score
    end

    test "non-admin cannot update a result" do
      sign_in_as @player
      patch admin_fixture_path(@fixture), params: { fixture: { home_score: 3, away_score: 1 } }
      assert_redirected_to root_path
      assert @fixture.reload.scheduled?
    end

    test "cannot enter a result for a TBD knockout fixture" do
      sign_in_as @admin
      tbd = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 25.days.from_now, stage: :r32,
                            home_slot_label: "Winner Group A", away_slot_label: "Runner-up Group B",
                            match_number: 73)

      assert_no_enqueued_jobs only: ScoreFixtureJob do
        patch admin_fixture_path(tbd), params: { fixture: { home_score: 2, away_score: 1 } }
      end

      assert_redirected_to admin_knockout_fixtures_path
      tbd.reload
      assert tbd.scheduled?
      assert_nil tbd.home_score
    end

    test "cannot enter a result for a TBD knockout fixture as turbo_stream" do
      sign_in_as @admin
      tbd = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 25.days.from_now, stage: :r32,
                            home_slot_label: "Winner Group A", away_slot_label: "Runner-up Group B",
                            match_number: 74)

      assert_no_enqueued_jobs only: ScoreFixtureJob do
        patch admin_fixture_path(tbd), params: { fixture: { home_score: 2, away_score: 1 } }, as: :turbo_stream
      end

      assert_response :unprocessable_entity
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_select "turbo-stream[action=replace][target=?]", dom_id(tbd)
      assert_select "turbo-stream template", text: /Set both teams for this match/
      tbd.reload
      assert tbd.scheduled?
      assert_nil tbd.home_score
    end

    test "records the shootout winner for a level knockout result" do
      sign_in_as @admin
      ko = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 1.hour.ago, stage: :sf,
                            match_number: 101, home_team: teams(:spain), away_team: teams(:canada))

      patch admin_fixture_path(ko), params: {
        fixture: { home_score: 1, away_score: 1, penalty_winner: "home" }
      }, as: :turbo_stream

      assert_response :success
      ko.reload
      assert ko.finished?
      assert_equal "home", ko.penalty_winner
    end

    test "rejects a level knockout result with no shootout winner" do
      sign_in_as @admin
      ko = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 1.hour.ago, stage: :sf,
                            match_number: 101, home_team: teams(:spain), away_team: teams(:canada))

      patch admin_fixture_path(ko), params: {
        fixture: { home_score: 1, away_score: 1 }
      }, as: :turbo_stream

      assert_response :unprocessable_entity
      assert_not ko.reload.finished?
    end
  end
end
