class LeaderboardsController < ApplicationController
  # NOTE: routes define `resource :leaderboard, only: :show` (singular), so the
  # action is #show rather than #index. Live updates arrive via the
  # "leaderboard" Turbo Stream broadcast from ScoreFixtureJob.
  def show
    @rows = LeaderboardService.fetch_rows
  end
end
