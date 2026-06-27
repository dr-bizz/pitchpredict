module Admin
  class FixturesController < BaseController
    before_action :set_fixture, only: %i[ edit update row ]

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
      # turbo_stream: swap the row in place for an inline edit form (edit.turbo_stream.erb).
      # html: full edit page as a no-JS fallback.
      respond_to do |format|
        format.turbo_stream
        format.html
      end
    end

    def update
      # A knockout match's teams must be set (via the knockout bracket screen)
      # before a result can be entered — guard here for a friendly message; the
      # Fixture model also refuses to finish a teams-unknown match.
      unless @fixture.teams_known?
        respond_to do |format|
          format.turbo_stream do
            @fixture.errors.add(:base, "Set both teams for this match before entering a result.")
            render :update, status: :unprocessable_entity
          end
          format.html do
            redirect_to admin_knockout_fixtures_path,
                        alert: "Set both teams for this match before entering a result."
          end
        end
        return
      end

      # Entering a result always marks the fixture finished; the Fixture model
      # validates that both scores are then present and >= 0.
      if @fixture.update(result_params.merge(status: :finished))
        ScoreFixtureJob.perform_later(@fixture.id)
        respond_to do |format|
          format.turbo_stream # update.turbo_stream.erb — swap row to result + toast
          format.html do
            redirect_to admin_fixtures_path,
                        notice: "Result saved: #{@fixture.home_display} #{@fixture.home_score}–#{@fixture.away_score} #{@fixture.away_display}. Predictions are being scored."
          end
        end
      else
        respond_to do |format|
          format.turbo_stream { render :update, status: :unprocessable_entity }
          format.html { render :edit, status: :unprocessable_entity }
        end
      end
    end

    # GET member action backing the inline edit's Cancel link: re-render the
    # display row, reverting the in-place form.
    def row
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_fixtures_path }
      end
    end

    private

    def set_fixture
      @fixture = Fixture.find(params.expect(:id))
    end

    def result_params
      params.expect(fixture: [ :home_score, :away_score ])
    end
  end
end
