import { Controller } from "@hotwired/stimulus"

// Collapsible filter drawer for LlamaPress scaffold index pages. The panel
// hangs off a full-width filter bar and starts collapsed unless the request
// already carries one of the panel's own params. Free-text search lives
// outside the panel, in the always-visible search bar.
//
// "filter-panel" is a reserved controller identifier — host apps must not
// define their own filter_panel_controller.js.
export default class extends Controller {
  static targets = ["panel", "chevron"]

  toggle(event) {
    const collapsed = this.panelTarget.classList.toggle("hidden")

    if (this.hasChevronTarget) {
      this.chevronTarget.classList.toggle("llama-filter-chevron-open", !collapsed)
    }

    const button = event && event.currentTarget
    if (button) button.setAttribute("aria-expanded", String(!collapsed))
  }
}
