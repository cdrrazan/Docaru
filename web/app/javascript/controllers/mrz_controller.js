import { Controller } from "@hotwired/stimulus"

// Pointing a camera at a passport instead of typing forty-four characters.
//
// Cold start is the product's biggest risk: it is worth nothing until roughly
// fifteen documents are in it, and typing fifteen documents in by hand is what
// has killed every personal-records product before this one.
//
// No OCR library is bundled. Where the browser has a text detector of its own
// it is used; where it does not, the captured frame is kept on screen, cropped
// to the zone and magnified, so the characters can be read off a still image
// rather than off a passport held at arm's length. That is a smaller
// improvement than real OCR and a much larger one than nothing, and it costs
// the reader — often on roaming data — no download at all.
//
// Nothing leaves the browser. The frame is drawn to a canvas, read, and
// dropped; it is never uploaded, and the server sees only the characters the
// person chooses to submit.
export default class extends Controller {
  static targets = ["video", "canvas", "input", "status", "capture", "start", "still"]

  connect() {
    this.stream = null
    // Support is checked once, up front, so the button can promise the right
    // thing rather than failing after the camera is already open.
    this.canDetect = "TextDetector" in window
  }

  disconnect() {
    this.stopCamera()
  }

  async start() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: { ideal: "environment" },
          // The zone is small in frame. Asking for more pixels than the preview
          // needs is what makes it legible once cropped.
          width: { ideal: 1920 },
          height: { ideal: 1080 }
        }
      })
    } catch (error) {
      this.report(
        error.name === "NotAllowedError"
          ? "Camera permission was declined. Type or paste the two lines instead — it works just as well."
          : "No camera available here. Type or paste the two lines instead.",
        true
      )
      return
    }

    this.videoTarget.srcObject = this.stream
    this.videoTarget.hidden = false
    this.stillTarget.hidden = true
    this.captureTarget.hidden = false
    this.startTarget.hidden = true
    await this.videoTarget.play()

    this.report(
      this.canDetect
        ? "Fill the frame with the two lines along the bottom of the photo page, then capture."
        : "Fill the frame with the two lines along the bottom of the photo page. This browser cannot read them automatically, so the capture will be held on screen, magnified, for you to copy."
    )
  }

  async capture() {
    const video = this.videoTarget
    const canvas = this.canvasTarget
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    canvas.getContext("2d").drawImage(video, 0, 0)

    // The zone occupies roughly the bottom quarter of the photo page. Cropping
    // to it both magnifies the still and keeps the detector away from the
    // surrounding text, which is where the false positives come from.
    const band = this.cropToZone(canvas)

    this.stillTarget.src = band.toDataURL("image/webp", 0.9)
    this.stillTarget.hidden = false
    this.videoTarget.hidden = true
    this.stopCamera()
    this.startTarget.hidden = false
    this.startTarget.textContent = "Retake"
    this.captureTarget.hidden = true

    if (this.canDetect) await this.read(band)
    else this.report("Captured. Copy the two lines from the image into the box below — every field carries a check digit, so a slip will be caught rather than saved.")
  }

  async read(canvas) {
    this.report("Reading…")

    let lines = []
    try {
      const detector = new window.TextDetector()
      const blocks = await detector.detect(canvas)
      lines = blocks.flatMap((block) => block.rawValue.split(/\r?\n/))
    } catch {
      this.report("This browser could not read the image. Copy the two lines from it instead.", true)
      return
    }

    const zone = this.mrzLines(lines)

    if (zone.length >= 2) {
      this.inputTarget.value = zone.join("\n")
      this.inputTarget.focus()
      this.report(`Read ${zone.length} lines. Check them against the image, then read it — the check digits will catch a misread character.`)
    } else {
      this.report("Could not make out the zone. Try again with more light and the page flat, or copy the lines from the image.", true)
    }
  }

  // The zone is the only part of a passport written in this alphabet at this
  // width, which is what makes it separable from the rest of the page without
  // understanding any of it: 44 characters for a passport, 30 for an ID card,
  // drawn from A-Z, 0-9 and the filler.
  mrzLines(lines) {
    return lines
      .map((line) => line.toUpperCase().replace(/[«≪]/g, "<").replace(/[^A-Z0-9<]/g, ""))
      .filter((line) => line.length >= 28 && line.length <= 46)
  }

  cropToZone(source) {
    const height = Math.round(source.height * 0.34)
    const band = document.createElement("canvas")
    band.width = source.width
    band.height = height
    band
      .getContext("2d")
      .drawImage(source, 0, source.height - height, source.width, height, 0, 0, source.width, height)
    return band
  }

  stopCamera() {
    if (!this.stream) return
    this.stream.getTracks().forEach((track) => track.stop())
    this.stream = null
  }

  report(message, isError = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("status-error", isError)
  }
}
