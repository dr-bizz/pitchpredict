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
    # Contract with leaderboard_highlight_controller.js: the layout exposes the
    # viewer's id and every row is addressable by user id.
    assert_select "meta[name='current-user-id'][content=?]", users(:two).id.to_s
    assert_select "#leaderboard-table[data-controller='leaderboard-highlight']"
    assert_select "tr[data-user-id=?]", users(:two).id.to_s, count: 1
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
    # The broadcast HTML still carries everything the Stimulus controller needs
    # to re-apply the viewer's highlight client-side.
    assert_includes html, 'data-controller="leaderboard-highlight"'
    assert_includes html, %(data-user-id="#{users(:two).id}")
    assert_includes html, "data-you-badge"
  end

  test "links other players' names to their predictions but not the viewer's own" do
    sign_in_as users(:two)
    get leaderboard_path

    assert_select "a[href=?]", user_predictions_path(users(:one))
    assert_select "a[href=?]", user_predictions_path(users(:two)), count: 0
  end

  test "podium links other players but not the viewer" do
    # The podium only renders with at least three players.
    User.create!(name: "User Three", email_address: "three@example.com", password: "password")
    sign_in_as users(:two)
    get leaderboard_path

    assert_select "section[aria-label='Top three players']" do
      assert_select "a[href=?]", user_predictions_path(users(:one))
      assert_select "a[href=?]", user_predictions_path(users(:two)), count: 0
    end
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
