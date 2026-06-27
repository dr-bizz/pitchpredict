class DashboardController < ApplicationController
  def show
    # Cached entry point — avoids recomputing the leaderboard here AND again in
    # the view (the view now reuses @top_rows instead of re-calling the service).
    leaderboard_rows = LeaderboardService.fetch_rows
    @top_rows = leaderboard_rows.first(5)
    @my_row = leaderboard_rows.find { |row| row.user.id == Current.user.id }

    # "N matches predicted" only counts matches a player can actually predict.
    # Knockout fixtures stay TBD (nil teams) until an admin enters the qualifiers,
    # so they are excluded from the denominator until both teams are known.
    @fixtures_count = Fixture.teams_set.count
    @predicted_count = Current.user.predictions.count
    @total_points = @my_row&.total_points || 0

    # Unpredicted upcoming fixtures — "matches remaining" to predict. Computed in
    # one query (matches the FixturesController#index "unpredicted" tab exactly).
    # .scheduled drops fixtures that are future-kickoff but already locked (live/
    # finished, e.g. an early-entered result); teams_set drops TBD knockout
    # matches. Both are unpredictable, so neither belongs in the remaining count.
    @remaining_to_predict = Fixture.upcoming.scheduled.teams_set
                                   .where.not(id: Current.user.predictions.select(:fixture_id)).count

    @champion_pick = Current.user.champion_pick
    @champion_locked = ChampionPick.picks_locked?
    @teams = Team.order(:name) unless @champion_locked
  end
end
