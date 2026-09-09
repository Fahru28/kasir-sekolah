import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "clear", "count", "item", "empty"]

  connect() { this.filter() }

  filter() {
    const q = (this.inputTarget.value || "").toLowerCase().trim()
    let visible = 0
    this.itemTargets.forEach(el => {
      const hay = (el.dataset.search || "").toLowerCase()
      const show = !q || hay.includes(q)
      el.classList.toggle("hidden", !show)
      if (show) visible++
    })
    if (this.hasCountTarget) {
      if (!q) this.countTarget.textContent = `${this.itemTargets.length} barang`
      else this.countTarget.textContent = visible ? `${visible} cocok` : "Tidak ada hasil"
    }
    if (this.hasClearTarget) this.clearTarget.classList.toggle("hidden", !q)
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", visible !== 0)
    this.inputTarget.classList.toggle("input-warning", q && visible === 0)
  }

  clear() {
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
  }
}
