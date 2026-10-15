import jsQR from 'jsqr'

// Phone camera photos are 12–48 MP. Drawn at full size they go past iOS Safari's canvas
// limit (the canvas comes back blank) and are slow to decode, so the photo is shrunk
// first. A few sizes are tried because a QR code that's small in the frame reads better
// larger, and a screen photo with moiré reads better smaller.
const SIZES = [1600, 1000, 2400, 700]

async function loadImage(file) {
  if (window.createImageBitmap) {
    try { return await createImageBitmap(file) } catch { /* fall back to <img> */ }
  }
  const url = URL.createObjectURL(file)
  try {
    const img = new Image()
    img.src = url
    await img.decode()
    return img
  } finally {
    URL.revokeObjectURL(url)
  }
}

// Resolves to the QR code's text, or null if none was found.
export async function readQrFromPhoto(file) {
  const img = await loadImage(file)
  const w0 = img.width, h0 = img.height
  const canvas = document.createElement('canvas')
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  const detector = 'BarcodeDetector' in window ? new window.BarcodeDetector({ formats: ['qr_code'] }) : null

  try {
    for (const max of SIZES) {
      const scale = Math.min(1, max / Math.max(w0, h0))
      const w = Math.round(w0 * scale), h = Math.round(h0 * scale)
      canvas.width = w
      canvas.height = h
      ctx.drawImage(img, 0, 0, w, h)

      if (detector) {
        try {
          const [hit] = await detector.detect(canvas)
          if (hit?.rawValue) return hit.rawValue
        } catch { /* use jsQR */ }
      }
      const hit = jsQR(ctx.getImageData(0, 0, w, h).data, w, h, { inversionAttempts: 'attemptBoth' })
      if (hit?.data) return hit.data
      if (scale === 1) break   // photo is already smaller than the remaining sizes
    }
    return null
  } finally {
    img.close?.()
    canvas.width = canvas.height = 0   // release the canvas memory right away on iOS
  }
}
