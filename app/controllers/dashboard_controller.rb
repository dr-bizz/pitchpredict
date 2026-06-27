class DashboardController < ApplicationController
  def show
    leaderboard_rows = LeaderboardService.new.rows
    @top_rows = leaderboard_rows.first(5)
    @my_row = leaderboard_rows.find { |row| row.user.id == Current.user.id }

    # "N matches predicted" only counts matches a player can actually predict.
    # Knockout fixtures stay TBD (nil teams) until an admin enters the qualifiers,
    # so they are excluded from the denominator until both teams are known.
    @fixtures_count = Fixture.teams_set.count
    @predicted_count = Current.user.predictions.count
    @total_points = @my_row&.total_points || 0

    @champion_pick = Current.user.champion_pick
    @champion_locked = ChampionPick.picks_locked?
    @teams = Team.order(:name) unless @champion_locked
  end
end
