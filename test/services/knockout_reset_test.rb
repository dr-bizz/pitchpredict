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
    knockouts = Fixture.where.not(stage: Fixture.stages[:group])
    assert_equal 32, knockouts.where.not(home_slot_label: nil).count
    assert_equal (73..104).to_a, knockouts.pluck(:match_number).sort
  end

  test "maps the right slot labels onto the right fixtures" do
    KnockoutReset.call
    first_r32 = Fixture.find_by!(match_number: 73)
    assert_equal "r32", first_r32.stage
    assert_equal "Winner Group A", first_r32.home_slot_label

    final = Fixture.find_by!(match_number: 104)
    assert_equal "final", final.stage
    assert_equal "Winner of Match 101", final.home_slot_label
    assert_equal "Winner of Match 102", final.away_slot_label
  end

  test "leaves group fixtures' teams, results and predictions intact" do
    group_count = Fixture.where(stage: Fixture.stages[:group]).count
    finished = fixtures(:finished_group)

    KnockoutReset.call

    assert_equal group_count, Fixture.where(stage: Fixture.stages[:group]).count
    assert_equal teams(:spain).id, fixtures(:upcoming_group).reload.home_team_id
    finished.reload
    assert finished.finished?
    assert_equal [ 2, 1 ], [ finished.home_score, finished.away_score ]
    assert Prediction.exists?(predictions(:two_finished).id)
    assert Fixture.where(stage: Fixture.stages[:group]).where.not(match_number: nil).exists?
  end

  test "is idempotent — a second run produces identical labels and numbers" do
    KnockoutReset.call
    snapshot = Fixture.where.not(stage: Fixture.stages[:group]).order(:id)
                      .pluck(:id, :home_slot_label, :away_slot_label, :match_number)

    assert_nothing_raised { KnockoutReset.call }

    after = Fixture.where.not(stage: Fixture.stages[:group]).order(:id)
                   .pluck(:id, :home_slot_label, :away_slot_label, :match_number)
    assert_equal snapshot, after
    assert_equal 32, Fixture.where.not(stage: Fixture.stages[:group]).count
  end
end
