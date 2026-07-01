require "test_helper"

class UserPredictionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @viewer = users(:one)
    @target = users(:two)
    @locked_fixture = fixtures(:finished_group)  # Brazil 2–1 France, finished (locked)
    @open_fixture = fixtures(:upcoming_group)     # Spain v Canada, scheduled (open)
  end

  test "requires authentication" do
    get user_predictions_path(@target)
    assert_redirected_to new_session_path
  end

  test "returns 404 for an unknown user" do
    sign_in_as @viewer
    get user_predictions_path(id: 999_999)
    assert_response :not_found
  end

  test "shows the target's prediction, the result and the points for a locked match" do
    sign_in_as @viewer
    get user_predictions_path(@target)

    assert_response :success
    assert_match "User Two", response.body  # whose predictions we're viewing
    assert_match "Brazil", response.body    # the locked fixture is shown
    assert_match "2–1", response.body       # their pick and the actual result
    assert_match "+5", response.body        # points earned (two_finished fixture)
  end

  test "never reveals the target's prediction on a match still open to predict" do
    # The target has an OPEN prediction. It must never appear on a foreign view —
    # this is the anti-cheat boundary.
    @target.predictions.create!(fixture: @open_fixture, home_score: 1, away_score: 1)

    sign_in_as @viewer
    get user_predictions_path(@target, stage: "group")

    assert_response :success
    assert_match "Brazil", response.body   # locked group match present
    refute_match "Canada", response.body   # open group match absent entirely
  end

  test "shows the viewer's own prediction head-to-head" do
    # Seed the viewer's pick on the locked match, bypassing the kickoff lock that
    # a normal save would reject (YAML fixtures bypass validations the same way).
    own = @viewer.predictions.build(fixture: @locked_fixture, home_score: 0, away_score: 3)
    own.save!(validate: false)

    sign_in_as @viewer
    get user_predictions_path(@target)

    assert_response :success
    assert_match "User Two", response.body  # the target's column
    assert_match "0–3", response.body       # the viewer's own pick
  end

  test "a viewed prediction shows the picked penalty advancer" do
    ko = Fixture.create!(stadium: stadia(:metlife), kickoff_at: 2.days.ago, stage: :r16, match_number: 89,
                         home_team: teams(:spain), away_team: teams(:canada),
                         status: :finished, home_score: 1, away_score: 1, penalty_winner: :away)
    pick = @target.predictions.build(fixture: ko, home_score: 1, away_score: 1, penalty_winner: :away)
    pick.save!(validate: false)

    sign_in_as @viewer
    get user_predictions_path(@target, stage: "r16")

    assert_response :success
    assert_match "Canada on pens", response.body     # fixture result: Canada won on penalties
    assert_match "(Canada pens)", response.body      # the target's pick called Canada
  end

  test "defaults to the Past tab and marks it current" do
    sign_in_as @viewer
    get user_predictions_path(@target)
    assert_select "a[aria-current=page]", text: "Past"
  end

  test "comparison card is read-only — no form, inputs or submit path" do
    html = ApplicationController.render(
      partial: "user_predictions/comparison_card",
      locals: {
        fixture: @locked_fixture,
        owner: @target,
        owner_prediction: predictions(:two_finished),
        viewer_prediction: nil
      }
    )

    assert_includes html, "User Two"       # owner column label
    assert_includes html, "No prediction"  # viewer column (nil prediction)
    refute_includes html, "<form"
    refute_includes html, "<input"
    refute_includes html, "fixture_prediction"
  end
end
