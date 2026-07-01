require "test_helper"

class FixturesControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get predictions_path

    assert_redirected_to new_session_path
  end

  test "defaults to all matches grouped by day, upcoming and past together" do
    sign_in_as users(:one)
    get predictions_path

    assert_response :success
    # Both axes default to "All", so every match shows regardless of time.
    assert_select "nav[aria-label=Status] a[aria-current=page]", text: "All"
    assert_select "nav[aria-label=Stage] a[aria-current=page]", text: "All"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id}"
  end

  test "renders a Kicked off divider between upcoming and past in the all view" do
    sign_in_as users(:one)
    get predictions_path

    assert_response :success
    assert_match "Kicked off", response.body
    # The divider sits after the upcoming match and before the past one.
    divider = response.body.index("Kicked off")
    upcoming = response.body.index("prediction_fixture_#{fixtures(:upcoming_group).id}")
    past = response.body.index("prediction_fixture_#{fixtures(:finished_group).id}")
    assert upcoming < divider && divider < past,
           "expected order: upcoming match, Kicked off divider, past match"
  end

  test "exposes both a Status and a Stage tablist" do
    sign_in_as users(:one)
    get predictions_path

    assert_select "nav[role=tablist][aria-label=Status]"
    assert_select "nav[role=tablist][aria-label=Stage]"
  end

  test "shows the group stage with group headings and per-fixture frames" do
    sign_in_as users(:one)
    get predictions_path(stage: "group")

    assert_response :success
    assert_select "h2", text: "Group A"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}"
    assert_select "nav[aria-label=Stage] a[aria-current=page]", text: "Groups"
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
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} footer",
                  text: /Result:\s*2–1/
    assert_select "span.badge.badge-warning", text: "+5 pts"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} form", count: 0
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} input", count: 0
  end

  test "finished fixture without a prediction shows the No prediction pill" do
    sign_in_as users(:one)
    get predictions_path(stage: "group")

    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} span.badge.badge-ghost",
                  text: "No prediction"
  end

  test "shows an empty state when no matches match the filters" do
    sign_in_as users(:one)
    get predictions_path(stage: "final")

    assert_response :success
    assert_select "nav[aria-label=Stage] a[aria-current=page]", text: "Final"
    assert_match "No matches", response.body
  end

  test "falls back to All for unknown status and stage params" do
    sign_in_as users(:one)
    get predictions_path(status: "bogus", stage: "bogus")

    assert_response :success
    assert_select "nav[aria-label=Status] a[aria-current=page]", text: "All"
    assert_select "nav[aria-label=Stage] a[aria-current=page]", text: "All"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}"
  end

  test "status chips preserve the selected stage and vice versa" do
    sign_in_as users(:one)
    get predictions_path(stage: "group")

    # The Past status chip keeps stage=group in its link.
    assert_select "nav[aria-label=Status] a[href=?]", predictions_path(status: "past", stage: "group")
    # The R16 stage chip keeps the current status in its link.
    assert_select "nav[aria-label=Stage] a[href=?]", predictions_path(stage: "r16", status: "all")
  end

  test "upcoming status lists matches with the soonest kickoff first" do
    sign_in_as users(:one)
    later = Fixture.create!(stadium: stadia(:azteca), kickoff_at: 30.days.from_now,
                            stage: :r32, home_team: teams(:brazil), away_team: teams(:france),
                            status: :scheduled, match_number: 99)
    get predictions_path(status: "upcoming")

    assert_response :success
    sooner = response.body.index("prediction_fixture_#{fixtures(:upcoming_group).id}")
    farther = response.body.index("prediction_fixture_#{later.id}")
    assert sooner && farther && sooner < farther,
           "expected the sooner kickoff to render before the later one"
  end

  test "past status shows kicked-off matches, most recent first, excludes upcoming" do
    sign_in_as users(:one)
    older = Fixture.create!(stadium: stadia(:azteca), kickoff_at: 10.days.ago,
                            stage: :group, home_team: teams(:spain), away_team: teams(:canada),
                            status: :finished, home_score: 1, away_score: 0, match_number: 98)
    get predictions_path(status: "past")

    assert_response :success
    assert_select "nav[aria-label=Status] a[aria-current=page]", text: "Past"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}", count: 0
    recent = response.body.index("prediction_fixture_#{fixtures(:finished_group).id}")
    older_pos = response.body.index("prediction_fixture_#{older.id}")
    assert recent && older_pos && recent < older_pos,
           "expected the more-recent kickoff to render before the older one"
  end

  test "unpredicted status shows open matches the player has not picked yet" do
    sign_in_as users(:two)
    get predictions_path(status: "unpredicted")

    assert_response :success
    assert_select "nav[aria-label=Status] a[aria-current=page]", text: "Unpredicted"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id}", count: 0
  end

  test "unpredicted status shows a tailored caught-up message when nothing is open" do
    sign_in_as users(:one)
    get predictions_path(status: "unpredicted")

    assert_response :success
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}", count: 0
    assert_match "all caught up", response.body
  end

  test "status and stage filters combine" do
    sign_in_as users(:two)
    get predictions_path(status: "past", stage: "group")

    assert_response :success
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id}"
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:upcoming_group).id}", count: 0
  end

  test "a finished knockout decided on penalties shows who advanced" do
    sign_in_as users(:one)
    Fixture.create!(stadium: stadia(:metlife), kickoff_at: 2.days.ago, stage: :sf,
                    match_number: 101, home_team: teams(:spain), away_team: teams(:canada),
                    status: :finished, home_score: 1, away_score: 1, penalty_winner: :home)

    get predictions_path

    assert_response :success
    assert_match "Spain win on penalties", response.body
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
    frame = "turbo-frame#prediction_fixture_#{ko.id}"
    assert_select "#{frame} form", count: 0
    assert_select "#{frame} input", count: 0
    assert_select frame, text: /Teams to be announced/
  end
end
