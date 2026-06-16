require "test_helper"

module Admin
  class FixturesControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

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

    test "edit renders the result form" do
      sign_in_as @admin
      get edit_admin_fixture_path(@fixture)
      assert_response :success
      assert_select "form[action=?]", admin_fixture_path(@fixture)
      assert_select "input[name='fixture[home_score]']"
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
  end
end
