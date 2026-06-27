module UserPredictionsHelper
  # Tabs for the read-only "another player's predictions" view: the owner grid's
  # stage tabs (single source of truth in FixturesHelper) minus the editing-only
  # "upcoming" tab, with a leading "past" catch-all for all locked matches.
  PREDICTION_TABS = { "past" => "Past" }.merge(FixturesHelper::STAGE_TABS.except("upcoming")).freeze

  # Maps a prediction's points_awarded to a short outcome tier + badge colour.
  # Unknown values (or nil = not yet scored) yield no label.
  PREDICTION_OUTCOMES = {
    ScoringService::EXACT_POINTS      => [ "Exact",    "badge-success" ],
    ScoringService::DIFFERENCE_POINTS => [ "Diff",     "badge-info" ],
    ScoringService::TENDENCY_POINTS   => [ "Tendency", "badge-warning" ],
    0                                 => [ "Miss",     "badge-ghost" ]
  }.freeze

  def prediction_outcome_label(points)
    PREDICTION_OUTCOMES.dig(points, 0)
  end

  def prediction_outcome_badge_class(points)
    PREDICTION_OUTCOMES.dig(points, 1) || "badge-warning"
  end
end
