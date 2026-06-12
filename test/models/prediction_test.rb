require "test_helper"

class PredictionTest < ActiveSupport::TestCase
  test "valid for an open fixture with scores in 0..20" do
    prediction = Prediction.new(user: users(:two), fixture: fixtures(:upcoming_group),
                                home_score: 3, away_score: 0)
    assert prediction.valid?
  end

  test "rejects scores outside 0..20" do
    prediction = predictions(:one_upcoming)
    prediction.home_score = 21
    assert_not prediction.valid?
    prediction.home_score = -1
    assert_not prediction.valid?
  end

  test "one prediction per user per fixture" do
    duplicate = Prediction.new(user: users(:one), fixture: fixtures(:upcoming_group),
                               home_score: 1, away_score: 1)
    assert_not duplicate.valid?
  end

  test "cannot create or change scores once the fixture is locked" do
    locked = Prediction.new(user: users(:one), fixture: fixtures(:finished_group),
                            home_score: 1, away_score: 0)
    assert_not locked.valid?

    existing = predictions(:two_finished)
    existing.home_score += 1
    assert_not existing.valid?
  end

  test "points_awarded can be saved after kickoff when scores are untouched" do
    existing = predictions(:two_finished)
    existing.points_awarded = 3
    assert existing.save
  end

  test "scored and for_stage scopes" do
    assert_includes Prediction.scored, predictions(:two_finished)
    assert_not_includes Prediction.scored, predictions(:one_upcoming)
    assert_includes Prediction.for_stage(:group), predictions(:one_upcoming)
    assert_empty Prediction.for_stage(:final)
  end
end
