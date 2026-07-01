class PredictionsController < ApplicationController
  before_action :set_fixture

  # POST /fixtures/:fixture_id/prediction
  def create
    upsert_prediction
  end

  # PATCH /fixtures/:fixture_id/prediction
  def update
    upsert_prediction
  end

  private

  def set_fixture
    @fixture = Fixture.includes(:home_team, :away_team, :stadium).find(params.expect(:fixture_id))
  end

  def prediction_params
    params.expect(prediction: [ :home_score, :away_score, :penalty_winner ])
  end

  # NOTE: create and update share an upsert. The singular nested route carries
  # no prediction id, so the record is always looked up by (user, fixture); a
  # stale POST against an already-predicted fixture updates it instead of
  # tripping the unique index. Locked fixtures are rejected by the Prediction
  # model validation and rendered back into the card's Turbo Frame with a 422.
  def upsert_prediction
    @prediction = Current.user.predictions.find_or_initialize_by(fixture: @fixture)
    @prediction.assign_attributes(prediction_params)

    if @prediction.save
      render_card just_saved: true
    else
      render_card status: :unprocessable_entity
    end
  end

  def render_card(just_saved: false, status: :ok)
    render partial: "fixtures/fixture_card",
           locals: { fixture: @fixture, prediction: @prediction, just_saved: just_saved },
           status: status
  end
end
