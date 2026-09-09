import { useEffect, useRef } from 'react'

// Periodically calls `callback` in the background so lists stay in sync
// without a manual refresh — pauses while the tab isn't visible (no point
// paying for requests nobody can see) and fires once immediately when the
// tab becomes visible again, so data doesn't look stale coming back.
export function usePolling(callback, intervalMs) {
  const callbackRef = useRef(callback)
  callbackRef.current = callback

  useEffect(() => {
    let intervalId = null

    const start = () => {
      if (intervalId) return
      intervalId = setInterval(() => callbackRef.current(), intervalMs)
    }
    const stop = () => {
      if (!intervalId) return
      clearInterval(intervalId)
      intervalId = null
    }

    const onVisibilityChange = () => {
      if (document.hidden) {
        stop()
      } else {
        callbackRef.current()
        start()
      }
    }

    if (!document.hidden) start()
    document.addEventListener('visibilitychange', onVisibilityChange)

    return () => {
      stop()
      document.removeEventListener('visibilitychange', onVisibilityChange)
    }
  }, [intervalMs])
}
