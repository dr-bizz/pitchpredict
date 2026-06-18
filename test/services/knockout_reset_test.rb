require "test_helper"

class KnockoutResetTest < ActiveSupport::TestCase
  setup do
    # A pre-migration production database has the full 32-match knockout bracket,
    # each fixture still holding placeholder teams (and some with predictions).
    counts = KnockoutBracket.specs.group_by { |s| s[:stage] }.transform_values(&:size)
    @knockouts = []
    counts.each do |stage, count|
      count.times do |i|
        @knockouts << Fixture.create!(home_team: teams(:spain), away_team: teams(:canada),
                                      stadium: stadia(:metlife),
                                      kickoff_at: (25 + @knockouts.size).days.from_now, stage: stage)
      end
    end

    # The representative fixture + prediction the per-fixture assertions inspect.
    @ko = @knockouts.first
    @prediction = users(:one).predictions.create!(fixture: @ko, home_score: 1, away_score: 0)
  end

  test "clears teams, scores and predictions on knockout fixtures" do
    KnockoutReset.call
    @ko.reload
    assert_nil @ko.home_team_id
    assert_nil @ko.away_team_id
    assert @ko.scheduled?
    assert_not Prediction.exists?(@prediction.id)
  end

  test "assigns slot labels and match numbers from KnockoutBracket" do
    KnockoutReset.call
    assert_equal 32, Fixture.where.not(stage: Fixture.stages[:group]).where.not(home_slot_label: nil).count
    assert_equal (73..104).to_a, Fixture.where.not(stage: Fixture.stages[:group]).pluck(:match_number).sort
  end

  test "leaves group fixtures' teams intact and numbers them" do
    KnockoutReset.call
    assert_equal teams(:spain).id, fixtures(:upcoming_group).reload.home_team_id
    assert Fixture.where(stage: Fixture.stages[:group]).where.not(match_number: nil).exists?
  end

  test "is idempotent" do
    KnockoutReset.call
    assert_nothing_raised { KnockoutReset.call }
    assert_equal 32, Fixture.where.not(stage: Fixture.stages[:group]).count
  end
end
