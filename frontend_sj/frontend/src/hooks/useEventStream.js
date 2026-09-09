import { useEffect, useRef } from 'react'
import { subscribeToEvent } from '../services/sseClient'

// Subscribes to a real-time event channel ('asset' | 'maintenance' | 'disposal').
// onEvent receives { action, id, data } — see SseEmitterService on the backend
// for the contract (data present -> upsert, action 'DELETED' -> remove by id,
// otherwise refetch).
export function useEventStream(type, onEvent) {
  const handlerRef = useRef(onEvent)
  handlerRef.current = onEvent

  useEffect(() => {
    return subscribeToEvent(type, (payload) => handlerRef.current(payload))
  }, [type])
}
