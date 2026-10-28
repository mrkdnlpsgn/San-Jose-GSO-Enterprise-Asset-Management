import { useCallback, useEffect, useRef, useState } from 'react'
import { useSelector } from 'react-redux'
import { getEditRequests } from '../services/assetHistoryService'
import { getUsers } from '../services/userService'
import { getDashboardSummary } from '../services/dashboardService'
import { usePolling } from './usePolling'
import { useEventStream } from './useEventStream'

// The bell's notifications - the same things the mobile app's bell gathers, and the only place
// the web shows them: staff requests waiting for an admin, your own requests that are pending or
// were rejected, accounts with no office, and asset data problems (each listing up to 10 of the
// assets behind it, as sent by /dashboard/summary).
// Each one has a `key` (what kind of notification it is) and a `count`; a rise in the count is
// what makes it unread. `category` is the kind of action it asks for - the panel filters by it.

export const NOTIFICATION_CATEGORIES = {
  reminder: { label: 'Reminders' },
  approval: { label: 'Approvals' },
  pending:  { label: 'Pending' },
  rejected: { label: 'Rejected' },
  account:  { label: 'Accounts' },
  asset:    { label: 'Asset issues' },
}

const REQUEST_KINDS = {
  MAINTENANCE: { one: 'maintenance request', many: 'maintenance requests' },
  DISPOSAL:    { one: 'disposal request', many: 'disposal requests' },
  TRANSFER:    { one: 'transfer request', many: 'transfer requests' },
}

const REJECTED_RECENT_DAYS = 14
const POLL_MS = 60000
const REQUESTS_LINK = (status) => `/asset-history?view=requests&status=${status}`

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`

// What a notification points to, for the page it opens to highlight (see useHighlight): requests
// are keyed like Asset History's rows, assets by id, accounts by user id.
const requestKey = (r) => `${r.kind}-${r.recordId}`
const assetIds = (att) => att.ids ?? (att.items ?? []).map((x) => x.id)

// "2 maintenance, 1 transfer"
function kindBreakdown(requests) {
  const counts = {}
  requests.forEach((r) => { counts[r.kind] = (counts[r.kind] ?? 0) + 1 })
  return Object.entries(counts).map(([k, n]) => `${n} ${k.toLowerCase()}`).join(', ')
}

function examples(att) {
  const shown = (att.items ?? []).slice(0, 2).map((x) => x.propertyNumber).filter(Boolean).join(', ')
  return att.count > 2 ? `${shown} and ${att.count - 2} more` : shown
}

function build({ role, officeId, requests, accounts, summary }) {
  const items = []
  const isAdmin = role === 'ADMIN'

  // A staff account only sees its office's assets, so without one it sees nothing.
  if (role === 'STAFF' && !officeId) items.push({
    key: 'my-no-office', category: 'account', tone: 'amber', count: 1,
    title: 'Your account has no office assigned yet',
    detail: 'There are no assets to show until an administrator assigns you one on the Personnel page. Then sign in again.',
  })

  if (isAdmin) {
    const pending = requests.filter((r) => r.approvalStatus === 'PENDING_APPROVAL')
    // An Admin-Staff account's "Notify admin": one per request, newest reminder first. The count
    // is how many times it was reminded, so every new reminder makes it unread again.
    pending.filter((r) => r.reminderCount > 0)
      .sort((a, b) => new Date(b.lastRemindedAt || 0) - new Date(a.lastRemindedAt || 0))
      .forEach((r) => {
        const kind = REQUEST_KINDS[r.kind]?.one ?? 'request'
        items.push({
          key: `reminder-${requestKey(r)}`, category: 'reminder', tone: 'amber', count: r.reminderCount,
          title: `Reminder: the ${kind} for ${r.propertyNumber} is still waiting for approval`,
          detail: `Filed by ${r.requestedByName || 'staff'}. ${r.lastRemindedByName || 'Admin-Staff'} reminded you${r.reminderCount > 1 ? ` (${r.reminderCount} times)` : ''}.`,
          to: REQUESTS_LINK('PENDING_APPROVAL'), highlight: [requestKey(r)],
        })
      })
    // One per request kind, so "Approvals" can be read at a glance.
    Object.entries(REQUEST_KINDS).forEach(([kind, label]) => {
      const ofKind = pending.filter((r) => r.kind === kind)
      const n = ofKind.length
      if (n === 0) return
      items.push({
        key: `pending-approvals-${kind.toLowerCase()}`, category: 'approval', tone: 'amber', count: n,
        title: `${plural(n, label.one, label.many)} ${n === 1 ? 'is' : 'are'} waiting for your approval`,
        detail: 'Filed by staff. Open it to approve or reject.',
        to: REQUESTS_LINK('PENDING_APPROVAL'), highlight: ofKind.map(requestKey),
      })
    })
    const noOffice = (accounts ?? []).filter((a) => a.role === 'STAFF' && a.isActive && !a.officeId && !a.officeName)
    if (noOffice.length > 0) {
      const names = noOffice.slice(0, 2).map((a) => a.fullName || a.username).join(', ')
      items.push({
        key: 'staff-no-office', category: 'account', tone: 'amber', count: noOffice.length,
        title: `${plural(noOffice.length, 'staff account has', 'staff accounts have')} no office assigned`,
        detail: `${names}${noOffice.length > 2 ? ' and others' : ''} can't see any assets until an office is assigned.`,
        to: '/personnel', highlight: noOffice.map((a) => a.id),
      })
    }
  } else {
    // Staff and Admin-Staff: the requests they filed.
    const cutoff = Date.now() - REJECTED_RECENT_DAYS * 86400000
    const rejected = requests.filter((r) => r.approvalStatus === 'REJECTED'
      && new Date(r.reviewedAt || r.requestedAt || 0).getTime() >= cutoff)
    if (rejected.length > 0) {
      items.push({
        key: 'my-rejected', category: 'rejected', tone: 'red', count: rejected.length,
        title: rejected.length === 1 ? 'Your request was rejected' : `${rejected.length} of your requests were rejected`,
        detail: `${kindBreakdown(rejected)}. Open it to read the reason and fix it.`,
        to: REQUESTS_LINK('REJECTED'), highlight: rejected.map(requestKey),
      })
    }
    const pending = requests.filter((r) => r.approvalStatus === 'PENDING_APPROVAL')
    if (pending.length > 0) {
      items.push({
        key: 'my-pending', category: 'pending', tone: 'slate', count: pending.length,
        title: pending.length === 1 ? 'Your request is waiting for approval' : `${pending.length} of your requests are waiting for approval`,
        detail: `${kindBreakdown(pending)}. An administrator still has to review ${pending.length === 1 ? 'it' : 'them'}.`,
        to: REQUESTS_LINK('PENDING_APPROVAL'), highlight: pending.map(requestKey),
      })
    }
  }

  const att = summary?.attention ?? {}
  const unserviceable = att.unserviceableNoDisposal ?? { count: 0 }
  if (unserviceable.count > 0) items.push({
    key: 'unserviceable-no-disposal', category: 'asset', tone: 'red', count: unserviceable.count,
    title: `${plural(unserviceable.count, 'unserviceable asset has', 'unserviceable assets have')} no disposal record yet`,
    detail: examples(unserviceable), assets: unserviceable.items, highlight: assetIds(unserviceable), to: '/assets?condition=UNSERVICEABLE',
  })
  const noAccountable = att.noAccountable ?? { count: 0 }
  if (noAccountable.count > 0) items.push({
    key: 'no-accountable', category: 'asset', tone: 'amber', count: noAccountable.count,
    title: `${plural(noAccountable.count, 'asset has', 'assets have')} no accountable person`,
    detail: examples(noAccountable), assets: noAccountable.items, highlight: assetIds(noAccountable), to: '/assets',
  })
  const noOffice = att.noOffice ?? { count: 0 }
  if (isAdmin && noOffice.count > 0) items.push({
    key: 'asset-no-office', category: 'asset', tone: 'amber', count: noOffice.count,
    title: `${plural(noOffice.count, 'asset is', 'assets are')} not assigned to an office`,
    detail: examples(noOffice), assets: noOffice.items, highlight: assetIds(noOffice), to: '/assets',
  })
  return items
}

// What this account has already seen, kept in this browser per account: the counts when the
// panel was last opened. Anything above them is unread.
const storageKey = (username) => `notifications.${username}`

function readSeen(username) {
  try {
    const raw = localStorage.getItem(storageKey(username))
    return raw ? JSON.parse(raw) : {}
  } catch {
    return {}
  }
}

function writeSeen(username, seen) {
  try { localStorage.setItem(storageKey(username), JSON.stringify(seen)) } catch { /* private mode etc. */ }
}

export function useNotifications() {
  const user = useSelector((s) => s.auth.user)
  const role = user?.role
  const username = user?.username
  const [items, setItems]     = useState([])
  const [loading, setLoading] = useState(true)
  const [failed, setFailed]   = useState(false)
  const [seen, setSeen]       = useState(() => (username ? readSeen(username) : {}))

  useEffect(() => { setSeen(username ? readSeen(username) : {}) }, [username])

  const load = useCallback(async () => {
    if (!username) return
    const [reqRes, userRes, sumRes] = await Promise.all([
      // Admin-Staff may list everyone's requests; its notifications are about the ones it filed.
      getEditRequests(role === 'ADMIN_STAFF' ? user?.id : undefined).catch(() => null),
      role === 'ADMIN' ? getUsers().catch(() => null) : Promise.resolve(null),
      getDashboardSummary().catch(() => null),
    ])
    setFailed(!reqRes && !sumRes)
    setItems(build({ role, officeId: user?.officeId, requests: reqRes?.data ?? [], accounts: userRes?.data, summary: sumRes?.data }))
    setLoading(false)
  }, [username, role, user?.id, user?.officeId])

  useEffect(() => { load() }, [load])
  usePolling(load, POLL_MS)

  // Live updates come in bursts (a bulk import is one event per asset): reload once they settle.
  const reloadTimer = useRef(null)
  const reloadSoon = useCallback(() => {
    clearTimeout(reloadTimer.current)
    reloadTimer.current = setTimeout(load, 1500)
  }, [load])
  useEffect(() => () => clearTimeout(reloadTimer.current), [])
  useEventStream('asset', reloadSoon)
  useEventStream('maintenance', reloadSoon)
  useEventStream('disposal', reloadSoon)

  const isUnread = useCallback((n) => n.count > (seen[n.key] ?? 0), [seen])
  const unreadCount = items.filter(isUnread).length

  const markAllSeen = useCallback(() => {
    if (!username || items.every((n) => !isUnread(n))) return
    const next = { ...seen }
    items.forEach((n) => { next[n.key] = n.count })
    setSeen(next)
    writeSeen(username, next)
  }, [username, items, seen, isUnread])

  return { items, loading, failed, unreadCount, isUnread, markAllSeen, refresh: load }
}
