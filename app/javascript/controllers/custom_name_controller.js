import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "select", "hint"]

  connect() { this.toggleHint() }

  onInput() {
    if (this.inputTarget.value.trim().length > 0) {
      this.selectTarget.value = ""
      // clear kasir-search filter visuals if present
      this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this.toggleHint()
  }

  onSelectChange() {
    if (this.selectTarget.value) {
      this.inputTarget.value = ""
    }
    this.toggleHint()
  }

  toggleHint() {
    if (!this.hasHintTarget) return
    const hasStudent = !!this.selectTarget.value
    const hasCustom = this.inputTarget.value.trim().length > 0
    this.hintTarget.classList.toggle("hidden", hasStudent || hasCustom)
  }
}
