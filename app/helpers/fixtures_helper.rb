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

  # NOTE: assumption — kickoff times are displayed in the app's default time
  # zone (UTC unless config.time_zone is set). Per-user zones are out of scope.
  def kickoff_label(fixture)
    fixture.kickoff_at.strftime("%a %-d %b · %-I:%M %p")
  end

  def stage_tab_classes(active)
    if active
      "rounded-full bg-pitch px-4 py-1.5 text-sm font-semibold text-white shadow-card"
    else
      "rounded-full bg-white px-4 py-1.5 text-sm font-medium text-charcoal/70 ring-1 ring-charcoal/10 hover:bg-pitch/5 hover:text-pitch"
    end
  end
end
