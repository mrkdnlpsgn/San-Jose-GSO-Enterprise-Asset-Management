// Single shared EventSource for real-time asset/maintenance/disposal updates.
// Multiple pages subscribe through this module instead of each opening their
// own connection (browsers cap concurrent HTTP/1.1 connections per origin).
const EVENT_TYPES = ['asset', 'maintenance', 'disposal', 'presence']

let eventSource = null
let refCount = 0
const listeners = { asset: new Set(), maintenance: new Set(), disposal: new Set(), presence: new Set() }

function ensureConnection() {
  if (eventSource) return
  const base = import.meta.env.VITE_API_BASE_URL || '/api'
  eventSource = new EventSource(`${base}/events/stream`, { withCredentials: true })
  EVENT_TYPES.forEach((type) => {
    eventSource.addEventListener(type, (e) => {
      let payload
      try { payload = JSON.parse(e.data) } catch { return }
      listeners[type].forEach((cb) => cb(payload))
    })
  })
}

function teardownIfUnused() {
  if (refCount <= 0 && eventSource) {
    eventSource.close()
    eventSource = null
  }
}

export function subscribeToEvent(type, callback) {
  if (!EVENT_TYPES.includes(type)) throw new Error(`Unknown SSE event type: ${type}`)
  ensureConnection()
  refCount += 1
  listeners[type].add(callback)
  return () => {
    listeners[type].delete(callback)
    refCount -= 1
    teardownIfUnused()
  }
}
