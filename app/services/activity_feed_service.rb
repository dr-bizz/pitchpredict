# Derives the dashboard "Recent activity" feed from scored predictions at read
# time — no persisted events. Mirrors LeaderboardService's cached-service
# pattern (short-TTL safety net + eager expiry from the same call sites).
class ActivityFeedService
  Item = Data.define(:type, :user, :count, :fixture, :points)

  CACHE_KEY = "activity/items"
  CACHE_TTL = 1.minute
  STREAK_MIN = 2
  RECENT_WINDOW = 72.hours
  MAX_ITEMS = 6

  # Feed ordering weight: exact streaks tower over everything, outcome streaks
  # rank by length, and a one-off exact hit is worth a 4-long outcome streak —
  # more impressive than the trivial 2–3 streaks, but no match for a long run.
  EXACT_STREAK_BONUS = 100
  EXACT_HIT_WEIGHT = 4

  def self.fetch_items
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new.items }
  end

  def self.expire_items
    Rails.cache.delete(CACHE_KEY)
  end

  # One Item per user (their best), heaviest first, recency as tie-break;
  # capped at MAX_ITEMS.
  def items
    cutoff = RECENT_WINDOW.ago

    best = scored_predictions_by_user.filter_map do |_user_id, predictions|
      best_item_for(predictions, cutoff)
    end

    best.sort_by { |item| [ -weight(item), -item.fixture.kickoff_at.to_i ] }
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

  def weight(item)
    case item.type
    when :exact_streak then EXACT_STREAK_BONUS + item.count
    when :outcome_streak then item.count
    else EXACT_HIT_WEIGHT
    end
  end

  # A user's best item is their heaviest, judged by the same feed weights: an
  # exact hit outweighs the short outcome streak it would otherwise start, but
  # not a long run. Ties go to the earlier (more special) candidate.
  def best_item_for(predictions, cutoff)
    [ exact_streak_item(predictions, cutoff),
      exact_hit_item(predictions, cutoff),
      outcome_streak_item(predictions, cutoff) ].compact.max_by { |item| weight(item) }
  end

  # A streak is only shown while it is alive: the user's most recent scored
  # prediction is part of it and kicked off within the recent window.
  def exact_streak_item(predictions, cutoff)
    streak_item(predictions, cutoff, :exact_streak) { |p| p.points_awarded == ScoringService::EXACT_POINTS }
  end

  def outcome_streak_item(predictions, cutoff)
    streak_item(predictions, cutoff, :outcome_streak) { |p| p.points_awarded.positive? }
  end

  def streak_item(predictions, cutoff, type, &hit)
    last = predictions.last
    return nil if last.fixture.kickoff_at < cutoff

    count = trailing_count(predictions, &hit)
    return nil if count < STREAK_MIN

    Item.new(type: type, user: last.user, count: count, fixture: last.fixture, points: nil)
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
