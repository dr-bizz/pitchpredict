require "test_helper"

class LeaderboardsControllerTest < ActionDispatch::IntegrationTest
  test "redirects to sign in when unauthenticated" do
    get leaderboard_path
    assert_redirected_to new_session_path
  end

  test "renders the leaderboard with the broadcast target and stream subscription" do
    sign_in_as users(:two)
    get leaderboard_path

    assert_response :success
    assert_select "turbo-cable-stream-source[channel=?]", "Turbo::StreamsChannel"
    assert_select "#leaderboard-table"
    assert_select "#leaderboard-table tbody tr", count: User.count
    # users(:two) has the scored prediction (5 pts fixture data) so appears with points
    assert_select "tr[data-current-user='true']", count: 1
    assert_select "tr[data-current-user='true']", text: /You/
  end

  test "ranks users by total points with medal flair for the leader" do
    sign_in_as users(:one)
    get leaderboard_path

    assert_select "tbody tr:first-child", text: /🥇/
    assert_select "tr[data-current-user='true']", count: 1
  end

  test "table partial tolerates a nil current_user (broadcast case)" do
    html = ApplicationController.render(
      partial: "leaderboards/table",
      locals: { rows: LeaderboardService.new.rows, current_user: nil }
    )

    assert_includes html, 'id="leaderboard-table"'
    refute_includes html, 'data-current-user="true"'
  end

  test "table partial shows an empty state when there are no rows" do
    html = ApplicationController.render(
      partial: "leaderboards/table",
      locals: { rows: [], current_user: nil }
    )

    assert_includes html, 'id="leaderboard-table"'
    assert_includes html, "No standings yet"
  end
end
