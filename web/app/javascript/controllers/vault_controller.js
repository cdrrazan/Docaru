import { Controller } from "@hotwired/stimulus"

// Client-side encryption for document scans.
//
// The passphrase never leaves this file's scope. It is not sent to the server,
// not stored in a cookie, and not written to localStorage — it lives in a
// variable for the lifetime of the tab and is derived into a key with PBKDF2.
// The server receives ciphertext, a nonce, and a content type, and has no code
// path that could turn those back into a passport scan.
//
// The corollary, which the UI says out loud: lose the passphrase and the files
// are gone. There is no recovery, because a recovery path the operator can walk
// is a recovery path an attacker or a subpoena can walk too.
export default class extends Controller {
  static targets = ["passphrase", "status", "input", "gallery", "locked", "unlocked"]
  static values = {
    salt: String,
    documentId: Number,
    uploadUrl: String,
    maxDimension: { type: Number, default: 1600 },
    quality: { type: Number, default: 0.82 }
  }

  connect() {
    this.key = null
    this.showLocked()
  }

  disconnect() {
    // Drop the key when the element goes away rather than leaving it reachable.
    this.key = null
  }

  showLocked() {
    if (this.hasLockedTarget) this.lockedTarget.hidden = false
    if (this.hasUnlockedTarget) this.unlockedTarget.hidden = true
  }

  showUnlocked() {
    if (this.hasLockedTarget) this.lockedTarget.hidden = true
    if (this.hasUnlockedTarget) this.unlockedTarget.hidden = false
  }

  async unlock(event) {
    event.preventDefault()
    const passphrase = this.passphraseTarget.value

    if (passphrase.length < 10) {
      this.report("Use at least 10 characters. This is the only thing standing between a stolen backup and your documents.", true)
      return
    }

    this.key = await this.deriveKey(passphrase)
    this.passphraseTarget.value = ""
    this.showUnlocked()
    this.report("Unlocked for this tab. Closing it locks the vault again.")
    await this.renderGallery()
  }

  lock() {
    this.key = null
    if (this.hasGalleryTarget) this.galleryTarget.innerHTML = ""
    this.showLocked()
    this.report("Locked.")
  }

  // PBKDF2 with a high iteration count: the passphrase is the only secret, so
  // the cost of guessing it is the whole security margin.
  async deriveKey(passphrase) {
    const encoder = new TextEncoder()
    const material = await crypto.subtle.importKey(
      "raw", encoder.encode(passphrase), "PBKDF2", false, ["deriveKey"]
    )

    return crypto.subtle.deriveKey(
      {
        name: "PBKDF2",
        salt: encoder.encode(this.saltValue),
        iterations: 310000,
        hash: "SHA-256"
      },
      material,
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"]
    )
  }

  async upload() {
    if (!this.key) {
      this.report("Unlock the vault first.", true)
      return
    }

    const files = Array.from(this.inputTarget.files || [])
    if (files.length === 0) return

    for (const [index, file] of files.entries()) {
      try {
        this.report(`Preparing ${index + 1} of ${files.length}…`)
        await this.encryptAndUpload(file)
      } catch (error) {
        this.report(`Could not add that file: ${error.message}`, true)
        return
      }
    }

    this.inputTarget.value = ""
    this.report("Added. The server holds only ciphertext.")
    await this.renderGallery()
  }

  async encryptAndUpload(file) {
    // Downscale before encrypting, not after: the server cannot process
    // ciphertext, so this is the only place it can happen. Also the honest
    // place — a 12MB phone photo of a passport is 12MB of someone's mobile
    // data, and the legible size is a few hundred kilobytes.
    const { blob, contentType } = await this.normalise(file)
    const plaintext = await blob.arrayBuffer()

    const iv = crypto.getRandomValues(new Uint8Array(12))
    const ciphertext = await crypto.subtle.encrypt(
      { name: "AES-GCM", iv }, this.key, plaintext
    )

    const body = new FormData()
    body.append("attachment[iv]", this.toBase64(iv))
    body.append("attachment[content_type]", contentType)
    body.append("attachment[byte_size]", String(plaintext.byteLength))
    body.append("attachment[page_no]", String(this.nextPageNumber()))
    body.append("attachment[ciphertext]", new Blob([ciphertext], { type: "application/octet-stream" }), "page.bin")

    const response = await fetch(this.uploadUrlValue, {
      method: "POST",
      body,
      headers: { "X-CSRF-Token": this.csrfToken(), Accept: "application/json" }
    })

    if (!response.ok) {
      const payload = await response.json().catch(() => ({}))
      throw new Error((payload.errors || ["upload rejected"]).join(", "))
    }
  }

  // Images are re-encoded to WebP at a sane size. PDFs pass through untouched:
  // rasterising one in the browser would lose the text layer, and we cannot
  // inspect it server-side.
  async normalise(file) {
    if (file.type === "application/pdf") {
      if (file.size > 10 * 1024 * 1024) throw new Error("PDFs must be under 10MB")
      return { blob: file, contentType: "application/pdf" }
    }

    if (!file.type.startsWith("image/")) {
      throw new Error("Only images and PDFs")
    }

    const bitmap = await createImageBitmap(file)
    const scale = Math.min(1, this.maxDimensionValue / Math.max(bitmap.width, bitmap.height))
    const canvas = document.createElement("canvas")
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close()

    const blob = await new Promise((resolve, reject) => {
      canvas.toBlob(
        (result) => (result ? resolve(result) : reject(new Error("could not re-encode the image"))),
        "image/webp",
        this.qualityValue
      )
    })

    return { blob, contentType: "image/webp" }
  }

  async renderGallery() {
    if (!this.hasGalleryTarget || !this.key) return

    this.galleryTarget.innerHTML = ""

    for (const node of this.element.querySelectorAll("[data-attachment-url]")) {
      const url = node.dataset.attachmentUrl
      const iv = node.dataset.attachmentIv
      const contentType = node.dataset.attachmentContentType

      try {
        const response = await fetch(url, { headers: { Accept: "application/octet-stream" } })
        const ciphertext = await response.arrayBuffer()
        const plaintext = await crypto.subtle.decrypt(
          { name: "AES-GCM", iv: this.fromBase64(iv) }, this.key, ciphertext
        )

        const objectUrl = URL.createObjectURL(new Blob([plaintext], { type: contentType }))
        this.galleryTarget.appendChild(this.figureFor(objectUrl, contentType))
      } catch {
        // AES-GCM authenticates, so a wrong passphrase fails here rather than
        // producing plausible garbage. Say which it is.
        this.galleryTarget.appendChild(
          this.errorFigure("Could not decrypt this page — wrong passphrase, or the file was altered.")
        )
      }
    }
  }

  figureFor(objectUrl, contentType) {
    const figure = document.createElement("figure")
    figure.className = "card"

    if (contentType.startsWith("image/")) {
      const image = document.createElement("img")
      image.src = objectUrl
      image.alt = "Decrypted document page"
      image.style.maxWidth = "100%"
      figure.appendChild(image)
    }

    const link = document.createElement("a")
    link.href = objectUrl
    link.textContent = "Open"
    link.target = "_blank"
    link.rel = "noopener"
    figure.appendChild(link)

    return figure
  }

  errorFigure(message) {
    const div = document.createElement("div")
    div.className = "banner banner-draft"
    div.textContent = message
    return div
  }

  nextPageNumber() {
    return this.element.querySelectorAll("[data-attachment-url]").length + 1
  }

  report(message, isError = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.className = isError ? "banner banner-draft" : "note"
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  toBase64(bytes) {
    return btoa(String.fromCharCode(...bytes))
  }

  fromBase64(value) {
    return Uint8Array.from(atob(value), (char) => char.charCodeAt(0))
  }
}
