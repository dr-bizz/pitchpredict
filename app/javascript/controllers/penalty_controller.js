import { Controller } from "@hotwired/stimulus"

// Reveals the "who advances on penalties" picker whenever the two score inputs
// are level. Attached only to knockout fixtures. Hidden radios are disabled so
// a stale winner is never submitted; visible radios are required so a draw
// always names an advancer.
export default class extends Controller {
  static targets = ["home", "away", "picker", "option"]

  connect() {
    this.refresh()
  }

  refresh() {
    const home = this.homeTarget.value
    const away = this.awayTarget.value
    const level = home !== "" && away !== "" && Number(home) === Number(away)

    this.pickerTarget.classList.toggle("hidden", !level)
    this.optionTargets.forEach((option) => {
      option.disabled = !level
      option.required = level
    })
  }
}
