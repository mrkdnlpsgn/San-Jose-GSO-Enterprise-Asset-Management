import { useDispatch, useSelector } from 'react-redux'
import { useEventStream } from '../hooks/useEventStream'
import { useToast } from '../context/ToastContext'
import { setOnlineUsers } from '../store/slices/presenceSlice'

function assetMessage(action, id, data, actor) {
  if (action === 'DELETED') return `${actor} deleted asset ${data?.propertyNumber || `#${id}`}`
  if (!data) return null
  return `${actor} ${action === 'CREATED' ? 'added' : 'updated'} asset ${data.propertyNumber}`
}

function recordMessage(kind, action, data, actor) {
  const propertyNumber = data?.asset?.propertyNumber
  const suffix = propertyNumber ? ` (${propertyNumber})` : ''
  if (action === 'DELETED') return `${actor} deleted a ${kind} record${suffix}`
  if (!data) return null
  return `${actor} ${action === 'CREATED' ? 'added' : 'updated'} a ${kind} record${suffix}`
}

// Mounted once for the whole authenticated app (see App.jsx) — turns the SSE
// stream already wired up for list-syncing into user-visible toasts for other
// users' actions, and keeps the online-users list (Sidebar) in sync. Skips
// "CHANGED" cascade events (no descriptive data, always paired with an asset
// event in the same request) and anything the current user did themselves
// (their own page already shows a synchronous toast for that).
function RealtimeSync() {
  const dispatch = useDispatch()
  const toast = useToast()
  const currentUsername = useSelector((s) => s.auth.user?.username)

  useEventStream('presence', ({ data }) => {
    dispatch(setOnlineUsers(data || []))
  })

  useEventStream('asset', ({ action, id, data, actorUsername }) => {
    if (action === 'CHANGED' || !actorUsername || actorUsername === currentUsername) return
    const message = assetMessage(action, id, data, actorUsername)
    if (message) toast.show(message, action === 'DELETED' ? 'warning' : 'info')
  })

  useEventStream('maintenance', ({ action, data, actorUsername }) => {
    if (action === 'CHANGED' || !actorUsername || actorUsername === currentUsername) return
    const message = recordMessage('maintenance', action, data, actorUsername)
    if (message) toast.show(message, action === 'DELETED' ? 'warning' : 'info')
  })

  useEventStream('disposal', ({ action, data, actorUsername }) => {
    if (action === 'CHANGED' || !actorUsername || actorUsername === currentUsername) return
    const message = recordMessage('disposal', action, data, actorUsername)
    if (message) toast.show(message, action === 'DELETED' ? 'warning' : 'info')
  })

  return null
}

export default RealtimeSync
