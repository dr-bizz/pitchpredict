# Derives the dashboard "Recent activity" feed from scored predictions at read
# time — no persisted events. Mirrors LeaderboardService's cached-service
# pattern (short-TTL safety net + eager expiry from the same call sites).
class ActivityFeedService
  Item = Data.define(:type, :user, :count, :fixture, :points)

  CACHE_KEY = "activity/items"
  CACHE_TTL = 1.minute
  STREAK_MIN = 3
  RECENT_WINDOW = 72.hours
  MAX_ITEMS = 6

  # Highest first: an exact streak beats an outcome streak beats a one-off hit.
  TYPE_PRIORITY = { exact_streak: 0, outcome_streak: 1, exact_hit: 2 }.freeze

  def self.fetch_items
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new.items }
  end

  def self.expire_items
    Rails.cache.delete(CACHE_KEY)
  end

  # One Item per user (their best), ordered by type priority, then streak
  # length, then recency; capped at MAX_ITEMS.
  def items
    cutoff = RECENT_WINDOW.ago

    best = scored_predictions_by_user.filter_map do |_user_id, predictions|
      best_item_for(predictions, cutoff)
    end

    best.sort_by { |item| [ TYPE_PRIORITY.fetch(item.type), -item.count.to_i, -item.fixture.kickoff_at.to_i ] }
        .first(MAX_ITEMS)
  end

  private

  # Scored predictions on finished fixtures, kickoff-ordered per user.
  def scored_predictions_by_user
    Prediction.joins(:fixture)
              .where(fixtures: { status: Fixture.statuses[:finished] })
              .where.not(points_awarded: nil)
              .includes(:user, fixture: %i[home_team away_team])
              .sort_by { |prediction| prediction.fixture.kickoff_at }
              .group_by(&:user_id)
  end

  def best_item_for(predictions, cutoff)
    streak_item(predictions, cutoff) || exact_hit_item(predictions, cutoff)
  end

  # A streak is only shown while it is alive: the user's most recent scored
  # prediction is part of it and kicked off within the recent window.
  def streak_item(predictions, cutoff)
    last = predictions.last
    return nil if last.fixture.kickoff_at < cutoff

    exact = trailing_count(predictions) { |p| p.points_awarded == ScoringService::EXACT_POINTS }
    outcome = trailing_count(predictions) { |p| p.points_awarded.positive? }

    if exact >= STREAK_MIN
      Item.new(type: :exact_streak, user: last.user, count: exact, fixture: last.fixture, points: nil)
    elsif outcome >= STREAK_MIN
      Item.new(type: :outcome_streak, user: last.user, count: outcome, fixture: last.fixture, points: nil)
    end
  end

  # A one-off exact hit is anchored on the exact-hit fixture itself, so it
  # stays in the feed for the whole recent window even when later scored
  # fixtures follow it. Most recent exact score wins.
  def exact_hit_item(predictions, cutoff)
    hit = predictions.reverse_each.find do |p|
      p.fixture.kickoff_at >= cutoff && p.points_awarded == ScoringService::EXACT_POINTS
    end
    return nil unless hit

    Item.new(type: :exact_hit, user: hit.user, count: nil, fixture: hit.fixture,
             points: ScoringService::EXACT_POINTS)
  end

  # Length of the run satisfying the block, counting back from the last
  # (most recent) prediction.
  def trailing_count(predictions, &block)
    predictions.reverse_each.take_while(&block).count
  end
end
