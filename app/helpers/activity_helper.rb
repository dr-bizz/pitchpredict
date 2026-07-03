# Presentation tiers for ActivityFeedService items: which emoji and hype line
# a feed row earns. Data stays in the service; fun lives here.
module ActivityHelper
  Tier = Data.define(:emoji, :you, :other)

  # Milestone (descending) => tier; a streak gets the highest milestone it has
  # reached. Exact streaks get a visibly flashier ladder than outcome streaks.
  OUTCOME_STREAK_TIERS = {
    10 => Tier.new(emoji: "👑", you: "You're a legend!", other: "An absolute legend!"),
    8  => Tier.new(emoji: "⭐", you: "You're a star!", other: "A star performance!"),
    6  => Tier.new(emoji: "🔥", you: "You're on fire!", other: "On fire!"),
    4  => Tier.new(emoji: "💯", you: "You're killing the prediction game!", other: "Killing the prediction game!"),
    2  => Tier.new(emoji: "🎯", you: "Right on target!", other: "Right on target!")
  }.freeze

  EXACT_STREAK_TIERS = {
    10 => Tier.new(emoji: "🐐", you: "You ARE the future.", other: "The GOAT. Simply the GOAT."),
    8  => Tier.new(emoji: "🌟", you: "Superstar! Nothing gets past you!", other: "Superstar stuff!"),
    6  => Tier.new(emoji: "🧙", you: "Actual wizardry!", other: "Actual wizardry!"),
    4  => Tier.new(emoji: "🔮", you: "Do you know the future??", other: "Do they know the future??"),
    2  => Tier.new(emoji: "🎯🎯", you: "Back-to-back bullseyes!", other: "Back-to-back bullseyes!")
  }.freeze

  EXACT_HIT_TIER = Tier.new(emoji: "👏", you: "What a call!", other: "What a call!").freeze

  def activity_emoji(item)
    activity_tier(item).emoji
  end

  def activity_hype(item, you:)
    tier = activity_tier(item)
    you ? tier.you : tier.other
  end

  def activity_badge(item)
    if item.type == :exact_hit
      "🎯 +#{item.points}"
    else
      "#{activity_emoji(item)} #{item.count}"
    end
  end

  private

  def activity_tier(item)
    case item.type
    when :outcome_streak then streak_tier(OUTCOME_STREAK_TIERS, item.count)
    when :exact_streak   then streak_tier(EXACT_STREAK_TIERS, item.count)
    when :exact_hit      then EXACT_HIT_TIER
    else raise ArgumentError, "unknown activity item type: #{item.type.inspect}"
    end
  end

  # Milestones are keyed descending, so the first one the count clears is the
  # highest reached. The service never emits streaks below the lowest milestone.
  def streak_tier(tiers, count)
    tiers.each_pair { |milestone, tier| return tier if count >= milestone }
    raise ArgumentError, "streak of #{count} is below the lowest milestone"
  end
end
