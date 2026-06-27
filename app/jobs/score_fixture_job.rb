# Scores every prediction for a finished fixture, then tells every subscribed
# player-facing page to refresh itself over Turbo Streams (Solid Cable).
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

    # CONTRACT with the UI stage: the player-facing pages (dashboard,
    # predictions grid, leaderboard) subscribe with turbo_stream_from "results".
    # A refresh broadcast carries no HTML — each subscribed browser re-GETs its
    # OWN current URL with its OWN session and morphs the diff. So every viewer
    # re-renders server-side with the correct Current.user (own-row highlight,
    # "my rank") without any viewer-specific broadcast. The refresh is
    # idempotent (a morph), so the client that triggered the job refreshing too
    # is harmless.
    Turbo::StreamsChannel.broadcast_refresh_to("results")
  end
end
