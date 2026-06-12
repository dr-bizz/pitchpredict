module Admin
  module FixturesHelper
    STAGE_LABELS = {
      "group" => "Group Stage",
      "r32" => "Round of 32",
      "r16" => "Round of 16",
      "qf" => "Quarter-final",
      "sf" => "Semi-final",
      "third_place" => "Third Place",
      "final" => "Final"
    }.freeze

    def stage_label(stage)
      STAGE_LABELS.fetch(stage.to_s) { stage.to_s.humanize }
    end

    # Maps a fixture status to one of the design-system pill classes.
    def status_pill_class(status)
      case status.to_s
      when "live" then "pill-live"
      when "finished" then "pill-predicted"
      else "pill-muted"
      end
    end
  end
end
