# Builds the ranked leaderboard in two queries total (one grouped aggregate
# over users+predictions, one pluck for champion picks) — no N+1.
class LeaderboardService
  Row = Data.define(:rank, :user, :total_points, :predictions_count, :exact_count, :diff_count, :tendency_count)

  # Returns an array of Row, ordered by total points (champion bonus included
  # once the final is finished) with standard competition ranking ("1224") on
  # equal points. NOTE: assumption — ties share a rank based on total points
  # only; the secondary ordering (exact count desc, then name asc) is for a
  # stable display order and does not affect rank.
  def rows
    bonus_user_ids = champion_bonus_user_ids

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

  def aggregated_users
    User.left_joins(:predictions).group("users.id").select(
      "users.*",
      "COALESCE(SUM(predictions.points_awarded), 0) AS prediction_points",
      "COUNT(predictions.id) AS predictions_count",
      count_where("predictions.points_awarded = #{ScoringService::EXACT_POINTS}", as: "exact_count"),
      count_where("predictions.points_awarded = #{ScoringService::DIFFERENCE_POINTS}", as: "diff_count"),
      count_where("predictions.points_awarded = #{ScoringService::TENDENCY_POINTS}", as: "tendency_count")
    )
  end

  def count_where(condition, as:)
    "COALESCE(SUM(CASE WHEN #{condition} THEN 1 ELSE 0 END), 0) AS #{as}"
  end

  # See ScoringService.champion_team_id for the bonus representation decision.
  def champion_bonus_user_ids
    champion_id = ScoringService.champion_team_id
    return Set.new if champion_id.nil?

    ChampionPick.where(team_id: champion_id).pluck(:user_id).to_set
  end
end
