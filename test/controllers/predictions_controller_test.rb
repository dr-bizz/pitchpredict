require "test_helper"

class PredictionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @open_fixture = fixtures(:upcoming_group)
    @locked_fixture = fixtures(:finished_group)
  end

  test "requires authentication" do
    post fixture_prediction_path(@open_fixture), params: { prediction: { home_score: 1, away_score: 1 } }

    assert_redirected_to new_session_path
  end

  test "creates a prediction for an open fixture and re-renders the card frame" do
    sign_in_as users(:two)

    assert_difference "Prediction.count", 1 do
      post fixture_prediction_path(@open_fixture), params: { prediction: { home_score: 3, away_score: 1 } }
    end

    assert_response :success
    assert_select "turbo-frame#prediction_fixture_#{@open_fixture.id}"
    assert_select "span.badge.badge-success", text: "Predicted"
    assert_match "Saved", response.body

    prediction = users(:two).predictions.find_by!(fixture: @open_fixture)
    assert_equal [ 3, 1 ], [ prediction.home_score, prediction.away_score ]
  end

  test "create against an already-predicted fixture updates it instead of failing" do
    sign_in_as users(:one)

    assert_no_difference "Prediction.count" do
      post fixture_prediction_path(@open_fixture), params: { prediction: { home_score: 4, away_score: 4 } }
    end

    assert_response :success
    prediction = predictions(:one_upcoming).reload
    assert_equal [ 4, 4 ], [ prediction.home_score, prediction.away_score ]
  end

  test "updates an existing prediction" do
    sign_in_as users(:one)

    patch fixture_prediction_path(@open_fixture), params: { prediction: { home_score: 0, away_score: 2 } }

    assert_response :success
    prediction = predictions(:one_upcoming).reload
    assert_equal [ 0, 2 ], [ prediction.home_score, prediction.away_score ]
  end

  test "rejects creating a prediction once the fixture is locked" do
    sign_in_as users(:one)

    assert_no_difference "Prediction.count" do
      post fixture_prediction_path(@locked_fixture), params: { prediction: { home_score: 1, away_score: 0 } }
    end

    assert_response :unprocessable_entity
    assert_match "locked", response.body
  end

  test "rejects updating a prediction once the fixture is locked" do
    sign_in_as users(:two)

    patch fixture_prediction_path(@locked_fixture), params: { prediction: { home_score: 9, away_score: 9 } }

    assert_response :unprocessable_entity
    prediction = predictions(:two_finished).reload
    assert_equal [ 2, 1 ], [ prediction.home_score, prediction.away_score ]
  end

  test "rejects out-of-range scores" do
    sign_in_as users(:two)

    assert_no_difference "Prediction.count" do
      post fixture_prediction_path(@open_fixture), params: { prediction: { home_score: 99, away_score: 0 } }
    end

    assert_response :unprocessable_entity
  end

  test "returns 404 for an unknown fixture" do
    sign_in_as users(:one)

    post fixture_prediction_path(fixture_id: 999_999), params: { prediction: { home_score: 1, away_score: 1 } }

    assert_response :not_found
  end
end
