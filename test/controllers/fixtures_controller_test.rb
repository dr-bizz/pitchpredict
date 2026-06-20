require "test_helper"

class FixturesControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get predictions_path

    assert_redirected_to new_session_path
  end

  test "shows upcoming matches by date by default" do
    sign_in_as users(:one)
    get predictions_path

    assert_response :success
    assert_select "a[aria-current=page]", text: "Upcoming"
    # Upcoming groups by day (not by group), and only future matches appear.
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id}", count: 0
  end

  test "shows the group stage with group headings and per-fixture frames" do
    sign_in_as users(:one)
    get predictions_path(stage: "group")

    assert_response :success
    assert_select "h2", text: "Group A"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}"
    assert_select "a[aria-current=page]", text: "Groups"
    assert_match "Spain", response.body
    assert_match "MetLife Stadium", response.body
    assert_match "East Rutherford", response.body
  end

  test "prefills the form and shows the Predicted pill for predicted fixtures" do
    sign_in_as users(:one)
    get predictions_path(stage: "group")

    assert_select "span.badge.badge-success", text: "Predicted"
    assert_select "input[name='prediction[home_score]'][value='2']"
  end

  test "finished fixtures show the actual score, locked inputs and the points pill" do
    sign_in_as users(:two)
    get predictions_path(stage: "group")

    assert_response :success
    # Finished card shows the real result: a prominent score block (2–1) and a
    # "Result: 2–1" footer. The en-dash separator is its own span, so assert the
    # footer result text rather than a brittle whitespace match.
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} footer",
                  text: /Result:\s*2–1/
    assert_select "span.badge.badge-warning", text: "+5 pts"
    # A finished fixture is locked from editing: it renders no form and no
    # editable score inputs (the result is shown as a static score block).
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} form", count: 0
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} input", count: 0
  end

  test "finished fixture without a prediction shows the No prediction pill" do
    sign_in_as users(:one)
    get predictions_path(stage: "group")

    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} span.badge.badge-ghost",
                  text: "No prediction"
  end

  test "filters fixtures by stage with an empty state" do
    sign_in_as users(:one)
    get predictions_path(stage: "final")

    assert_response :success
    assert_select "a[aria-current=page]", text: "Final"
    assert_match "No fixtures scheduled", response.body
  end

  test "falls back to the upcoming view for unknown stage params" do
    sign_in_as users(:one)
    get predictions_path(stage: "bogus")

    assert_response :success
    assert_select "a[aria-current=page]", text: "Upcoming"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}"
  end

  test "upcoming lists matches with the soonest kickoff first" do
    sign_in_as users(:one)
    # upcoming_group kicks off in 7 days; add a later match to pin the ordering.
    later = Fixture.create!(stadium: stadia(:azteca), kickoff_at: 30.days.from_now,
                            stage: :r32, home_team: teams(:brazil), away_team: teams(:france),
                            status: :scheduled, match_number: 99)
    get predictions_path

    assert_response :success
    sooner = response.body.index("prediction_fixture_#{fixtures(:upcoming_group).id}")
    farther = response.body.index("prediction_fixture_#{later.id}")
    assert sooner && farther && sooner < farther,
           "expected the sooner kickoff to render before the later one"
  end

  test "past shows kicked-off matches and excludes upcoming ones" do
    sign_in_as users(:one)
    get predictions_path(stage: "past")

    assert_response :success
    assert_select "a[aria-current=page]", text: "Past"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id}"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}", count: 0
  end

  test "past lists matches with the most recent kickoff first" do
    sign_in_as users(:one)
    # finished_group is 2 days ago; add an older match to pin the descending order.
    older = Fixture.create!(stadium: stadia(:azteca), kickoff_at: 10.days.ago,
                            stage: :group, home_team: teams(:spain), away_team: teams(:canada),
                            status: :finished, home_score: 1, away_score: 0, match_number: 98)
    get predictions_path(stage: "past")

    assert_response :success
    recent = response.body.index("prediction_fixture_#{fixtures(:finished_group).id}")
    older_pos = response.body.index("prediction_fixture_#{older.id}")
    assert recent && older_pos && recent < older_pos,
           "expected the more-recent kickoff to render before the older one"
  end

  test "unpredicted shows open matches the player has not picked yet" do
    # User two has no prediction on the open upcoming_group.
    sign_in_as users(:two)
    get predictions_path(stage: "unpredicted")

    assert_response :success
    assert_select "a[aria-current=page]", text: "Unpredicted"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}"
    # A kicked-off match can no longer be predicted, so it never shows here.
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id}", count: 0
  end

  test "unpredicted excludes matches the player has already predicted" do
    # User one predicted upcoming_group, leaving nothing open to pick.
    sign_in_as users(:one)
    get predictions_path(stage: "unpredicted")

    assert_response :success
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}", count: 0
    assert_match "all caught up", response.body
  end

  test "unpredicted excludes future matches whose teams are not yet set" do
    sign_in_as users(:two)
    tbd = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                          stage: :r32, home_slot_label: "Winner Group A",
                          away_slot_label: "Runner-up Group B", match_number: 73)
    get predictions_path(stage: "unpredicted")

    assert_response :success
    assert_select "turbo-frame#prediction_fixture_#{tbd.id}", count: 0
  end

  test "unpredicted excludes future matches locked by status (live or pre-kickoff result)" do
    # A live or already-finished match in the future is locked even though its
    # kickoff is still ahead — the .scheduled guard must keep it off this tab.
    sign_in_as users(:two)
    live = Fixture.create!(stadium: stadia(:azteca), kickoff_at: 5.days.from_now,
                           stage: :r32, home_team: teams(:brazil), away_team: teams(:france),
                           status: :live, match_number: 80)
    finished_future = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 6.days.from_now,
                                      stage: :r32, home_team: teams(:spain), away_team: teams(:canada),
                                      status: :finished, home_score: 1, away_score: 0, match_number: 81)
    get predictions_path(stage: "unpredicted")

    assert_response :success
    assert_select "turbo-frame#prediction_fixture_#{live.id}", count: 0
    assert_select "turbo-frame#prediction_fixture_#{finished_future.id}", count: 0
  end

  test "knockout fixture with unknown teams renders as a non-predictable TBD card" do
    sign_in_as users(:one)
    ko = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 20.days.from_now,
                         stage: :r32, home_slot_label: "Winner Group A",
                         away_slot_label: "Runner-up Group B", match_number: 73)
    get predictions_path(stage: "r32")
    assert_response :success
    assert_includes response.body, "Winner Group A"
    assert_includes response.body, "Runner-up Group B"
    # The TBD card renders no prediction form and no editable score inputs, and
    # shows the "Teams to be announced" affordance instead.
    frame = "turbo-frame#prediction_fixture_#{ko.id}"
    assert_select "#{frame} form", count: 0
    assert_select "#{frame} input", count: 0
    assert_select frame, text: /Teams to be announced/
  end
end
