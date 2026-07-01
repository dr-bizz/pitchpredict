class LeaderboardsController < ApplicationController
  # NOTE: routes define `resource :leaderboard, only: :show` (singular), so the
  # action is #show rather than #index. Live updates arrive via the "results"
  # Turbo Stream refresh broadcast from ScoreFixtureJob.
  def show
    @overall_rows = LeaderboardService.fetch_rows(variant: :overall)
    @r16_rows = LeaderboardService.fetch_rows(variant: :r16)
  end
end
