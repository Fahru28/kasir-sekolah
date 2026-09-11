import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "clear", "count", "item", "empty", "kategori"]

  connect() { this.filter() }

  filter() {
    const q = (this.inputTarget.value || "").toLowerCase().trim()
    const kat = this.hasKategoriTarget ? this.kategoriTarget.value : ""
    let visible = 0
    this.itemTargets.forEach(el => {
      const hay = (el.dataset.search || "").toLowerCase()
      const elKat = el.dataset.kategori || ""
      const matchQ = !q || hay.includes(q)
      const matchKat = !kat || elKat === kat
      const show = matchQ && matchKat
      el.classList.toggle("hidden", !show)
      if (show) visible++
    })
    if (this.hasCountTarget) {
      if (!q && !kat) this.countTarget.textContent = `${this.itemTargets.length} barang`
      else this.countTarget.textContent = visible ? `${visible} cocok` : "Tidak ada hasil"
    }
    if (this.hasClearTarget) this.clearTarget.classList.toggle("hidden", !q && !kat)
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", visible !== 0)
    this.inputTarget.classList.toggle("input-warning", (q || kat) && visible === 0)
  }

  clear() {
    this.inputTarget.value = ""
    if (this.hasKategoriTarget) this.kategoriTarget.value = ""
    this.filter()
    this.inputTarget.focus()
  }
}
