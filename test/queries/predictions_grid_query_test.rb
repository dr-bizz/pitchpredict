require "test_helper"

class PredictionsGridQueryTest < ActiveSupport::TestCase
  def sections_for(user, status:, stage:)
    PredictionsGridQuery.new(user: user, status: status, stage: stage).sections
  end

  def fixture_ids(sections)
    sections.flat_map(&:fixtures).map(&:id)
  end

  test "all/all includes both upcoming and past matches" do
    ids = fixture_ids(sections_for(users(:one), status: "all", stage: "all"))

    assert_includes ids, fixtures(:upcoming_group).id
    assert_includes ids, fixtures(:finished_group).id
  end

  test "all/all orders upcoming sections before past sections and tags the past ones" do
    sections = sections_for(users(:one), status: "all", stage: "all")

    upcoming_idx = sections.index { |s| s.fixtures.include?(fixtures(:upcoming_group)) }
    past_idx = sections.index { |s| s.fixtures.include?(fixtures(:finished_group)) }

    assert upcoming_idx < past_idx, "expected upcoming section before past section"
    refute sections[upcoming_idx].past, "upcoming section should not be tagged past"
    assert sections[past_idx].past, "past section should be tagged past"
  end

  test "upcoming status excludes matches that have kicked off" do
    ids = fixture_ids(sections_for(users(:one), status: "upcoming", stage: "all"))

    assert_includes ids, fixtures(:upcoming_group).id
    refute_includes ids, fixtures(:finished_group).id
  end

  test "past status excludes matches still upcoming" do
    ids = fixture_ids(sections_for(users(:one), status: "past", stage: "all"))

    assert_includes ids, fixtures(:finished_group).id
    refute_includes ids, fixtures(:upcoming_group).id
  end

  test "unpredicted status lists open matches the player has not picked" do
    # User two has no prediction on the open upcoming_group.
    ids = fixture_ids(sections_for(users(:two), status: "unpredicted", stage: "all"))

    assert_includes ids, fixtures(:upcoming_group).id
    refute_includes ids, fixtures(:finished_group).id
  end

  test "unpredicted status excludes already-predicted matches" do
    # User one predicted upcoming_group.
    ids = fixture_ids(sections_for(users(:one), status: "unpredicted", stage: "all"))

    refute_includes ids, fixtures(:upcoming_group).id
  end

  test "predicted status returns only the user's predicted matches across time" do
    # User two predicted the past finished_group, nothing else.
    ids = fixture_ids(sections_for(users(:two), status: "predicted", stage: "all"))

    assert_includes ids, fixtures(:finished_group).id
    refute_includes ids, fixtures(:upcoming_group).id
  end

  test "stage=group groups matches under their group letter" do
    sections = sections_for(users(:one), status: "all", stage: "group")

    group_a = sections.find { |s| s.fixtures.include?(fixtures(:upcoming_group)) }
    assert_equal "Group A", group_a.heading
  end

  test "a single knockout stage returns one section ordered by match number" do
    later = Fixture.create!(stadium: stadia(:azteca), kickoff_at: 30.days.from_now,
                            stage: :r16, home_team: teams(:brazil), away_team: teams(:france),
                            status: :scheduled, match_number: 90)
    earlier = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 31.days.from_now,
                              stage: :r16, home_team: teams(:spain), away_team: teams(:canada),
                              status: :scheduled, match_number: 89)
    sections = sections_for(users(:one), status: "all", stage: "r16")

    assert_equal 1, sections.length
    assert_nil sections.first.heading
    assert_equal [ earlier.id, later.id ], sections.first.fixtures.map(&:id)
  end

  test "status filter combines with a stage filter" do
    ids = fixture_ids(sections_for(users(:two), status: "past", stage: "group"))

    assert_includes ids, fixtures(:finished_group).id
    refute_includes ids, fixtures(:upcoming_group).id
  end
end
