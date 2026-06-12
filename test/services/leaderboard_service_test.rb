require "test_helper"

class LeaderboardServiceTest < ActiveSupport::TestCase
  setup do
    # Make the fixture data self-consistent: rescore the finished fixture so
    # two_finished's stale points_awarded (5) becomes the real value (4, exact).
    ScoringService.score_fixture!(fixtures(:finished_group))
  end

  test "returns one row per user with totals and per-kind counts" do
    rows = LeaderboardService.new.rows

    assert_equal User.count, rows.size

    two = rows.find { |row| row.user == users(:two) }
    assert_equal 1, two.rank
    assert_equal 4, two.total_points
    assert_equal 1, two.predictions_count
    assert_equal 1, two.exact_count
    assert_equal 0, two.diff_count
    assert_equal 0, two.tendency_count

    one = rows.find { |row| row.user == users(:one) }
    assert_equal 2, one.rank
    assert_equal 0, one.total_points
    assert_equal 1, one.predictions_count # unscored prediction still counts
    assert_equal 0, one.exact_count
  end

  test "includes the champion bonus once the final is finished" do
    # users(:two) picked brazil; make brazil win the final.
    Fixture.create!(
      home_team: teams(:brazil), away_team: teams(:france), stadium: stadia(:azteca),
      kickoff_at: 1.day.ago, stage: :final, status: :finished, home_score: 2, away_score: 0
    )

    two = LeaderboardService.new.rows.find { |row| row.user == users(:two) }
    assert_equal 4 + ScoringService::CHAMPION_BONUS, two.total_points
  end

  test "applies standard competition ranking on equal points" do
    predictions(:one_upcoming).update!(points_awarded: 4) # tie users one and two on 4
    third = User.create!(name: "User Three", email_address: "three@example.com", password: "password")

    rows = LeaderboardService.new.rows

    assert_equal [ 1, 1, 3 ], rows.map(&:rank)
    assert_equal [ 4, 4, 0 ], rows.map(&:total_points)
    assert_equal third, rows.last.user
  end

  # NOTE: the test environment uses :null_store, so these caching tests swap in
  # a MemoryStore to exercise the real fetch/expire behavior.
  test "fetch_rows serves cached rows until expire_rows is called" do
    with_memory_cache do
      first = LeaderboardService.fetch_rows
      assert_equal 4, first.find { |row| row.user == users(:two) }.total_points

      # Change points behind the cache's back (update_columns skips callbacks).
      predictions(:two_finished).update_columns(points_awarded: 0)
      cached = LeaderboardService.fetch_rows
      assert_equal 4, cached.find { |row| row.user == users(:two) }.total_points

      LeaderboardService.expire_rows
      fresh = LeaderboardService.fetch_rows
      assert_equal 0, fresh.find { |row| row.user == users(:two) }.total_points
    end
  end

  test "saving a prediction or creating a user expires the cached rows" do
    with_memory_cache do
      LeaderboardService.fetch_rows
      predictions(:one_upcoming).update!(home_score: 5) # after_commit expires
      assert_nil Rails.cache.read(LeaderboardService::CACHE_KEY)

      LeaderboardService.fetch_rows
      User.create!(name: "Newbie", email_address: "new@example.com", password: "password")
      assert_nil Rails.cache.read(LeaderboardService::CACHE_KEY)
    end
  end

  test "runs a constant number of queries regardless of user count" do
    3.times { |i| User.create!(name: "U#{i}", email_address: "u#{i}@example.com", password: "password") }

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      LeaderboardService.new.rows
    end

    assert_operator queries, :<=, 3, "expected no N+1 (got #{queries} queries)"
  end

  private

  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end
end
