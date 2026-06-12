module Admin
  class FixturesController < ApplicationController
    before_action :require_admin
    before_action :set_fixture, only: %i[ edit update ]

    def index
      # NOTE: presence_in returns nil for blank/unknown values, so bad params
      # silently fall back to "all" instead of raising on an invalid enum.
      @stage  = params[:stage].presence_in(Fixture.stages.keys)
      @status = params[:status].presence_in(Fixture.statuses.keys)

      fixtures = Fixture.includes(:home_team, :away_team, :stadium)
      fixtures = fixtures.by_stage(@stage) if @stage
      fixtures = fixtures.where(status: @status) if @status

      # Scheduled first (enum values: scheduled 0 < live 1 < finished 2),
      # then soonest kickoff so the next match to settle is on top.
      @fixtures = fixtures.order(:status, :kickoff_at)
    end

    def edit
    end

    def update
      # Entering a result always marks the fixture finished; the Fixture model
      # validates that both scores are then present and >= 0.
      if @fixture.update(result_params.merge(status: :finished))
        ScoreFixtureJob.perform_later(@fixture.id)
        redirect_to admin_fixtures_path,
                    notice: "Result saved: #{@fixture.home_team.name} #{@fixture.home_score}–#{@fixture.away_score} #{@fixture.away_team.name}. Predictions are being scored."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_fixture
      @fixture = Fixture.find(params.expect(:id))
    end

    def result_params
      params.expect(fixture: [ :home_score, :away_score ])
    end

    def require_admin
      return if Current.user&.admin?

      redirect_to root_path, alert: "You don't have access to the admin area."
    end
  end
end
