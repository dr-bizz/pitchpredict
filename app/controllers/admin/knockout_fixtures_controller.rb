module Admin
  class KnockoutFixturesController < BaseController
    def index
      @fixtures = Fixture.includes(:home_team, :away_team, :stadium)
                         .where.not(stage: Fixture.stages[:group])
                         .order(:match_number, :kickoff_at)
      @teams = Team.order(:group_name, :name)
    end

    def update
      @fixture = Fixture.find(params.expect(:id))
      if @fixture.update(knockout_params)
        redirect_to admin_knockout_fixtures_path,
                    notice: "Saved: #{@fixture.home_display} vs #{@fixture.away_display}."
      else
        redirect_to admin_knockout_fixtures_path, alert: @fixture.errors.full_messages.to_sentence
      end
    end

    private

    # Blank ("") clears a slot back to TBD; presence turns it into a real id.
    def knockout_params
      params.expect(fixture: [ :home_team_id, :away_team_id ]).transform_values(&:presence)
    end
  end
end
