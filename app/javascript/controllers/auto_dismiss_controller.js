import { Controller } from "@hotwired/stimulus"

// Auto-removes its element after a delay.
//
// The admin index intentionally does NOT subscribe to "results" (no background
// page refresh), and inline saves prepend a success toast into #admin-flash via
// a targeted Turbo Stream. Without this, those toasts would stack unbounded for
// the whole session. This controller removes each toast shortly after it
// connects so #admin-flash stays tidy across many saves.
export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  connect() {
    this.timeout = setTimeout(() => this.element.remove(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
