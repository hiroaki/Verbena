import { Controller } from "@hotwired/stimulus"

// Controls Bulma tabs: toggles visibility of tab panels
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    if (!this.hasTabTarget || !this.hasPanelTarget) return

    // Initialize first tab (form input) as active
    this.activate(0)

    // On form submission end, reset form on success.
    // Tab state is managed client-side and not affected by Turbo stream replacements
    // (stream replaces only #eml-inputs-flash, not the tab panels).
    const form = document.getElementById('main-form')
    if (form) {
      this.formListener = (event) => {
        // Prefer Turbo's event detail success flag
        const turboSucceeded = event?.detail?.success === true
        const flash = document.getElementById('eml-inputs-flash')
        const successNode = flash?.querySelector('.notification.is-success')
        const results = successNode?.dataset?.results

        // Consider success if Turbo says so, or if the flash contains results,
        // or (fallback) if a success notification exists.
        const succeeded = turboSucceeded || !!results || !!successNode

        if (succeeded && form.reset) {
          form.reset()
          form.querySelectorAll('input[type="file"]').forEach(i => { i.value = '' })
        }
      }

      form.addEventListener('turbo:submit-end', this.formListener)
    }
  }

  disconnect() {
    const form = document.getElementById('main-form')
    if (form && this.formListener) {
      form.removeEventListener('turbo:submit-end', this.formListener)
      this.formListener = null
    }
  }

  change(event) {
    event.preventDefault()
    const tabEl = event.currentTarget.closest('[data-tabs-target="tab"]')
    const idx = this.tabTargets.indexOf(tabEl)
    if (idx >= 0) {
      this.activate(idx)
    }
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
