# Scores every prediction for a finished fixture, then pushes the fresh
# leaderboard to subscribers over Turbo Streams (Solid Cable).
class ScoreFixtureJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(fixture_id)
    fixture = Fixture.find(fixture_id)
    ScoringService.score_fixture!(fixture)

    # Prediction after_commit hooks already expired the cached rows, but expire
    # again defensively: a result correction on a fixture nobody predicted
    # (e.g. the final, which drives the champion bonus) touches no Prediction.
    LeaderboardService.expire_rows

    # CONTRACT with the UI stage: the leaderboard page subscribes with
    # turbo_stream_from "leaderboard" and renders leaderboards/_table inside
    # an element with id="leaderboard-table".
    # NOTE: current_user is nil here — a background job has no session, so the
    # broadcast HTML is viewer-agnostic. Each viewer's own-row highlight is
    # re-applied client-side by leaderboard_highlight_controller.js (it matches
    # tr[data-user-id] against the layout's current-user-id meta tag).
    Turbo::StreamsChannel.broadcast_replace_to(
      "leaderboard",
      target: "leaderboard-table",
      partial: "leaderboards/table",
      locals: { rows: LeaderboardService.fetch_rows, current_user: nil }
    )
  end
end
