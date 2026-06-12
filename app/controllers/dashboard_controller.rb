class DashboardController < ApplicationController
  def show
    leaderboard_rows = LeaderboardService.new.rows
    @top_rows = leaderboard_rows.first(5)
    @my_row = leaderboard_rows.find { |row| row.user.id == Current.user.id }

    # NOTE: assumption — "N matches predicted" counts every seeded fixture as
    # predictable, including knockout games whose pairings are already known
    # (the seeds create the full 104-match schedule up front).
    @fixtures_count = Fixture.count
    @predicted_count = Current.user.predictions.count
    @total_points = @my_row&.total_points || 0

    @champion_pick = Current.user.champion_pick
    @champion_locked = ChampionPick.tournament_started?
    @teams = Team.order(:name) unless @champion_locked
  end
end
