class FixturesController < ApplicationController
  # GET /predictions — the predictions grid. The "upcoming" tab lists every
  # not-yet-started match in date order; the others filter by tournament stage.
  def index
    @stage = params[:stage].presence_in(FixturesHelper::STAGE_TABS.keys) || "upcoming"

    fixtures = Fixture.includes(:home_team, :away_team, :stadium)

    if @stage == "upcoming"
      # Soonest kickoff first — only matches still open to predict.
      @fixtures = fixtures.upcoming.to_a
      # Ordered hash of date => fixtures (upcoming is already kickoff-ascending),
      # grouped in the app's display zone so headers match the card times.
      @by_date = @fixtures.group_by { |fixture| fixture.kickoff_at.in_time_zone.to_date }
    else
      @fixtures = fixtures.by_stage(@stage).order(:kickoff_at).to_a
      # NOTE: assumption — group-stage fixtures always pair teams from the same
      # group, so the home team's group_name is the fixture's group.
      @grouped = @fixtures.group_by { |fixture| fixture.home_team.group_name }.sort_by(&:first) if @stage == "group"
    end

    # Avoid an N+1: one query for all of the current user's predictions on this page.
    @predictions_by_fixture_id =
      Current.user.predictions.where(fixture_id: @fixtures.map(&:id)).index_by(&:fixture_id)
  end
end
