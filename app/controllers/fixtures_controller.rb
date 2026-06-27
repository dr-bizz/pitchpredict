class FixturesController < ApplicationController
  # GET /predictions — the predictions grid. Two independent, combinable filter
  # axes: STATUS (all / upcoming / unpredicted / predicted / past) and STAGE
  # (all / group / r32 / … / final). Both default to "all"; unknown params fall
  # back to "all". PredictionsGridQuery turns the pair into ordered sections.
  def index
    @status = params[:status].presence_in(FixturesHelper::STATUS_TABS.keys) || "all"
    @stage = params[:stage].presence_in(FixturesHelper::STAGE_TABS.keys) || "all"

    query = PredictionsGridQuery.new(user: Current.user, status: @status, stage: @stage)
    @sections = query.sections

    # Avoid an N+1: one query for all of the current user's predictions on this page.
    @predictions_by_fixture_id =
      Current.user.predictions.where(fixture_id: query.fixtures.map(&:id)).index_by(&:fixture_id)
  end
end
