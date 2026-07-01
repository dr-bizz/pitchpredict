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

  test "cannot predict a fixture whose result was entered before kickoff" do
    fixture = fixtures(:upcoming_group)
    fixture.update!(status: :finished, home_score: 2, away_score: 1)

    sneaky = Prediction.new(user: users(:two), fixture: fixture, home_score: 2, away_score: 1)
    assert_not sneaky.valid?
    assert_match(/locked/, sneaky.errors.full_messages.to_sentence)
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

  test "cannot predict a knockout fixture whose teams are not yet known" do
    tbd = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_slot_label: "Winner Group A",
                          away_slot_label: "Runner-up Group B", match_number: 73)
    prediction = users(:one).predictions.build(fixture: tbd, home_score: 1, away_score: 0)
    assert_not prediction.valid?
    assert prediction.errors.added?(:base, "Teams for this match haven't been announced yet")
  end

  test "penalty_winner round-trips as a home/away enum" do
    prediction = predictions(:one_upcoming)
    prediction.penalty_winner = :home
    assert_equal "home", prediction.penalty_winner
    assert prediction.penalty_winner_home?
  end

  test "predicting a knockout draw requires a penalty winner" do
    prediction = Prediction.new(user: users(:one), fixture: open_knockout_fixture,
                                home_score: 1, away_score: 1)
    assert_not prediction.valid?
    assert prediction.errors[:penalty_winner].any?

    prediction.penalty_winner = :home
    assert prediction.valid?, prediction.errors.full_messages.to_sentence
  end

  test "a non-draw knockout prediction drops any penalty winner" do
    prediction = Prediction.new(user: users(:one), fixture: open_knockout_fixture,
                                home_score: 2, away_score: 1, penalty_winner: :home)
    assert prediction.valid?
    assert_nil prediction.penalty_winner
  end

  test "a group-stage draw prediction never carries a penalty winner" do
    prediction = Prediction.new(user: users(:two), fixture: fixtures(:upcoming_group),
                                home_score: 1, away_score: 1, penalty_winner: :away)
    assert prediction.valid?
    assert_nil prediction.penalty_winner
  end

  test "penalty_winner_team resolves against the fixture's teams" do
    fixture = open_knockout_fixture
    prediction = Prediction.new(user: users(:one), fixture: fixture,
                                home_score: 0, away_score: 0, penalty_winner: :away)
    assert_equal fixture.away_team, prediction.penalty_winner_team
  end

  private

  def open_knockout_fixture
    Fixture.create!(stadium: stadia(:metlife), kickoff_at: 7.days.from_now, stage: :r16,
                    match_number: 89, home_team: teams(:spain), away_team: teams(:canada))
  end
end
