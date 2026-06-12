require "test_helper"

class FixturesControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get predictions_path

    assert_redirected_to new_session_path
  end

  test "shows the group stage by default with group headings and per-fixture frames" do
    sign_in_as users(:one)
    get predictions_path

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
    get predictions_path

    assert_select "span.pill-predicted", text: "Predicted"
    assert_select "input[name='prediction[home_score]'][value='2']"
  end

  test "finished fixtures show the actual score, locked inputs and the points pill" do
    sign_in_as users(:two)
    get predictions_path

    assert_response :success
    assert_match "2 – 1", response.body
    assert_select "span.pill-points", text: "+5 pts"
    assert_select "input[disabled]"
    # A finished fixture renders no form for the locked card.
    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} form", count: 0
  end

  test "finished fixture without a prediction shows the No prediction pill" do
    sign_in_as users(:one)
    get predictions_path

    assert_select "turbo-frame#prediction_fixture_#{fixtures(:finished_group).id} span.pill-muted",
                  text: "No prediction"
  end

  test "filters fixtures by stage with an empty state" do
    sign_in_as users(:one)
    get predictions_path(stage: "final")

    assert_response :success
    assert_select "a[aria-current=page]", text: "Final"
    assert_match "No fixtures scheduled", response.body
  end

  test "falls back to the group stage for unknown stage params" do
    sign_in_as users(:one)
    get predictions_path(stage: "bogus")

    assert_response :success
    assert_select "a[aria-current=page]", text: "Groups"
    assert_select "h2", text: "Group A"
  end
end
