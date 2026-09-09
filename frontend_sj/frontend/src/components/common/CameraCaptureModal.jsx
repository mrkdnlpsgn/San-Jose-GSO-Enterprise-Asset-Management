import { useEffect, useRef, useState } from 'react'
import Modal from './Modal'
import Button from './Button'

// `<input capture>` only opens a live camera on mobile browsers — desktop
// Chrome/Firefox/Edge silently ignore the `capture` attribute and fall back
// to the plain file picker, which is indistinguishable from "Upload Image".
// getUserMedia gives a real live preview + shutter on every platform
// (desktop webcam included) as long as the page is served over a secure
// context (https, or http://localhost — which is what docker-compose maps
// the frontend to).
export default function CameraCaptureModal({ onCapture, onClose }) {
  const videoRef = useRef(null)
  const streamRef = useRef(null)
  const [error, setError] = useState('')
  const [ready, setReady] = useState(false)

  useEffect(() => {
    let cancelled = false

    async function start() {
      if (!navigator.mediaDevices?.getUserMedia) {
        setError('Camera access is not supported in this browser.')
        return
      }
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: 'environment' } },
          audio: false,
        })
        if (cancelled) { stream.getTracks().forEach((t) => t.stop()); return }
        streamRef.current = stream
        if (videoRef.current) {
          videoRef.current.srcObject = stream
          await videoRef.current.play()
        }
        setReady(true)
      } catch (err) {
        if (cancelled) return
        setError(
          err?.name === 'NotAllowedError'
            ? 'Camera permission was denied. Allow camera access and try again, or use Upload Image instead.'
            : err?.name === 'NotFoundError'
            ? 'No camera was found on this device.'
            : 'Could not access the camera. Try Upload Image instead.'
        )
      }
    }

    start()
    return () => {
      cancelled = true
      streamRef.current?.getTracks().forEach((t) => t.stop())
    }
  }, [])

  const capture = () => {
    const video = videoRef.current
    if (!video || !video.videoWidth) return
    const canvas = document.createElement('canvas')
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    canvas.getContext('2d').drawImage(video, 0, 0)
    canvas.toBlob((blob) => {
      if (!blob) return
      const file = new File([blob], `asset-scan-${Date.now()}.jpg`, { type: 'image/jpeg' })
      onCapture(file)
    }, 'image/jpeg', 0.92)
  }

  return (
    <Modal title="Take Photo" size="md" onClose={onClose}>
      <div className="space-y-3">
        {error ? (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-3">
            {error}
          </div>
        ) : (
          <div className="relative rounded-lg overflow-hidden bg-black aspect-video">
            <video ref={videoRef} className="w-full h-full object-contain" playsInline muted />
            {!ready && (
              <div className="absolute inset-0 flex items-center justify-center text-sm text-zinc-400">
                Starting camera…
              </div>
            )}
          </div>
        )}

        <div className="flex justify-end gap-2 pt-1">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="button" size="md" disabled={!ready || !!error} onClick={capture}>
            Capture
          </Button>
        </div>
      </div>
    </Modal>
  )
}
