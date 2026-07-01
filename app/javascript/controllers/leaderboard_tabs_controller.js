import { Controller } from "@hotwired/stimulus"

// Two-tab switch for the leaderboard: "Overall" and "From R16".
//
// The active tab lives in the URL hash (#overall / #r16), NOT in the DOM, so it
// survives the live-update morph. ScoreFixtureJob broadcasts a refresh to
// "results"; the page re-GETs itself and Turbo morphs the server HTML back in,
// which resets each panel's `hidden` attribute to its server default (Overall
// shown, R16 hidden). A morph keeps this controller's element in place, so
// connect() does NOT re-run — we re-apply the hash-selected board on every
// turbo:render instead, keeping the player on the tab they chose.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.reapply = this.reapply.bind(this)
    this.reapply()
    document.addEventListener("turbo:render", this.reapply)
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.reapply)
  }

  // Tab click handler.
  select(event) {
    const board = event.currentTarget.dataset.board
    // replaceState (not `location.hash =`) so the browser does not scroll to an
    // element whose id happens to match the fragment.
    history.replaceState(history.state, "", `#${board}`)
    this.show(board)
  }

  reapply() {
    this.show(this.#activeBoard())
  }

  show(board) {
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.board !== board
    })
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.board === board
      tab.classList.toggle("tab-active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })
  }

  // The board named by the URL hash, or "overall" when the hash is absent or
  // does not match a known tab.
  #activeBoard() {
    const fromHash = window.location.hash.replace("#", "")
    const known = this.tabTargets.some((tab) => tab.dataset.board === fromHash)
    return known ? fromHash : "overall"
  }
}
