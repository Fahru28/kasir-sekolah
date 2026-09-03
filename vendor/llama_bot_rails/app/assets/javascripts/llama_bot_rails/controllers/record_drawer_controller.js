import { Controller } from "@hotwired/stimulus"

// Slide-over detail drawer driven by the shared "record_drawer" Turbo Frame
// (see app/views/llama_bot_rails/_record_drawer.html.erb). The drawer opens
// only after the frame has loaded content, so a slow fetch never shows an
// empty panel. Closing clears both the frame src and its content, so
// reopening the same record always refetches.
//
// "record-drawer" is a reserved controller identifier — host apps must not
// define their own record_drawer_controller.js.
export default class extends Controller {
  static targets = ["frame", "closeButton"]

  connect() {
    this.onDocumentClick = this.onDocumentClick.bind(this)
    document.addEventListener("click", this.onDocumentClick)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
  }

  // Row convenience: a click on non-interactive space inside a
  // [data-drawer-row] row follows that row's drawer link. Clicks on real
  // links/buttons/inputs are left alone, so in-row controls never trigger a
  // second navigation.
  onDocumentClick(event) {
    const row = event.target.closest("[data-drawer-row]")
    if (!row) return
    if (event.target.closest("a, button, form, input, select, textarea, label")) return
    const link = row.querySelector("a[data-turbo-frame='record_drawer']")
    if (link) link.click()
  }

  // data-action: turbo:frame-load->record-drawer#open (on the frame)
  open() {
    this.element.classList.remove("hidden")
    requestAnimationFrame(() => this.element.classList.add("llama-drawer-open"))
    if (this.hasCloseButtonTarget) this.closeButtonTarget.focus()
  }

  close() {
    if (this.element.classList.contains("hidden")) return
    this.element.classList.remove("llama-drawer-open")
    this.element.classList.add("hidden")
    if (this.hasFrameTarget) {
      this.frameTarget.removeAttribute("src")
      this.frameTarget.innerHTML = ""
    }
  }

  // data-action: turbo:frame-missing->record-drawer#frameMissing
  // A frame response without a matching frame (e.g. a Devise sign-in redirect
  // after session expiry) becomes a normal full-page visit instead of a
  // "content missing" error inside the drawer.
  frameMissing(event) {
    event.preventDefault()
    this.close()
    const response = event.detail && event.detail.response
    if (response && window.Turbo) window.Turbo.visit(response.url)
  }
}
