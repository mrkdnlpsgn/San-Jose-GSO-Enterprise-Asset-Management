import { useState, useEffect, useCallback, useMemo } from 'react'
import { useToast } from '../../context/ToastContext'
import MainLayout from '../../components/layout/MainLayout'
import Modal from '../../components/common/Modal'
import { getAccountableHistory, getEditRequests } from '../../services/assetHistoryService'
import { getUsers } from '../../services/userService'
import { useDebounce } from '../../hooks/useDebounce'
import { useAuth } from '../../hooks/useAuth'
import { useEventStream } from '../../hooks/useEventStream'
import { ApprovalActions, RejectRequestModal } from '../../components/common/ApprovalControls'
import { approveMaintenance, rejectMaintenance } from '../../services/maintenanceService'
import { approveDisposal, rejectDisposal } from '../../services/disposalService'

const EVENT_TYPES = ['REGISTERED', 'ASSIGNED', 'TRANSFERRED', 'MAINTENANCE', 'DISPOSAL', 'ARCHIVED']

const EVENT_BADGE = {
  REGISTERED:  'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  ASSIGNED:    'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  TRANSFERRED: 'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
  MAINTENANCE: 'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  DISPOSAL:    'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
  ARCHIVED:    'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20',
}

// Where a staff request (maintenance / disposal) stands.
const REQUEST_STATUS = {
  PENDING_APPROVAL: { label: 'Pending',  cls: 'bg-amber-500/10 text-amber-500 ring-1 ring-amber-500/20' },
  APPROVED:         { label: 'Approved', cls: 'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20' },
  REJECTED:         { label: 'Rejected', cls: 'bg-red-500/10 text-red-400 ring-1 ring-red-500/20' },
}

function formatDate(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}

const SELECT_CLASS = 'appearance-none text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 px-3 py-2 pr-8 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all disabled:opacity-70 disabled:cursor-not-allowed'

function Chevron() {
  return (
    <div className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 dark:text-zinc-500">
      <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
    </div>
  )
}

const PAGE_SIZE = 10

function withinDate(dt, dateFilter, now) {
  if (dateFilter === 'all') return true
  const t = new Date(dt).getTime()
  if (dateFilter === 'today') {
    const today = new Date(); today.setHours(0, 0, 0, 0)
    return t >= today.getTime()
  }
  const days = dateFilter === '7d' ? 7 : 30
  return now - t <= days * 86400000
}

function AssetHistory() {
  const toast = useToast()
  const { user } = useAuth()
  const isAdmin = user?.role === 'ADMIN'

  const [view, setView]           = useState('history')   // 'history' | 'requests'
  const [history, setHistory]     = useState([])
  const [requests, setRequests]   = useState([])
  const [loading, setLoading]     = useState(true)
  const [users, setUsers]         = useState([])
  const [search, setSearch]       = useState('')
  const [filterType, setFilterType] = useState('')
  const [filterStatus, setFilterStatus] = useState('')
  const [dateFilter, setDateFilter] = useState('all')
  // Admin can narrow to one person ('' = everyone). Staff aren't filtered here — the backend
  // already limits them to their accountable assets' history and their own requests.
  const [performer, setPerformer] = useState('')
  const [viewing, setViewing]     = useState(null)
  const [rejecting, setRejecting] = useState(null)
  const [page, setPage]           = useState(1)

  const debouncedSearch = useDebounce(search, 300)

  const fetchHistory = useCallback(async (q = '', silent = false) => {
    if (!silent) setLoading(true)
    try {
      const { data } = await getAccountableHistory(q)
      setHistory(data)
    } catch {
      toast.show('Failed to load asset history.', 'error')
    } finally {
      setLoading(false)
    }
  }, [toast])

  const fetchRequests = useCallback(async (userId, silent = false) => {
    if (!silent) setLoading(true)
    try {
      const { data } = await getEditRequests(userId)
      setRequests(data)
    } catch {
      toast.show('Failed to load requests.', 'error')
    } finally {
      setLoading(false)
    }
  }, [toast])

  useEffect(() => {
    if (isAdmin) getUsers().then(({ data }) => setUsers(data)).catch(() => {})
  }, [isAdmin])

  useEffect(() => {
    if (view === 'history') fetchHistory(debouncedSearch)
    else fetchRequests(performer || null)
  }, [view, debouncedSearch, performer, fetchHistory, fetchRequests])

  // Admin approves / rejects a staff request right from the list.
  const handleApprove = async (r) => {
    try {
      await (r.kind === 'MAINTENANCE' ? approveMaintenance : approveDisposal)(r.recordId)
      toast.show(`Request approved — ${r.propertyNumber} is now ${r.kind === 'MAINTENANCE' ? 'under maintenance' : 'disposed'}.`, 'success')
      fetchRequests(performer || null)
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to approve the request.', 'error')
    }
  }

  const handleReject = async (note) => {
    await (rejecting.kind === 'MAINTENANCE' ? rejectMaintenance : rejectDisposal)(rejecting.recordId, note)
    toast.show('Request rejected.', 'success')
    fetchRequests(performer || null)
  }

  // Keep the list current as assets / requests change anywhere (no loading flicker).
  const refreshSilently = () => {
    if (view === 'history') fetchHistory(debouncedSearch, true)
    else fetchRequests(performer || null, true)
  }
  useEventStream('asset', refreshSilently)
  useEventStream('maintenance', refreshSilently)
  useEventStream('disposal', refreshSilently)

  useEffect(() => { setPage(1) }, [view, debouncedSearch, filterType, filterStatus, dateFilter, performer])

  const now = Date.now()
  const filteredHistory = useMemo(() => history.filter((h) => {
    if (performer && String(h.performedBy?.id) !== performer) return false
    if (filterType && h.eventType !== filterType) return false
    return withinDate(h.eventDate || h.createdAt, dateFilter, now)
  }), [history, performer, filterType, dateFilter, now])

  const filteredRequests = useMemo(() => {
    const q = debouncedSearch.trim().toLowerCase()
    return requests.filter((r) => {
      if (filterStatus && r.approvalStatus !== filterStatus) return false
      if (q && ![r.propertyNumber, r.parNumber, r.assetDescription, r.requestedByName, r.detail]
        .some((v) => v?.toLowerCase().includes(q))) return false
      return withinDate(r.requestedAt, dateFilter, now)
    })
  }, [requests, filterStatus, debouncedSearch, dateFilter, now])

  const rows       = view === 'history' ? filteredHistory : filteredRequests
  const total      = view === 'history' ? history.length : requests.length
  const totalPages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE))
  const paged      = rows.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)
  const noun       = view === 'history' ? ['entry', 'entries'] : ['request', 'requests']

  return (
    <MainLayout>
      <div className="flex flex-col gap-3 mb-5">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
          <div className="relative w-full sm:max-w-xs">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
            </svg>
            <input type="text" placeholder={view === 'history' ? 'Search asset, event type, person…' : 'Search asset, person, details…'}
              value={search} onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
          </div>
          <div className="inline-flex self-start sm:self-auto rounded-lg border border-slate-200 dark:border-zinc-700 p-0.5 bg-white dark:bg-zinc-900">
            {[['history', 'History'], ['requests', isAdmin ? 'Staff Requests' : 'My Requests']].map(([v, label]) => (
              <button key={v} onClick={() => setView(v)}
                className={`text-xs px-3 py-1.5 rounded-md font-medium transition-all ${
                  view === v
                    ? 'bg-slate-900 text-white dark:bg-white dark:text-zinc-900'
                    : 'text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800'
                }`}>{label}</button>
            ))}
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative">
            <select value={performer} onChange={(e) => setPerformer(e.target.value)} disabled={!isAdmin}
              title={isAdmin ? 'Show changes made by one person' : view === 'history' ? 'Changes to the assets you are accountable for' : 'Your own requests'}
              className={SELECT_CLASS}>
              {isAdmin ? (
                <>
                  <option value="">{view === 'history' ? 'Performed by: everyone' : 'Requested by: all staff'}</option>
                  {users.map((u) => <option key={u.id} value={String(u.id)}>{u.fullName || u.username}{u.role === 'ADMIN' ? ' (Admin)' : ''}</option>)}
                </>
              ) : (
                <option value="">{view === 'history' ? 'Assets you are accountable for' : `Requested by: ${user?.fullName || user?.username} (you)`}</option>
              )}
            </select>
            <Chevron />
          </div>
          {view === 'history' ? (
            <div className="relative">
              <select value={filterType} onChange={(e) => setFilterType(e.target.value)} className={SELECT_CLASS}>
                <option value="">All Event Types</option>
                {EVENT_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
              </select>
              <Chevron />
            </div>
          ) : (
            <div className="relative">
              <select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} className={SELECT_CLASS}>
                <option value="">All Statuses</option>
                {Object.entries(REQUEST_STATUS).map(([k, { label }]) => <option key={k} value={k}>{label}</option>)}
              </select>
              <Chevron />
            </div>
          )}
          {['all', 'today', '7d', '30d'].map((d) => (
            <button key={d} onClick={() => setDateFilter(d)}
              className={`text-xs px-2.5 py-1.5 rounded-lg border font-medium transition-all ${
                dateFilter === d
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-zinc-900 border-slate-900 dark:border-white'
                  : 'border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800'
              }`}>
              {d === 'all' ? 'All time' : d === 'today' ? 'Today' : d === '7d' ? 'Last 7 days' : 'Last 30 days'}
            </button>
          ))}
        </div>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">
            {view === 'history' ? 'Asset History' : isAdmin ? 'Staff Requests' : 'My Requests'}
          </p>
          {!loading && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {rows.length}{rows.length !== total ? ` of ${total}` : ''} {rows.length !== 1 ? noun[1] : noun[0]}
            </span>
          )}
        </div>

        {loading ? (
          <div className="divide-y divide-slate-100 dark:divide-zinc-800">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="flex items-center gap-4 px-5 py-3.5">
                <div className="animate-pulse h-3 w-32 rounded bg-slate-200 dark:bg-zinc-800" />
                <div className="animate-pulse h-5 w-20 rounded-full bg-slate-200 dark:bg-zinc-800" />
                <div className="animate-pulse h-3 w-24 rounded bg-slate-200 dark:bg-zinc-800 ml-auto" />
              </div>
            ))}
          </div>
        ) : rows.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-2 text-zinc-600">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            <p className="text-sm text-zinc-500">
              {total === 0
                ? (view === 'history' ? 'No history recorded yet.' : 'No requests yet.')
                : 'Nothing matches your filters.'}
            </p>
          </div>
        ) : view === 'history' ? (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Asset', 'Event Type', 'From Office', 'Performed By', 'Date', 'Notes'].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((h) => (
                  <tr key={h.id} onClick={() => setViewing(h)}
                    className="cursor-pointer hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                    <td className="px-5 py-3.5">
                      <p className="font-mono text-xs text-slate-500 dark:text-zinc-400">{h.asset?.propertyNumber}</p>
                      {h.asset?.parNumber && <p className="font-mono text-2xs text-slate-400 dark:text-zinc-500">PAR: {h.asset.parNumber}</p>}
                      <p className="text-sm font-medium text-slate-900 dark:text-white truncate max-w-[160px]">{h.asset?.description}</p>
                    </td>
                    <td className="px-5 py-3.5 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${EVENT_BADGE[h.eventType] || 'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20'}`}>
                        {h.eventType}
                      </span>
                    </td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{h.fromOffice?.officeName || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{h.performedBy?.fullName || h.performedBy?.username || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{formatDate(h.eventDate || h.createdAt)}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs max-w-[160px]">
                      <span className="block truncate" title={h.notes}>{h.notes || '—'}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Asset', 'Request', 'Details', 'Requested By', 'Requested', 'Status', 'Reviewed', ...(isAdmin ? [''] : [])].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((r) => {
                  const status = REQUEST_STATUS[r.approvalStatus] || { label: r.approvalStatus, cls: 'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20' }
                  return (
                    <tr key={`${r.kind}-${r.recordId}`}>
                      <td className="px-5 py-3.5">
                        <p className="font-mono text-xs text-slate-500 dark:text-zinc-400">{r.propertyNumber}</p>
                        {r.parNumber && <p className="font-mono text-2xs text-slate-400 dark:text-zinc-500">PAR: {r.parNumber}</p>}
                        <p className="text-sm font-medium text-slate-900 dark:text-white truncate max-w-[160px]">{r.assetDescription}</p>
                      </td>
                      <td className="px-5 py-3.5 whitespace-nowrap">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${EVENT_BADGE[r.kind]}`}>
                          {r.kind === 'MAINTENANCE' ? 'Under Maintenance' : 'Disposal'}
                        </span>
                      </td>
                      <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs max-w-[200px]">
                        <span className="block truncate" title={r.detail}>{r.detail || '—'}</span>
                      </td>
                      <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{r.requestedByName || '—'}</td>
                      <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{formatDate(r.requestedAt)}</td>
                      <td className="px-5 py-3.5 whitespace-nowrap">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${status.cls}`}>{status.label}</span>
                      </td>
                      <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs max-w-[200px]">
                        {r.approvalStatus === 'PENDING_APPROVAL' ? '—' : (
                          <>
                            <p className="whitespace-nowrap">{r.reviewedByName || '—'} · {formatDate(r.reviewedAt)}</p>
                            {r.reviewNote && <p className="truncate text-red-400" title={r.reviewNote}>Reason: {r.reviewNote}</p>}
                          </>
                        )}
                      </td>
                      {isAdmin && (
                        <td className="px-5 py-3.5">
                          <div className="flex items-center justify-end gap-1">
                            <ApprovalActions record={r} onApprove={handleApprove} onReject={setRejecting} />
                          </div>
                        </td>
                      )}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        {!loading && rows.length > PAGE_SIZE && (
          <div className="px-5 py-3 border-t border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
            <p className="text-xs text-slate-400 dark:text-zinc-500">
              {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, rows.length)} of {rows.length}
            </p>
            <div className="flex items-center gap-1">
              <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}
                className="px-2.5 py-1.5 text-xs rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">
                Prev
              </button>
              <span className="text-xs text-slate-400 px-2">{page} / {totalPages}</span>
              <button onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                className="px-2.5 py-1.5 text-xs rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">
                Next
              </button>
            </div>
          </div>
        )}
      </div>

      {rejecting && (
        <RejectRequestModal
          record={rejecting}
          describe={(r) => `${r.propertyNumber} — ${r.assetDescription}`}
          onClose={() => setRejecting(null)}
          onConfirm={handleReject}
        />
      )}

      {viewing && (
        <Modal title="Event Details" subtitle={viewing.asset?.propertyNumber} onClose={() => setViewing(null)} size="md">
          <div className="space-y-0">
            <Field label="Asset" value={viewing.asset?.description} />
            <Field label="PAR Number" value={viewing.asset?.parNumber} />
            <Field label="Event Type" value={
              <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${EVENT_BADGE[viewing.eventType] || 'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20'}`}>
                {viewing.eventType}
              </span>
            } />
            <Field label="From Office" value={viewing.fromOffice?.officeName} />
            <Field label="Performed By" value={viewing.performedBy?.fullName || viewing.performedBy?.username} />
            <Field label="Date" value={formatDate(viewing.eventDate || viewing.createdAt)} />
            <Field label="Notes" value={viewing.notes} />
          </div>
        </Modal>
      )}
    </MainLayout>
  )
}

function Field({ label, value }) {
  return (
    <div className="flex items-start gap-2 py-2.5 border-b border-slate-100 dark:border-zinc-800/60 last:border-0">
      <span className="text-xs text-slate-400 dark:text-zinc-500 w-28 flex-shrink-0 pt-0.5">{label}</span>
      <span className="text-sm text-slate-900 dark:text-zinc-200 font-medium break-words">{value ?? '—'}</span>
    </div>
  )
}

export default AssetHistory
