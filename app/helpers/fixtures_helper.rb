module FixturesHelper
  # The predictions grid filters on two independent axes. STATUS filters by time
  # and prediction state; STAGE filters by tournament stage. Both default to
  # "all" and combine (e.g. Unpredicted + R16). Keys map to PredictionsGridQuery
  # statuses and Fixture.stages respectively.
  STATUS_TABS = {
    "all" => "All",
    "upcoming" => "Upcoming",
    "unpredicted" => "Unpredicted",
    "predicted" => "Predicted",
    "past" => "Past"
  }.freeze

  STAGE_TABS = {
    "all" => "All",
    "group" => "Groups",
    "r32" => "R32",
    "r16" => "R16",
    "qf" => "QF",
    "sf" => "SF",
    "third_place" => "3rd Place",
    "final" => "Final"
  }.freeze

  # Empty-state copy. "Unpredicted" gets tailored "all caught up" copy; every
  # other filter combination shares a neutral message.
  def empty_fixtures_message(status)
    if status == "unpredicted"
      "You're all caught up — every available match has a prediction."
    else
      "No matches match these filters."
    end
  end

  # Single source of truth for kickoff timestamps so every screen agrees.
  # NOTE: kickoff times are displayed in the app's default time zone (Eastern;
  # set in config/application.rb), matching the official 2026 schedule dates.
  # Per-user zones are out of scope, so the zone is labelled explicitly — the
  # tournament spans US/Canada/Mexico and an unlabelled "4:00 PM" is ambiguous.
  KICKOFF_FORMATS = {
    short: "%a %-d %b · %-I:%M %p",        # fixture cards, admin index
    long: "%A %-d %B %Y · %-I:%M %p"       # admin edit header
  }.freeze

  def kickoff_label(fixture, style: :short)
    "#{fixture.kickoff_at.in_time_zone.strftime(KICKOFF_FORMATS.fetch(style))} ET"
  end

  def stage_tab_classes(active)
    if active
      "rounded-full bg-pitch px-4 py-1.5 text-sm font-semibold text-white shadow-card"
    else
      "rounded-full bg-white px-4 py-1.5 text-sm font-medium text-charcoal/70 ring-1 ring-charcoal/10 hover:bg-pitch/5 hover:text-pitch"
    end
  end
end
