import { Controller } from "@hotwired/stimulus"

// Rafraîchit le turbo-frame "context-section" toutes les N ms
// quand ia_context_status est "processing".
// Lorsque le job termine, le frame rechargé rend active-value=false
// → le contrôleur ne redémarre pas le timer → le polling s'arrête.
export default class extends Controller {
  static values = {
    active:   Boolean,
    interval: { type: Number, default: 5000 }
  }

  connect() {
    if (this.activeValue) {
      this.timer = setInterval(() => this.refresh(), this.intervalValue)
    }
  }

  disconnect() {
    clearInterval(this.timer)
  }

  refresh() {
    const frame = document.getElementById("context-section")
    if (frame) frame.reload()
  }
}
