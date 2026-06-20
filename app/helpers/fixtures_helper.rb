module FixturesHelper
  # Tab order + labels for the predictions grid. "upcoming", "unpredicted" and
  # "past" are virtual tabs (filtered by time/prediction status rather than
  # stage); the rest match Fixture.stages.
  STAGE_TABS = {
    "upcoming" => "Upcoming",
    "unpredicted" => "Unpredicted",
    "past" => "Past",
    "group" => "Groups",
    "r32" => "R32",
    "r16" => "R16",
    "qf" => "QF",
    "sf" => "SF",
    "third_place" => "3rd Place",
    "final" => "Final"
  }.freeze

  # Empty-state copy per tab. Each virtual tab gets tailored copy; every real
  # stage shares the "bracket not set yet" fallback.
  EMPTY_FIXTURES_MESSAGES = {
    "upcoming" => "No upcoming matches — every game has kicked off.",
    "unpredicted" => "You're all caught up — every available match has a prediction.",
    "past" => "No matches have kicked off yet."
  }.freeze

  def empty_fixtures_message(stage)
    EMPTY_FIXTURES_MESSAGES.fetch(stage) do
      "No fixtures scheduled for this stage yet. Check back once the bracket is set."
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
