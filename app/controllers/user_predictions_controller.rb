class UserPredictionsController < ApplicationController
  # GET /users/:id/predictions — a read-only, head-to-head view of another
  # player's predictions, restricted to matches no longer open to prediction
  # (Fixture.locked) so a player's still-open guesses can never leak.
  def index
    @user = User.find(params[:id])
    @stage = params[:stage].presence_in(UserPredictionsHelper::PREDICTION_TABS.keys) || "past"

    fixtures = Fixture.includes(:home_team, :away_team, :stadium).locked

    if @stage == "past"
      @fixtures = fixtures.order(kickoff_at: :desc).to_a
      @by_date = @fixtures.group_by { |fixture| fixture.kickoff_at.in_time_zone.to_date }
    else
      @fixtures = fixtures.by_stage(@stage).order(:match_number, :kickoff_at).to_a
      @grouped = @fixtures.group_by { |fixture| fixture.home_team.group_name }.sort_by(&:first) if @stage == "group"
    end

    # Two queries, indexed by fixture id, scoped to the locked fixtures on screen
    # — the target's open predictions are never even fetched.
    fixture_ids = @fixtures.map(&:id)
    @owner_predictions = @user.predictions.where(fixture_id: fixture_ids).index_by(&:fixture_id)
    @viewer_predictions = Current.user.predictions.where(fixture_id: fixture_ids).index_by(&:fixture_id)

    # Header context (rank + points); nil if the target has no scored predictions.
    @user_row = LeaderboardService.fetch_rows.find { |row| row.user.id == @user.id }
  end
end
