require "test_helper"

class FixtureTest < ActiveSupport::TestCase
  test "locked? is true once kickoff has passed" do
    assert fixtures(:finished_group).locked?
    assert_not fixtures(:upcoming_group).locked?
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
end
