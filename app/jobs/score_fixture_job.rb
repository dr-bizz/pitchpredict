# Scores every prediction for a finished fixture, then pushes the fresh
# leaderboard to subscribers over Turbo Streams (Solid Cable).
class ScoreFixtureJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(fixture_id)
    fixture = Fixture.find(fixture_id)
    ScoringService.score_fixture!(fixture)

    # CONTRACT with the UI stage: the leaderboard page subscribes with
    # turbo_stream_from "leaderboard" and renders leaderboards/_table inside
    # an element with id="leaderboard-table".
    # NOTE: current_user is nil here — a background job has no session, so the
    # broadcast partial cannot highlight the viewer's own row.
    Turbo::StreamsChannel.broadcast_replace_to(
      "leaderboard",
      target: "leaderboard-table",
      partial: "leaderboards/table",
      locals: { rows: LeaderboardService.new.rows, current_user: nil }
    )
  end
end
