import { Controller } from "@hotwired/stimulus"

// Controls Bulma tabs: toggles visibility of tab panels
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    if (!this.hasTabTarget || !this.hasPanelTarget) return
    // Ensure one active tab
    if (!this.tabTargets.some((t) => t.classList.contains('is-active'))) {
      this.activate(0)
    }
  }

  change(event) {
    event.preventDefault()
    const tabEl = event.currentTarget.closest('[data-tabs-target="tab"]')
    const idx = this.tabTargets.indexOf(tabEl)
    if (idx >= 0) this.activate(idx)
  }

  activate(index) {
    this.tabTargets.forEach((t, i) => {
      t.classList.toggle('is-active', i === index)
    })
    this.panelTargets.forEach((p, i) => {
      p.hidden = i !== index
    })
  }
}
