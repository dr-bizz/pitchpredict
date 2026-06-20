class FixturesController < ApplicationController
  # GET /predictions — the predictions grid. The virtual tabs filter by time and
  # prediction status: "upcoming" lists every not-yet-started match in date
  # order; "unpredicted" narrows that to matches this player still has to pick;
  # "past" shows matches that have kicked off. The rest filter by tournament stage.
  def index
    @stage = params[:stage].presence_in(FixturesHelper::STAGE_TABS.keys) || "upcoming"

    fixtures = Fixture.includes(:home_team, :away_team, :stadium)

    case @stage
    when "upcoming"
      # Soonest kickoff first — every match still open to predict.
      @fixtures = fixtures.upcoming.to_a
      @by_date = group_by_kickoff_date(@fixtures)
    when "unpredicted"
      # Soonest first, like "upcoming", but only matches open to predict
      # (teams set, not yet locked) that this player hasn't picked. Matches
      # whose teams are still TBD are excluded — there is nothing to predict.
      @fixtures = fixtures.upcoming.scheduled.teams_set
                          .where.not(id: Current.user.predictions.select(:fixture_id))
                          .to_a
      @by_date = group_by_kickoff_date(@fixtures)
    when "past"
      # Most recent kickoff first (Fixture.past is kickoff-descending).
      @fixtures = fixtures.past.to_a
      @by_date = group_by_kickoff_date(@fixtures)
    else
      @fixtures = fixtures.by_stage(@stage).order(:match_number, :kickoff_at).to_a
      # NOTE: assumption — group-stage fixtures always pair teams from the same
      # group, so the home team's group_name is the fixture's group.
      @grouped = @fixtures.group_by { |fixture| fixture.home_team.group_name }.sort_by(&:first) if @stage == "group"
    end

    # Avoid an N+1: one query for all of the current user's predictions on this page.
    @predictions_by_fixture_id =
      Current.user.predictions.where(fixture_id: @fixtures.map(&:id)).index_by(&:fixture_id)
  end

  private

  # Ordered hash of date => fixtures, preserving the relation's kickoff order
  # and grouped in the app's display zone so day headers match the card times.
  def group_by_kickoff_date(fixtures)
    fixtures.group_by { |fixture| fixture.kickoff_at.in_time_zone.to_date }
  end
end
