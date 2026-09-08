import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "clear", "card", "count", "empty", "category", "loadMore", "grid"]
  static values = { initial: Number }

  connect() {
    this.visibleLimit = this.initialValue || 8
    this.activeCategory = "Semua"
    this.filter()
  }

  filter() {
    const q = (this.inputTarget.value || "").toLowerCase().trim()
    let matchCount = 0
    let visibleCount = 0

    this.cardTargets.forEach(card => {
      const name = (card.dataset.name || "").toLowerCase()
      const cat = (card.dataset.category || "")
      const matchesQ = !q || name.includes(q)
      const matchesCat = this.activeCategory === "Semua" || cat === this.activeCategory
      const matches = matchesQ && matchesCat
      if (matches) matchCount++
      // respect limit when no query and no category filter
      const withinLimit = !q && this.activeCategory === "Semua" ? visibleCount < this.visibleLimit : true
      const show = matches && withinLimit
      if (show) visibleCount++
      card.classList.toggle("hidden", !show)
      // keep matched but beyond limit hidden for load more
      if (matches && !show) card.dataset.beyondLimit = "1"
      else delete card.dataset.beyondLimit
    })

    if (this.hasCountTarget) {
      if (!q && this.activeCategory === "Semua") {
        const total = this.cardTargets.length
        this.countTarget.textContent = `Menampilkan ${visibleCount} dari ${total} barang`
      } else {
        this.countTarget.textContent = `${matchCount} hasil${q ? ` untuk "${q}"` : ""}`
      }
    }
    if (this.hasClearTarget) this.clearTarget.classList.toggle("hidden", !q)
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", matchCount !== 0)
    if (this.hasLoadMoreTarget) {
      const hiddenBeyond = this.cardTargets.some(c => c.dataset.beyondLimit === "1")
      this.loadMoreTarget.classList.toggle("hidden", !hiddenBeyond || q || this.activeCategory !== "Semua")
      if (hiddenBeyond) {
        const remaining = this.cardTargets.filter(c => c.dataset.beyondLimit === "1").length
        this.loadMoreTarget.querySelector("[data-role='remaining']")?.replaceChildren(document.createTextNode(remaining))
      }
    }
    this.inputTarget.classList.toggle("input-warning", q && matchCount === 0)
  }

  clear() {
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
  }

  selectCategory(e) {
    this.activeCategory = e.currentTarget.dataset.category
    this.categoryTargets.forEach(btn => {
      const active = btn.dataset.category === this.activeCategory
      btn.classList.toggle("btn-primary", active)
      btn.classList.toggle("btn-ghost", !active)
      btn.classList.toggle("border", !active)
    })
    this.filter()
  }

  showMore() {
    this.visibleLimit += 12
    this.filter()
  }
}
