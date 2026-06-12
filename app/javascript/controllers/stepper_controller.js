import { Controller } from "@hotwired/stimulus"

// +/- stepper around a numeric score input.
//
//   <div data-controller="stepper">
//     <button type="button" data-action="stepper#decrement">−</button>
//     <input type="number" min="0" max="20" data-stepper-target="input">
//     <button type="button" data-action="stepper#increment">+</button>
//   </div>
export default class extends Controller {
  static targets = ["input"]

  increment() {
    this.#step(1)
  }

  decrement() {
    this.#step(-1)
  }

  #step(delta) {
    const input = this.inputTarget
    if (input.disabled) return

    const min = input.min === "" ? 0 : Number(input.min)
    const max = input.max === "" ? Infinity : Number(input.max)
    const current = Number.parseInt(input.value, 10)
    const next = Number.isNaN(current) ? min : current + delta

    input.value = Math.min(max, Math.max(min, next))
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
