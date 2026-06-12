class FixturesController < ApplicationController
  # GET /predictions — the predictions grid, tabbed by tournament stage.
  def index
    @stage = params[:stage].presence_in(Fixture.stages.keys) || "group"

    @fixtures = Fixture.by_stage(@stage)
                       .includes(:home_team, :away_team, :stadium)
                       .order(:kickoff_at)
                       .to_a

    # Avoid an N+1: one query for all of the current user's predictions on this page.
    @predictions_by_fixture_id =
      Current.user.predictions.where(fixture_id: @fixtures.map(&:id)).index_by(&:fixture_id)

    # NOTE: assumption — group-stage fixtures always pair teams from the same
    # group, so the home team's group_name is the fixture's group.
    @grouped = @fixtures.group_by { |fixture| fixture.home_team.group_name }.sort_by(&:first) if @stage == "group"
  end
end
