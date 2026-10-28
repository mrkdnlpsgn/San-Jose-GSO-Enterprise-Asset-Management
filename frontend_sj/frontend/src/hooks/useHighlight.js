import { useCallback, useEffect, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'

// Opening a notification from the bell (NotificationBell) navigates here with
// state.highlight = { ids, title }: the records that notification is about. The page tints
// those rows and lists them first until the person clears it or opens another notification.
// ids are whatever the page keys its rows by (asset ids, "KIND-recordId" requests, user ids).
export function useHighlight() {
  const location = useLocation()
  const navigate = useNavigate()
  const fromState = location.state?.highlight
  const [highlight, setHighlight] = useState(() => toHighlight(fromState))

  // A new notification opened while already on this page replaces the highlight.
  useEffect(() => { if (fromState) setHighlight(toHighlight(fromState)) }, [location.key]) // eslint-disable-line react-hooks/exhaustive-deps

  const clear = useCallback(() => {
    setHighlight(null)
    // drop it from history too, so going back/forward or reloading doesn't bring it back
    navigate(`${location.pathname}${location.search}`, { replace: true, state: null })
  }, [navigate, location.pathname, location.search])

  return {
    ids: highlight?.ids ?? EMPTY,
    title: highlight?.title,
    active: !!highlight && highlight.ids.size > 0,
    clear,
  }
}

const EMPTY = new Set()

function toHighlight(h) {
  if (!h?.ids?.length) return null
  return { ids: new Set(h.ids.map(String)), title: h.title }
}

// Highlighted rows first (keeping their order), so they are on the first page / batch.
export function highlightedFirst(rows, ids, keyOf) {
  if (!ids.size) return rows
  const hit = []
  const rest = []
  rows.forEach((r) => (ids.has(String(keyOf(r))) ? hit : rest).push(r))
  return hit.length ? hit.concat(rest) : rows
}

// Row classes for a highlighted row: an amber tint with an accent bar on its left edge.
export const HIGHLIGHT_ROW = 'bg-amber-50 dark:bg-amber-500/10 shadow-[inset_3px_0_0_0] shadow-amber-500'
