import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import jsQR from 'jsqr'

// Full-screen live QR scanner for phones and tablets: the camera fills the screen, a
// square guide shows where to hold the code, and it reads on its own — no shutter
// button. Only the middle of the camera frame (around the guide) is decoded, shrunk to
// DECODE_SIZE, which keeps each pass fast on older phones.
const DECODE_SIZE = 800
const SCAN_EVERY_MS = 120

export default function QrScannerOverlay({ onDetected, onClose }) {
  const videoRef = useRef(null)
  const onDetectedRef = useRef(onDetected)
  const [error, setError] = useState('')
  const [ready, setReady] = useState(false)

  useEffect(() => { onDetectedRef.current = onDetected }, [onDetected])

  useEffect(() => {
    let stopped = false
    let stream = null
    let raf = 0
    let busy = false
    let last = 0
    const canvas = document.createElement('canvas')
    const ctx = canvas.getContext('2d', { willReadFrequently: true })
    const detector = 'BarcodeDetector' in window ? new window.BarcodeDetector({ formats: ['qr_code'] }) : null

    const decode = async (video) => {
      const vw = video.videoWidth, vh = video.videoHeight
      const side = Math.min(vw, vh)
      const size = Math.min(side, DECODE_SIZE)
      canvas.width = canvas.height = size
      ctx.drawImage(video, (vw - side) / 2, (vh - side) / 2, side, side, 0, 0, size, size)
      if (detector) {
        try {
          const [hit] = await detector.detect(canvas)
          if (hit?.rawValue) return hit.rawValue
        } catch { /* use jsQR */ }
      }
      return jsQR(ctx.getImageData(0, 0, size, size).data, size, size, { inversionAttempts: 'attemptBoth' })?.data
    }

    const tick = async (t) => {
      if (stopped) return
      raf = requestAnimationFrame(tick)
      const video = videoRef.current
      if (busy || t - last < SCAN_EVERY_MS || !video || video.readyState < 2 || !video.videoWidth) return
      last = t
      busy = true
      try {
        const text = await decode(video)
        if (text && !stopped) {
          stopped = true
          navigator.vibrate?.(80)
          onDetectedRef.current(text)
        }
      } finally {
        busy = false
      }
    }

    async function start() {
      if (!navigator.mediaDevices?.getUserMedia) {
        setError('This browser can’t open the camera. Type the Property Number instead.')
        return
      }
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } },
          audio: false,
        })
        if (stopped) { stream.getTracks().forEach((t) => t.stop()); return }
        const [track] = stream.getVideoTracks()
        track?.applyConstraints?.({ advanced: [{ focusMode: 'continuous' }] }).catch(() => {})
        const video = videoRef.current
        video.srcObject = stream
        await video.play()
        setReady(true)
        raf = requestAnimationFrame(tick)
      } catch (err) {
        if (stopped) return
        setError(
          err?.name === 'NotAllowedError'
            ? 'Camera access is blocked. Allow camera access for this site in your browser settings, then try again.'
            : err?.name === 'NotFoundError'
            ? 'No camera was found on this device. Type the Property Number instead.'
            : 'Couldn’t open the camera. Close other apps using it and try again.'
        )
      }
    }

    start()
    return () => {
      stopped = true
      cancelAnimationFrame(raf)
      stream?.getTracks().forEach((t) => t.stop())
    }
  }, [])

  // Lock page scroll and let Escape close the scanner while it's open.
  useEffect(() => {
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const onKey = (e) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => {
      document.body.style.overflow = prev
      window.removeEventListener('keydown', onKey)
    }
  }, [onClose])

  const corner = 'absolute w-12 h-12 border-white'

  return createPortal(
    <div role="dialog" aria-modal="true" aria-label="Scan QR code" className="fixed inset-0 z-[1000] bg-black text-white">
      <video ref={videoRef} className="absolute inset-0 h-full w-full object-cover" playsInline muted autoPlay />

      {!error && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none" aria-hidden="true">
          {/* The huge shadow darkens everything outside the guide square. */}
          <div className="relative w-[72vmin] h-[72vmin] max-w-[420px] max-h-[420px] rounded-md" style={{ boxShadow: '0 0 0 100vmax rgba(0,0,0,0.6)' }}>
            <span className={`${corner} top-0 left-0 border-t-4 border-l-4 rounded-tl-md`} />
            <span className={`${corner} top-0 right-0 border-t-4 border-r-4 rounded-tr-md`} />
            <span className={`${corner} bottom-0 left-0 border-b-4 border-l-4 rounded-bl-md`} />
            <span className={`${corner} bottom-0 right-0 border-b-4 border-r-4 rounded-br-md`} />
          </div>
        </div>
      )}

      <div className="absolute inset-x-0 top-0 px-5 pt-[max(1.5rem,env(safe-area-inset-top))] text-center">
        <p className="text-lg font-semibold" role="status">
          {error ? 'Camera unavailable' : ready ? 'Place the QR code inside the square' : 'Starting camera…'}
        </p>
        {!error && ready && <p className="mt-1 text-sm text-white/80">It will read on its own. Hold the phone steady.</p>}
      </div>

      {error && (
        <div className="absolute inset-0 flex items-center justify-center px-6">
          <p className="max-w-sm text-center text-base bg-white text-slate-900 rounded-lg px-5 py-4" role="alert">{error}</p>
        </div>
      )}

      <div className="absolute inset-x-0 bottom-0 px-5 pb-[max(1.5rem,env(safe-area-inset-bottom))]">
        <button
          type="button"
          onClick={onClose}
          className="w-full rounded-lg bg-white text-slate-900 px-4 py-4 text-base font-semibold focus:outline-none focus-visible:ring-4 focus-visible:ring-white/60"
        >
          Cancel
        </button>
      </div>
    </div>,
    document.body
  )
}
