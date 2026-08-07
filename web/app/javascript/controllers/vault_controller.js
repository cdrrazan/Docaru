import { Controller } from "@hotwired/stimulus"

// Client-side encryption for document scans.
//
// The passphrase never leaves this file's scope. It is not sent to the server,
// not stored in a cookie, and not written to localStorage — it lives in a
// variable for the lifetime of the tab and is derived into a key with PBKDF2.
// The server receives ciphertext, a nonce, and a content type, and has no code
// path that could turn those back into a passport scan.
//
// Files are encrypted under a random vault key, not under the passphrase
// itself. The passphrase encrypts that key, and so does a recovery code, so the
// server holds the same key sealed two ways and can open neither. Two things
// fall out of the indirection that a passphrase-as-key design cannot do:
// changing a passphrase rewraps one small blob instead of re-encrypting every
// scan, and forgetting one is survivable.
//
// What has not changed is who can read anything. The recovery code is generated
// here, shown once, and never sent — a recovery path the operator can walk is a
// recovery path an attacker or a subpoena can walk too, so the operator does not
// get one. Lose both the passphrase and the code and the files are still gone.
export default class extends Controller {
  static targets = [
    "passphrase", "status", "input", "gallery", "locked", "unlocked",
    "setup", "setupPassphrase", "setupConfirm", "recoveryCode", "recoveryPanel",
    "recoveryInput", "recoveryPassphrase", "recovery"
  ]
  static values = {
    salt: String,
    recoverySalt: String,
    wrappedKey: String,
    wrappedKeyIv: String,
    recoveryWrappedKey: String,
    recoveryWrappedKeyIv: String,
    initialised: Boolean,
    keyUrl: String,
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

  // Three states, not two: a household that has never chosen a passphrase is
  // shown the setup panel, because "wrong passphrase" and "you have not picked
  // one yet" are different problems and only one of them is the user's fault.
  showLocked() {
    const setup = !this.initialisedValue

    if (this.hasLockedTarget) this.lockedTarget.hidden = setup
    if (this.hasSetupTarget) this.setupTarget.hidden = !setup
    if (this.hasUnlockedTarget) this.unlockedTarget.hidden = true
    if (this.hasRecoveryTarget) this.recoveryTarget.hidden = true
  }

  showUnlocked() {
    if (this.hasLockedTarget) this.lockedTarget.hidden = true
    if (this.hasSetupTarget) this.setupTarget.hidden = true
    if (this.hasRecoveryTarget) this.recoveryTarget.hidden = true
    if (this.hasUnlockedTarget) this.unlockedTarget.hidden = false
  }

  showRecovery(event) {
    event?.preventDefault()
    if (this.hasLockedTarget) this.lockedTarget.hidden = true
    if (this.hasRecoveryTarget) this.recoveryTarget.hidden = false
  }

  // ---- setup ---------------------------------------------------------------

  // Generates the vault key and both of its wrappings in one go. The key never
  // exists outside this function's closure in extractable form except for the
  // moment it is wrapped, and the recovery code exists only long enough to be
  // shown.
  async createVault(event) {
    event.preventDefault()

    const passphrase = this.setupPassphraseTarget.value
    const confirm = this.setupConfirmTarget.value

    if (passphrase.length < 10) {
      this.report("Use at least 10 characters. This is the only thing standing between a stolen backup and your documents.", true)
      return
    }

    if (passphrase !== confirm) {
      this.report("Those two do not match. A typo here locks you out of your own files.", true)
      return
    }

    const vaultKey = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, true, ["encrypt", "decrypt"])
    const recoveryCode = this.generateRecoveryCode()

    const wrapped = await this.wrap(vaultKey, await this.deriveKey(passphrase, this.saltValue))
    const recoveryWrapped = await this.wrap(vaultKey, await this.deriveKey(recoveryCode, this.recoverySaltValue))

    const response = await this.submitKey("POST", wrapped, recoveryWrapped)
    if (!response) return

    this.setupPassphraseTarget.value = ""
    this.setupConfirmTarget.value = ""

    // Re-imported unextractable for use: the copy that could be exported has
    // done its job and is not kept.
    this.key = await this.reimport(vaultKey)
    this.initialisedValue = true
    this.wrappedKeyValue = wrapped.ciphertext
    this.wrappedKeyIvValue = wrapped.iv
    this.recoveryWrappedKeyValue = recoveryWrapped.ciphertext
    this.recoveryWrappedKeyIvValue = recoveryWrapped.iv

    this.presentRecoveryCode(recoveryCode)
    this.showUnlocked()
    this.report("Vault created. Write the recovery code down before you leave this page — it is not shown again.")
  }

  // ---- unlock --------------------------------------------------------------

  async unlock(event) {
    event.preventDefault()
    const passphrase = this.passphraseTarget.value

    if (passphrase.length < 10) {
      this.report("Use at least 10 characters. This is the only thing standing between a stolen backup and your documents.", true)
      return
    }

    const wrapping = await this.deriveKey(passphrase, this.saltValue)
    const vaultKey = await this.unwrap(this.wrappedKeyValue, this.wrappedKeyIvValue, wrapping)

    // AES-GCM authenticates, so a wrong passphrase fails here rather than
    // producing a key that quietly decrypts everything into noise. This is the
    // one place the passphrase can be checked, and it is checked before
    // anything is shown as unlocked.
    if (!vaultKey) {
      this.report("That passphrase does not open this vault. If you have lost it, use your recovery code.", true)
      return
    }

    this.key = vaultKey
    this.passphraseTarget.value = ""
    this.showUnlocked()
    this.report("Unlocked for this tab. Closing it locks the vault again.")
    await this.renderGallery()
  }

  // ---- recovery ------------------------------------------------------------

  // The recovery code opens the same vault key, which is then rewrapped under a
  // new passphrase. The scans are not touched: they were never encrypted with
  // the passphrase in the first place, which is the whole point of the
  // indirection.
  async recover(event) {
    event.preventDefault()

    const code = this.normaliseRecoveryCode(this.recoveryInputTarget.value)
    const passphrase = this.recoveryPassphraseTarget.value

    if (passphrase.length < 10) {
      this.report("The new passphrase needs at least 10 characters.", true)
      return
    }

    const recoveryKey = await this.deriveKey(code, this.recoverySaltValue)
    const vaultKey = await this.unwrap(this.recoveryWrappedKeyValue, this.recoveryWrappedKeyIvValue, recoveryKey)

    if (!vaultKey) {
      this.report("That recovery code does not open this vault. Check for a mistyped character.", true)
      return
    }

    // A code that has been used has been written somewhere, read out, or
    // screenshotted. Issue a fresh one rather than letting a spent code stay
    // valid.
    const replacement = this.generateRecoveryCode()
    const wrapped = await this.wrap(vaultKey, await this.deriveKey(passphrase, this.saltValue))
    const recoveryWrapped = await this.wrap(vaultKey, await this.deriveKey(replacement, this.recoverySaltValue))

    const response = await this.submitKey("PATCH", wrapped, recoveryWrapped)
    if (!response) return

    this.recoveryInputTarget.value = ""
    this.recoveryPassphraseTarget.value = ""

    this.key = await this.reimport(vaultKey)
    this.wrappedKeyValue = wrapped.ciphertext
    this.wrappedKeyIvValue = wrapped.iv
    this.recoveryWrappedKeyValue = recoveryWrapped.ciphertext
    this.recoveryWrappedKeyIvValue = recoveryWrapped.iv

    this.presentRecoveryCode(replacement)
    this.showUnlocked()
    this.report("Back in, and your passphrase is changed. The old recovery code no longer works — the new one is above.")
    await this.renderGallery()
  }

  lock() {
    this.key = null
    if (this.hasGalleryTarget) this.galleryTarget.innerHTML = ""
    if (this.hasRecoveryCodeTarget) this.recoveryCodeTarget.textContent = ""
    if (this.hasRecoveryPanelTarget) this.recoveryPanelTarget.hidden = true
    this.showLocked()
    this.report("Locked.")
  }

  // ---- key handling --------------------------------------------------------

  // PBKDF2 with a high iteration count. The derived key only ever wraps the
  // vault key, but that makes it no less worth guessing, so the cost stays.
  async deriveKey(secret, salt) {
    const encoder = new TextEncoder()
    const material = await crypto.subtle.importKey(
      "raw", encoder.encode(secret), "PBKDF2", false, ["deriveKey"]
    )

    return crypto.subtle.deriveKey(
      {
        name: "PBKDF2",
        salt: encoder.encode(salt),
        iterations: 310000,
        hash: "SHA-256"
      },
      material,
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"]
    )
  }

  async wrap(vaultKey, wrappingKey) {
    const raw = await crypto.subtle.exportKey("raw", vaultKey)
    const iv = crypto.getRandomValues(new Uint8Array(12))
    const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, wrappingKey, raw)

    return { ciphertext: this.toBase64(new Uint8Array(ciphertext)), iv: this.toBase64(iv) }
  }

  // Returns null rather than throwing on a bad key: a wrong passphrase is an
  // ordinary thing for a person to do, not an exception.
  async unwrap(ciphertext, iv, wrappingKey) {
    try {
      const raw = await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: this.fromBase64(iv) }, wrappingKey, this.fromBase64(ciphertext)
      )

      return crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, true, ["encrypt", "decrypt"])
    } catch {
      return null
    }
  }

  async reimport(vaultKey) {
    const raw = await crypto.subtle.exportKey("raw", vaultKey)

    return crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["encrypt", "decrypt"])
  }

  async submitKey(method, wrapped, recoveryWrapped) {
    const response = await fetch(this.keyUrlValue, {
      method,
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        Accept: "application/json"
      },
      body: JSON.stringify({
        vault_key: {
          wrapped: wrapped.ciphertext,
          wrapped_iv: wrapped.iv,
          recovery_wrapped: recoveryWrapped.ciphertext,
          recovery_wrapped_iv: recoveryWrapped.iv
        }
      })
    })

    if (!response.ok) {
      const payload = await response.json().catch(() => ({}))
      this.report((payload.errors || ["Could not save the vault key."]).join(", "), true)
      return false
    }

    return true
  }

  // ---- recovery codes ------------------------------------------------------

  // 160 bits in Crockford's base32, which drops I, L, O and U so the alphabet
  // has no character that can be misread as another when it is copied off a
  // screen onto paper — which is exactly what this is for.
  generateRecoveryCode() {
    const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    const bytes = crypto.getRandomValues(new Uint8Array(20))
    let bits = 0
    let value = 0
    let output = ""

    for (const byte of bytes) {
      value = (value << 8) | byte
      bits += 8

      while (bits >= 5) {
        output += alphabet[(value >>> (bits - 5)) & 31]
        bits -= 5
      }
    }

    return output.match(/.{1,4}/g).join("-")
  }

  // Accepts what a person types back: any casing, any grouping, and the letters
  // Crockford maps onto digits because they look like them. U is left alone —
  // the alphabet excludes it, so a typed U is a genuine mistake, and turning it
  // into some other character would replace a clear failure with a confusing
  // one.
  normaliseRecoveryCode(value) {
    return value
      .toUpperCase()
      .replace(/[^0-9A-Z]/g, "")
      .replace(/[ILO]/g, (char) => ({ I: "1", L: "1", O: "0" })[char])
      .match(/.{1,4}/g)
      ?.join("-") || ""
  }

  presentRecoveryCode(code) {
    if (!this.hasRecoveryCodeTarget) return

    this.recoveryCodeTarget.textContent = code
    if (this.hasRecoveryPanelTarget) this.recoveryPanelTarget.hidden = false
  }

  copyRecoveryCode(event) {
    event.preventDefault()
    navigator.clipboard?.writeText(this.recoveryCodeTarget.textContent)
    this.report("Copied. A clipboard is not somewhere to leave it — write it down too.")
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
