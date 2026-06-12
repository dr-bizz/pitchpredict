require "test_helper"

class ScoringServiceTest < ActiveSupport::TestCase
  test "exact score earns 4 points" do
    assert_equal 4, ScoringService.points_for(predicted_home: 2, predicted_away: 1, actual_home: 2, actual_away: 1)
  end

  test "correct goal difference but not exact earns 3 points" do
    assert_equal 3, ScoringService.points_for(predicted_home: 3, predicted_away: 2, actual_home: 2, actual_away: 1)
  end

  test "draw predicted as a draw with the wrong score earns 3 points" do
    assert_equal 3, ScoringService.points_for(predicted_home: 1, predicted_away: 1, actual_home: 0, actual_away: 0)
  end

  test "correct outcome with wrong goal difference earns 2 points" do
    assert_equal 2, ScoringService.points_for(predicted_home: 3, predicted_away: 1, actual_home: 1, actual_away: 0)
    assert_equal 2, ScoringService.points_for(predicted_home: 0, predicted_away: 1, actual_home: 1, actual_away: 3)
  end

  test "wrong outcome earns 0 points" do
    assert_equal 0, ScoringService.points_for(predicted_home: 0, predicted_away: 2, actual_home: 2, actual_away: 1)
    assert_equal 0, ScoringService.points_for(predicted_home: 1, predicted_away: 1, actual_home: 2, actual_away: 1)
  end

  test "score_fixture! recomputes and persists points for every prediction of the fixture" do
    fixture = fixtures(:finished_group) # brazil 2-1 france

    exact = predictions(:two_finished) # predicted 2-1, fixture data has stale points_awarded: 5
    diff = Prediction.new(user: users(:one), fixture: fixture, home_score: 3, away_score: 2)
    diff.save!(validate: false) # bypass kickoff lock to seed a post-kickoff prediction

    ScoringService.score_fixture!(fixture)

    assert_equal 4, exact.reload.points_awarded
    assert_equal 3, diff.reload.points_awarded
  end

  test "score_fixture! raises on an unfinished fixture" do
    error = assert_raises(ArgumentError) { ScoringService.score_fixture!(fixtures(:upcoming_group)) }
    assert_match(/not finished/, error.message)
  end

  test "champion_team_id is nil without a finished final" do
    assert_nil ScoringService.champion_team_id

    Fixture.create!(
      home_team: teams(:brazil), away_team: teams(:france), stadium: stadia(:metlife),
      kickoff_at: 1.day.from_now, stage: :final, status: :scheduled
    )
    assert_nil ScoringService.champion_team_id
  end

  test "champion_team_id returns the winning team of the finished final" do
    final = create_finished_final(home_score: 1, away_score: 3)
    assert_equal teams(:france).id, ScoringService.champion_team_id

    final.update_columns(home_score: 2, away_score: 0)
    assert_equal teams(:brazil).id, ScoringService.champion_team_id
  end

  test "champion_team_id is nil when the final scores are level" do
    create_finished_final(home_score: 1, away_score: 1)
    assert_nil ScoringService.champion_team_id
  end

  # NOTE: the bonus is applied at read time by LeaderboardService (it is never
  # persisted on Prediction), so this asserts both the constant and that the
  # leaderboard credits exactly +10 to the user who picked the champion.
  test "champion bonus is worth 10 points and reaches the picker's total" do
    assert_equal 10, ScoringService::CHAMPION_BONUS

    totals_before = leaderboard_totals
    create_finished_final(home_score: 2, away_score: 0) # brazil wins; users(:two) picked brazil
    totals_after = leaderboard_totals

    assert_equal totals_before[users(:two).id] + ScoringService::CHAMPION_BONUS, totals_after[users(:two).id]
    assert_equal totals_before[users(:one).id], totals_after[users(:one).id]
  end

  private

  def leaderboard_totals
    LeaderboardService.new.rows.to_h { |row| [ row.user.id, row.total_points ] }
  end

  def create_finished_final(home_score:, away_score:)
    Fixture.create!(
      home_team: teams(:brazil), away_team: teams(:france), stadium: stadia(:azteca),
      kickoff_at: 1.day.ago, stage: :final, status: :finished,
      home_score: home_score, away_score: away_score
    )
  end
end
