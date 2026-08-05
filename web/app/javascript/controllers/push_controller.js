import { Controller } from "@hotwired/stimulus"

// Asking to be allowed to interrupt, and remembering the answer.
//
// The prompt is never fired on page load. A permission request that arrives
// before the reader knows what the site is gets denied — and a denial is close
// to permanent, because most browsers will not ask again and most people never
// find the setting that undoes it. So it sits behind a button, on a page that
// has already explained what the interruption is for.
export default class extends Controller {
  static targets = ["enable", "disable", "status"]
  static values = { publicKey: String, url: String }

  async connect() {
    this.supported = "serviceWorker" in navigator && "PushManager" in window
    await this.render()
  }

  async render() {
    if (!this.supported) {
      this.show(null)
      this.report("This browser cannot show notifications. Reminders will still arrive by email.")
      return
    }

    if (Notification.permission === "denied") {
      this.show(null)
      this.report("Notifications are blocked for this site in your browser settings. Reminders will still arrive by email.")
      return
    }

    const subscription = await this.existing()
    this.show(subscription ? "on" : "off")
    this.report(
      subscription
        ? "On for this device. Reminders arrive here as well as by email."
        : "Off for this device. Reminders arrive by email only."
    )
  }

  async existing() {
    const registration = await navigator.serviceWorker.ready
    return registration.pushManager.getSubscription()
  }

  async enable() {
    this.report("Waiting for permission…")

    const permission = await Notification.requestPermission()
    if (permission !== "granted") {
      await this.render()
      return
    }

    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.subscribe({
      // Required by every browser that implements this: a push that cannot be
      // shown to the reader may not be delivered silently.
      userVisibleOnly: true,
      applicationServerKey: this.decodeKey(this.publicKeyValue)
    })

    const response = await this.send("POST", subscription)
    if (!response.ok) {
      // Never leave a subscription registered with the push service that the
      // server has no record of: it would receive nothing and look enabled.
      await subscription.unsubscribe()
      this.report("Could not register this device. Reminders will still arrive by email.")
      return
    }

    await this.render()
  }

  async disable() {
    const subscription = await this.existing()
    if (!subscription) return

    await this.send("DELETE", subscription)
    await subscription.unsubscribe()
    await this.render()
  }

  send(method, subscription) {
    const json = subscription.toJSON()

    return fetch(this.urlValue, {
      method,
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: JSON.stringify({
        endpoint: subscription.endpoint,
        p256dh_key: json.keys?.p256dh,
        auth_key: json.keys?.auth
      })
    })
  }

  // The VAPID key travels as base64url in the markup and has to reach
  // subscribe() as bytes.
  decodeKey(base64url) {
    const padded = base64url.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(base64url.length / 4) * 4, "=")
    const raw = atob(padded)
    return Uint8Array.from(raw, (char) => char.charCodeAt(0))
  }

  show(state) {
    if (this.hasEnableTarget) this.enableTarget.hidden = state !== "off"
    if (this.hasDisableTarget) this.disableTarget.hidden = state !== "on"
  }

  report(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
