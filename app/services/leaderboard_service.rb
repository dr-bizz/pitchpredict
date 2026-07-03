# Builds a ranked leaderboard in two queries (one grouped aggregate over
# users+predictions, one pluck for champion picks) — no N+1.
#
# Two board variants share this code:
#   :overall — the whole tournament, with the champion bonus.
#   :r16     — Round-of-16-onward fixtures only (stage >= r16, so group AND the
#              Round of 32 are excluded), with NO champion bonus.
class LeaderboardService
  Row = Data.define(:rank, :user, :total_points, :predictions_count, :exact_count, :diff_count, :tendency_count)

  # min_stage: nil means "all stages". champion_bonus toggles the final-winner
  # +10. Referencing Fixture.stages[:r16] keeps the floor in sync with the enum.
  VARIANTS = {
    overall: { min_stage: nil, champion_bonus: true },
    r16: { min_stage: Fixture.stages[:r16], champion_bonus: false }
  }.freeze

  CACHE_KEY = "leaderboard/rows"
  # NOTE: short TTL is only a safety net — Prediction/User after_commit hooks
  # and ScoreFixtureJob expire the keys eagerly on every relevant change.
  CACHE_TTL = 1.minute

  # Cached entry point used by the leaderboard page and the broadcast job.
  # Backed by Solid Cache, so each board is computed once per change (or per
  # minute) instead of on every page view. Keys are per-variant.
  def self.fetch_rows(variant: :overall)
    config = VARIANTS.fetch(variant)
    Rails.cache.fetch("#{CACHE_KEY}/#{variant}", expires_in: CACHE_TTL) { new(**config).rows }
  end

  # Expire every variant. A single prediction/result change can affect either
  # board, and recomputing an unaffected board just reproduces identical rows,
  # so we clear all keys rather than reason about which board changed.
  def self.expire_rows
    VARIANTS.each_key { |variant| Rails.cache.delete("#{CACHE_KEY}/#{variant}") }
  end

  def initialize(min_stage: nil, champion_bonus: true)
    @min_stage = min_stage
    @champion_bonus = champion_bonus
  end

  # Returns an array of Row, ordered by total points (champion bonus included
  # once the final is finished, when this variant awards it) with standard
  # competition ranking ("1224") on equal points. NOTE: assumption — ties share
  # a rank based on total points only; the secondary ordering (exact count desc,
  # then name asc) is for a stable display order and does not affect rank.
  def rows
    bonus_user_ids = @champion_bonus ? champion_bonus_user_ids : Set.new

    ranked = aggregated_users.map do |user|
      bonus = bonus_user_ids.include?(user.id) ? ScoringService::CHAMPION_BONUS : 0
      { user: user, total_points: user.prediction_points + bonus }
    end

    ranked.sort_by! { |row| [ -row[:total_points], -row[:user].exact_count, row[:user].name ] }

    previous = nil
    ranked.each_with_index.map do |row, index|
      rank = (previous && previous[:total_points] == row[:total_points]) ? previous[:rank] : index + 1
      previous = { total_points: row[:total_points], rank: rank }

      user = row[:user]
      Row.new(
        rank: rank,
        user: user,
        total_points: row[:total_points],
        predictions_count: user.predictions_count,
        exact_count: user.exact_count,
        diff_count: user.diff_count,
        tendency_count: user.tendency_count
      )
    end
  end

  private

  # The overall board keeps its lean predictions-only join (the hot path). The
  # r16 board also joins the fixture so aggregates can be gated by stage.
  def aggregated_users
    relation = @min_stage ? User.left_joins(predictions: :fixture) : User.left_joins(:predictions)
    relation.group("users.id").select(
      "users.*",
      sum_where("predictions.points_awarded", as: "prediction_points"),
      count_where("predictions.id IS NOT NULL", as: "predictions_count"),
      count_where("predictions.points_awarded = #{ScoringService::EXACT_POINTS}", as: "exact_count"),
      count_where("predictions.points_awarded = #{ScoringService::DIFFERENCE_POINTS}", as: "diff_count"),
      count_where("predictions.points_awarded = #{ScoringService::TENDENCY_POINTS}", as: "tendency_count")
    )
  end

  # SQL predicate limiting aggregates to in-scope fixtures, or nil for "all".
  # Gating lives inside the SUM/COUNT CASE expressions (below), never in a WHERE,
  # so a player with no in-scope predictions still appears with a correct 0
  # rather than being dropped by the join.
  def stage_gate
    "fixtures.stage >= #{@min_stage.to_i}" if @min_stage
  end

  # SUM(expr) over in-scope predictions; 0 when there are none.
  def sum_where(expr, as:)
    inner = stage_gate ? "CASE WHEN #{stage_gate} THEN #{expr} END" : expr
    "COALESCE(SUM(#{inner}), 0) AS #{as}"
  end

  # Count of in-scope predictions matching condition; 0 when there are none.
  def count_where(condition, as:)
    full = [ stage_gate, condition ].compact.join(" AND ")
    "COALESCE(SUM(CASE WHEN #{full} THEN 1 ELSE 0 END), 0) AS #{as}"
  end

  # See ScoringService.champion_team_id for the bonus representation decision.
  def champion_bonus_user_ids
    champion_id = ScoringService.champion_team_id
    return Set.new if champion_id.nil?

    ChampionPick.where(team_id: champion_id).pluck(:user_id).to_set
  end
end
