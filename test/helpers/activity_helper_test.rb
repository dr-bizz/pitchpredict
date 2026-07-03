require "test_helper"

class ActivityHelperTest < ActionView::TestCase
  def item(type, count: nil, points: nil)
    ActivityFeedService::Item.new(type: type, user: users(:one), count: count,
                                  fixture: fixtures(:finished_group), points: points)
  end

  test "outcome streak ladder escalates at 2, 4, 6, 8 and 10" do
    { 2 => "🎯", 3 => "🎯", 4 => "💯", 5 => "💯", 6 => "🔥", 7 => "🔥",
      8 => "⭐", 9 => "⭐", 10 => "👑", 15 => "👑" }.each do |count, emoji|
      assert_equal emoji, activity_emoji(item(:outcome_streak, count: count)),
                   "outcome streak of #{count}"
    end
  end

  test "exact streak ladder is flashier than the outcome ladder" do
    { 2 => "🎯🎯", 4 => "🔮", 6 => "🧙", 8 => "🌟", 10 => "🐐", 15 => "🐐" }
      .each do |count, emoji|
      assert_equal emoji, activity_emoji(item(:exact_streak, count: count)),
                   "exact streak of #{count}"
    end
  end

  test "a one-off exact hit gets the clap" do
    assert_equal "👏", activity_emoji(item(:exact_hit, points: 4))
  end

  test "hype copy speaks to you in the second person" do
    assert_equal "You're on fire!", activity_hype(item(:outcome_streak, count: 6), you: true)
    assert_equal "Do you know the future??", activity_hype(item(:exact_streak, count: 4), you: true)
  end

  test "hype copy about other players avoids the second person" do
    assert_equal "On fire!", activity_hype(item(:outcome_streak, count: 6), you: false)
    assert_equal "Do they know the future??", activity_hype(item(:exact_streak, count: 4), you: false)
  end

  test "exact hit hype is the same for everyone" do
    hit = item(:exact_hit, points: 4)

    assert_equal "What a call!", activity_hype(hit, you: true)
    assert_equal "What a call!", activity_hype(hit, you: false)
  end

  test "badges show the tier emoji with the count or points" do
    assert_equal "👑 12", activity_badge(item(:outcome_streak, count: 12))
    assert_equal "🔮 4", activity_badge(item(:exact_streak, count: 4))
    assert_equal "🎯 +4", activity_badge(item(:exact_hit, points: 4))
  end
end
