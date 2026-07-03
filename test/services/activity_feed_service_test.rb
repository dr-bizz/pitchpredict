require "test_helper"

class ActivityFeedServiceTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  # Creates a finished, scored knockout-free fixture `days_ago` and a scored
  # prediction on it for `user`. Bypasses validations like production scoring
  # does (fixtures are past kickoff).
  def scored_prediction(user, points:, days_ago:, match_number:)
    fixture = Fixture.create!(home_team: teams(:brazil), away_team: teams(:france),
      stadium: stadia(:azteca), kickoff_at: days_ago.days.ago, stage: :group,
      status: :finished, home_score: 2, away_score: 1, match_number: match_number)
    prediction = Prediction.new(user: user, fixture: fixture,
      home_score: 2, away_score: 1, points_awarded: points)
    prediction.save!(validate: false)
    prediction
  end

  test "reports an outcome streak of 3+ scored matches" do
    user = users(:one)
    scored_prediction(user, points: 2, days_ago: 2, match_number: 201)
    scored_prediction(user, points: 3, days_ago: 1, match_number: 202)
    scored_prediction(user, points: 2, days_ago: 0.5, match_number: 203)

    item = ActivityFeedService.new.items.find { |i| i.user.id == user.id }

    assert_equal :outcome_streak, item.type
    assert_equal 3, item.count
  end

  test "an exact streak outranks the outcome streak for the same user" do
    user = users(:one)
    scored_prediction(user, points: 4, days_ago: 2, match_number: 201)
    scored_prediction(user, points: 4, days_ago: 1, match_number: 202)
    scored_prediction(user, points: 4, days_ago: 0.5, match_number: 203)

    items = ActivityFeedService.new.items

    assert_equal [ :exact_streak ], items.select { |i| i.user.id == user.id }.map(&:type)
    assert_equal 3, items.first.count
  end

  test "a zero-point result breaks a streak" do
    user = users(:one)
    scored_prediction(user, points: 2, days_ago: 3, match_number: 201)
    scored_prediction(user, points: 2, days_ago: 2, match_number: 202)
    scored_prediction(user, points: 0, days_ago: 1, match_number: 203)

    assert_not ActivityFeedService.new.items.any? { |i| i.user.id == user.id && i.type != :exact_hit }
  end

  test "a recent exact score shows as an exact hit when there is no streak" do
    user = users(:one)
    scored_prediction(user, points: 4, days_ago: 1, match_number: 201)

    item = ActivityFeedService.new.items.find { |i| i.user.id == user.id }

    assert_equal :exact_hit, item.type
    assert_equal ScoringService::EXACT_POINTS, item.points
  end

  test "an exact hit still shows when a later scored fixture follows it" do
    user = users(:one)
    exact = scored_prediction(user, points: 4, days_ago: 1, match_number: 201)
    scored_prediction(user, points: 2, days_ago: 0.5, match_number: 202)

    item = ActivityFeedService.new.items.find { |i| i.user.id == user.id }

    assert_equal :exact_hit, item.type
    assert_equal exact.fixture, item.fixture
    assert_equal ScoringService::EXACT_POINTS, item.points
  end

  test "exact hits outside the recent window are not resurfaced by newer results" do
    user = users(:one)
    scored_prediction(user, points: 4, days_ago: 5, match_number: 201)
    scored_prediction(user, points: 2, days_ago: 1, match_number: 202)

    assert_empty ActivityFeedService.new.items.select { |i| i.user.id == user.id }
  end

  test "streaks anchored on old fixtures are not recent activity" do
    user = users(:one)
    scored_prediction(user, points: 2, days_ago: 10, match_number: 201)
    scored_prediction(user, points: 2, days_ago: 9, match_number: 202)
    scored_prediction(user, points: 2, days_ago: 8, match_number: 203)

    assert_empty ActivityFeedService.new.items.select { |i| i.user.id == user.id }
  end

  test "caps the feed at MAX_ITEMS with one item per user" do
    User.transaction do
      7.times do |n|
        user = User.create!(name: "Player #{n}", email_address: "p#{n}@example.com", password: "password123")
        scored_prediction(user, points: 4, days_ago: 1, match_number: 300 + n)
      end
    end

    items = ActivityFeedService.new.items

    assert_operator items.size, :<=, ActivityFeedService::MAX_ITEMS
    assert_equal items.map { |i| i.user.id }.uniq.size, items.size
  end

  test "fetch_items caches and expire_items clears" do
    assert_equal ActivityFeedService.fetch_items, ActivityFeedService.fetch_items
    ActivityFeedService.expire_items # must not raise; cache key dropped
  end

  test "saving a prediction expires the cached feed" do
    # The test env cache store is :null_store, which never keeps anything, so
    # this test would pass vacuously against it. Swap in a real store to prove
    # the after_commit hook actually drops the stale cached feed.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    user = users(:one)
    scored_prediction(user, points: 4, days_ago: 1, match_number: 210)
    assert ActivityFeedService.fetch_items.any? { |i| i.user.id == user.id }

    # Rescoring to 0 must drop the cached exact hit once the cache is expired
    # by the save (production path: ScoreFixtureJob rescoring a correction).
    Prediction.last.update!(points_awarded: 0)

    assert_not ActivityFeedService.fetch_items.any? { |i| i.user.id == user.id && i.type == :exact_hit }
  ensure
    Rails.cache = original_cache
  end
end
