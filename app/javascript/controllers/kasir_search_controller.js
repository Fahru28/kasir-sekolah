import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "select", "count", "clear"]

  connect() {
    this.filter()
  }

  filter() {
    const q = (this.inputTarget.value || "").toLowerCase().trim()
    const select = this.selectTarget
    let visible = 0
    let firstVisibleValue = null

    Array.from(select.options).forEach(opt => {
      if (!opt.value) { opt.hidden = false; return } // placeholder
      const text = opt.textContent.toLowerCase()
      const show = !q || text.includes(q)
      opt.hidden = !show
      if (show) {
        visible++
        if (!firstVisibleValue) firstVisibleValue = opt.value
      }
    })

    if (this.hasCountTarget) {
      if (!q) {
        this.countTarget.textContent = `${select.options.length - 1} siswa`
      } else {
        this.countTarget.textContent = visible ? `${visible} cocok` : "Tidak ada hasil"
      }
    }
    if (this.hasClearTarget) {
      this.clearTarget.classList.toggle("hidden", !q)
    }
    // highlight mismatch
    this.inputTarget.classList.toggle("input-warning", q && visible === 0)
  }

  clear() {
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
  }

  pickFirstOnEnter(e) {
    if (e.key !== "Enter") return
    const q = (this.inputTarget.value || "").toLowerCase().trim()
    if (!q) return
    const select = this.selectTarget
    const first = Array.from(select.options).find(o => o.value && !o.hidden)
    if (first) {
      e.preventDefault()
      select.value = first.value
      select.dispatchEvent(new Event("change", { bubbles: true }))
      // flash select
      select.classList.add("select-primary")
      setTimeout(() => select.classList.remove("select-primary"), 400)
    }
  }
}
