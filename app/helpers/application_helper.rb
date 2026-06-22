module ApplicationHelper
  # Renders a player's name as a link to their predictions page, except for the
  # viewer's own row, which stays plain text. Single source of truth for every
  # leaderboard surface (table, podium, dashboard top-5).
  #
  # NOTE: the leaderboard table is broadcast by ScoreFixtureJob with viewer: nil
  # (a background job has no session), so every name links on a broadcast;
  # leaderboard_highlight_controller.js neutralises the viewer's own link
  # client-side, the same fix-up it already does for the "You" badge.
  def player_predictions_link(user, viewer:, name: user.name)
    return name if viewer && viewer.id == user.id

    link_to name, user_predictions_path(user), class: "link link-hover", data: { player_link: "" }
  end
end
