require "test_helper"

class ScoreFixtureJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  test "scores the fixture's predictions and broadcasts a refresh to results" do
    fixture = fixtures(:finished_group)

    assert_broadcasts("results", 1) do
      ScoreFixtureJob.perform_now(fixture.id)
    end

    assert_equal 4, predictions(:two_finished).reload.points_awarded # predicted 2-1, result 2-1
  end

  test "broadcast is a refresh (no viewer-specific HTML payload)" do
    ScoreFixtureJob.perform_now(fixtures(:finished_group).id)

    message = broadcasts("results").last
    html = JSON.parse(message) # Turbo broadcasts the <turbo-stream> element as a string

    assert_includes html, 'action="refresh"'
  end

  test "is discarded when the fixture no longer exists" do
    assert_nothing_raised do
      ScoreFixtureJob.perform_now(-1)
    end
  end
end
