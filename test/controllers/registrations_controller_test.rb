require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_registration_url
    assert_response :success
  end

  test "signup creates a player user and logs them in" do
    assert_difference("User.count", 1) do
      post registration_url, params: { user: {
        name: "New Player",
        email_address: "new@example.com",
        password: "secret123",
        password_confirmation: "secret123"
      } }
    end

    user = User.find_by!(email_address: "new@example.com")
    assert user.player?
    assert_equal 1, user.sessions.count
    assert cookies[:session_id].present?
    assert_redirected_to root_url
  end

  test "signup with missing name re-renders form" do
    assert_no_difference("User.count") do
      post registration_url, params: { user: {
        name: "",
        email_address: "new@example.com",
        password: "secret123",
        password_confirmation: "secret123"
      } }
    end

    assert_response :unprocessable_entity
  end
end
