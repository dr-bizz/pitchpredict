module FixturesHelper
  # Tab order + labels for the predictions grid. Keys match Fixture.stages.
  STAGE_TABS = {
    "group" => "Groups",
    "r32" => "R32",
    "r16" => "R16",
    "qf" => "QF",
    "sf" => "SF",
    "third_place" => "3rd Place",
    "final" => "Final"
  }.freeze

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
