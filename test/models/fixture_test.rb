require "test_helper"

class FixtureTest < ActiveSupport::TestCase
  test "locked? is true once kickoff has passed" do
    assert fixtures(:finished_group).locked?
    assert_not fixtures(:upcoming_group).locked?
  end

  test "locked? is true when a result is entered before kickoff" do
    fixture = fixtures(:upcoming_group)
    fixture.update!(status: :finished, home_score: 2, away_score: 1)

    assert fixture.kickoff_at.future?, "precondition: kickoff has not passed"
    assert fixture.locked?
  end

  test "locked? is true for a live fixture even before kickoff" do
    fixture = fixtures(:upcoming_group)
    fixture.status = :live

    assert fixture.locked?
  end

  test "home and away team must differ" do
    fixture = fixtures(:upcoming_group)
    fixture.away_team = fixture.home_team
    assert_not fixture.valid?
    assert fixture.errors[:away_team].any?
  end

  test "finished fixture requires both scores" do
    fixture = fixtures(:upcoming_group)
    fixture.status = :finished
    assert_not fixture.valid?
  end

  test "upcoming, past and by_stage scopes" do
    assert_includes Fixture.upcoming, fixtures(:upcoming_group)
    assert_not_includes Fixture.upcoming, fixtures(:finished_group)
    assert_includes Fixture.past, fixtures(:finished_group)
    assert_not_includes Fixture.past, fixtures(:upcoming_group)
    assert_includes Fixture.by_stage(:group), fixtures(:upcoming_group)
    assert_empty Fixture.by_stage(:final)
  end

  test "knockout fixture is valid with no teams and slot labels" do
    fixture = Fixture.new(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_slot_label: "Winner Group A",
                          away_slot_label: "Runner-up Group B", match_number: 73)
    assert fixture.valid?, fixture.errors.full_messages.to_sentence
    assert_not fixture.teams_known?
  end

  test "group fixture requires both teams" do
    fixture = Fixture.new(stadium: stadia(:metlife), kickoff_at: 5.days.from_now, stage: :group)
    assert_not fixture.valid?
    assert fixture.errors.added?(:base, "Group fixtures require both teams")
  end

  test "a knockout fixture cannot have only one team" do
    fixture = Fixture.new(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_team: teams(:spain))
    assert_not fixture.valid?
    assert fixture.errors.added?(:base, "Both teams must be set together")
  end

  test "teams_known? and open_for_predictions? reflect team presence" do
    known = fixtures(:upcoming_group)
    assert known.teams_known?
    assert known.open_for_predictions?

    tbd = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_slot_label: "Winner Group A",
                          away_slot_label: "Runner-up Group B", match_number: 73)
    assert_not tbd.open_for_predictions?
  end

  test "display helpers fall back to slot label then TBD" do
    tbd = Fixture.new(stage: :r16, home_slot_label: "Winner of Match 73")
    assert_equal "Winner of Match 73", tbd.home_display
    assert_equal "TBD", tbd.away_display
    assert_equal "🏳️", tbd.home_flag
    assert_equal "Spain", fixtures(:upcoming_group).home_display
  end

  test "a knockout fixture cannot be finished while its teams are unknown" do
    tbd = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_slot_label: "Winner Group A",
                          away_slot_label: "Runner-up Group B", match_number: 73)
    tbd.assign_attributes(status: :finished, home_score: 2, away_score: 1)
    assert_not tbd.valid?
    assert tbd.errors.added?(:base, "Cannot finish a match before both teams are known")
  end
end
