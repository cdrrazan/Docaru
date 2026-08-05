// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Registered from here rather than inline, so the page carries no script tag a
// content security policy would have to make an exception for.
//
// Failure is deliberately silent. The worker only makes the public playbooks
// readable offline; if the browser refuses it — private browsing, an insecure
// origin, an older iOS — every page still works exactly as it did.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker").catch(() => {})
  })
}
