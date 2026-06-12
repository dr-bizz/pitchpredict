import { Controller } from "@hotwired/stimulus"

// Highlights the viewer's own row in the leaderboard table.
//
// ScoreFixtureJob broadcasts the table partial with current_user: nil (a
// background job has no session), so the server-rendered highlight would be
// wiped on every live update. This controller re-applies it client-side: it
// sits on the partial's root element, so each Turbo Stream replace reconnects
// it, and it matches each row's data-user-id against the signed-in user's id
// from the layout's <meta name="current-user-id"> tag.
export default class extends Controller {
  connect() {
    const viewerId = document.querySelector('meta[name="current-user-id"]')?.content
    if (!viewerId) return

    const row = this.element.querySelector(`tr[data-user-id="${viewerId}"]`)
    if (!row) return

    row.dataset.currentUser = "true"
    row.classList.add("bg-pitch/5")
    row.querySelector("[data-you-badge]")?.removeAttribute("hidden")
  }
}
