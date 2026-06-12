require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  # The prediction grid labels its score inputs and stepper buttons with
  # aria-label, so let fill_in/click_on match on it.
  Capybara.enable_aria_label = true

  # Sign in through the real form so the browser session gets the cookie
  # (the cookie-jar trick in SessionTestHelper only works for integration tests).
  def sign_in_through_ui(user, password: "password")
    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: password
    click_button "Sign in" # the nav bar also has a "Sign in" link
    assert_current_path root_path
  end
end
