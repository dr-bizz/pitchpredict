# One-time, idempotent normalisation for databases seeded BEFORE knockout
# fixtures were TBD. Used by the backfill migration (and safe to re-run): clears
# the placeholder teams/scores/predictions on every knockout fixture and stamps
# the KnockoutBracket slot labels + match numbers. Also numbers group fixtures.
class KnockoutReset
  GROUP = 0 # Fixture.stages[:group]

  def self.call
    new.call
  end

  def call
    Fixture.transaction do
      number_group_fixtures
      reset_knockout_fixtures
    end
    LeaderboardService.expire_rows if defined?(LeaderboardService)
  end

  private

  def number_group_fixtures
    Fixture.where(stage: GROUP).order(:kickoff_at, :id).each_with_index do |fixture, i|
      fixture.update_columns(match_number: i + 1)
    end
  end

  def reset_knockout_fixtures
    specs = KnockoutBracket.specs.sort_by { |s| s[:match_number] }
    knockouts = Fixture.where.not(stage: GROUP).order(:stage, :kickoff_at, :id).to_a

    knockouts.zip(specs).each do |fixture, spec|
      next unless spec

      Prediction.where(fixture_id: fixture.id).delete_all
      fixture.update_columns(
        home_team_id: nil, away_team_id: nil, home_score: nil, away_score: nil,
        status: 0, # scheduled
        home_slot_label: spec[:home_label], away_slot_label: spec[:away_label],
        match_number: spec[:match_number]
      )
    end
  end
end
