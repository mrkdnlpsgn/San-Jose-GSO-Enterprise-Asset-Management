import { useState, useEffect, useCallback, useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useToast } from '../../context/ToastContext'
import MainLayout from '../../components/layout/MainLayout'
import { getAccountableHistory, getEditRequests, remindAdmin } from '../../services/assetHistoryService'
import { getUsers } from '../../services/userService'
import { useDebounce } from '../../hooks/useDebounce'
import { useAuth } from '../../hooks/useAuth'
import { useEventStream } from '../../hooks/useEventStream'
import { RejectRequestModal } from '../../components/common/ApprovalControls'
import {
  SearchBox, FilterSelect, FilterBar, ListCard, RefreshButton, Pager, ListSkeleton, ListEmpty,
  DataTable, PrimaryCell, MutedCell, MappedBadge, ICON, fmtDate, personName, HighlightNotice,
} from '../../components/common/ListKit'
import DetailModal, { DetailGrid, DetailSection, DetailField, ModalAction } from '../../components/common/DetailModal'
import { approveMaintenance, rejectMaintenance } from '../../services/maintenanceService'
import { approveDisposal, rejectDisposal } from '../../services/disposalService'
import { approveTransfer, rejectTransfer } from '../../services/transferService'
import { seesAllAssets } from '../../utils/roles'
import { useHighlight, highlightedFirst } from '../../hooks/useHighlight'

// Only the events the system actually records (ASSIGNED / ARCHIVED are never logged).
const EVENT = {
  REGISTERED:  { label: 'Registered',  tone: 'blue' },
  TRANSFERRED: { label: 'Transferred', tone: 'violet' },
  MAINTENANCE: { label: 'Maintenance', tone: 'amber' },
  DISPOSAL:    { label: 'Disposal',    tone: 'red' },
}

// Staff request kinds: label in the list, the API calls, and what approving does.
const REQUEST_KIND = {
  MAINTENANCE: { label: 'Maintenance', tone: 'amber',  approve: approveMaintenance, reject: rejectMaintenance, done: 'is now under maintenance' },
  DISPOSAL:    { label: 'Disposal',    tone: 'red',    approve: approveDisposal,    reject: rejectDisposal,    done: 'is now disposed' },
  TRANSFER:    { label: 'Transfer',    tone: 'violet', approve: approveTransfer,    reject: rejectTransfer,    done: 'has been transferred' },
}

// Where a staff request (maintenance / disposal / transfer) stands.
const REQUEST_STATUS = {
  PENDING_APPROVAL: { label: 'Awaiting approval', tone: 'amber' },
  APPROVED:         { label: 'Approved',          tone: 'green' },
  REJECTED:         { label: 'Rejected',          tone: 'red' },
}

const WHEN = [['today', 'Today'], ['7d', 'Last 7 days'], ['30d', 'Last 30 days']]

const PAGE_SIZE = 5

function withinDate(dt, dateFilter, now) {
  if (!dateFilter) return true
  const t = new Date(dt).getTime()
  if (dateFilter === 'today') {
    const today = new Date(); today.setHours(0, 0, 0, 0)
    return t >= today.getTime()
  }
  const days = dateFilter === '7d' ? 7 : 30
  return now - t <= days * 86400000
}

const HISTORY_COLUMNS = [
  { key: 'asset', label: 'Asset', cell: (h, open) => (
    <PrimaryCell code={h.asset?.propertyNumber} title={h.asset?.description} open={open}
      extra={<div className="sm:hidden mt-1"><MappedBadge map={EVENT} value={h.eventType} /></div>} />
  ) },
  { key: 'event', label: 'Event', className: 'hidden sm:table-cell w-[9rem]', cell: (h) => <MappedBadge map={EVENT} value={h.eventType} /> },
  { key: 'who', label: 'Done by', className: 'hidden md:table-cell w-[22%]', cell: (h) => <MutedCell>{personName(h.performedBy)}</MutedCell> },
  { key: 'date', label: 'Date', className: 'hidden lg:table-cell w-[8.5rem]', cell: (h) => <MutedCell>{fmtDate(h.eventDate || h.createdAt)}</MutedCell> },
]

const REQUEST_COLUMNS = [
  { key: 'asset', label: 'Asset', cell: (r, open) => (
    <PrimaryCell code={r.propertyNumber} title={r.assetDescription} open={open}
      extra={<div className="sm:hidden mt-1"><MappedBadge map={REQUEST_STATUS} value={r.approvalStatus} /></div>} />
  ) },
  { key: 'kind', label: 'Request', className: 'hidden md:table-cell w-[8.5rem]', cell: (r) => <MappedBadge map={REQUEST_KIND} value={r.kind} /> },
  { key: 'status', label: 'Status', className: 'hidden sm:table-cell w-[10.5rem]', cell: (r) => <MappedBadge map={REQUEST_STATUS} value={r.approvalStatus} /> },
  { key: 'who', label: 'Requested by', className: 'hidden lg:table-cell w-[20%]', cell: (r) => <MutedCell>{r.requestedByName}</MutedCell> },
  { key: 'date', label: 'Requested', className: 'hidden xl:table-cell w-[8.5rem]', cell: (r) => <MutedCell>{fmtDate(r.requestedAt)}</MutedCell> },
]

const requestKey = (r) => `${r.kind}-${r.recordId}`

function AssetHistory() {
  const toast = useToast()
  const navigate = useNavigate()
  const { user } = useAuth()
  const isAdmin = user?.role === 'ADMIN'
  // Admin-Staff sees everyone's requests too, but only an admin approves / rejects them.
  const seesAll = seesAllAssets(user?.role)
  // Admin-Staff can't review requests, but can remind an administrator about a pending one.
  const canRemind = user?.role === 'ADMIN_STAFF'
  const [reminding, setReminding] = useState(false)

  // The dashboard links here with ?view=requests&status=PENDING_APPROVAL|REJECTED.
  const location = useLocation()
  const linked = new URLSearchParams(location.search)
  const [view, setView]           = useState(linked.get('view') === 'requests' ? 'requests' : 'history')   // 'history' | 'requests'
  const [history, setHistory]     = useState([])
  const [requests, setRequests]   = useState([])
  const [loading, setLoading]     = useState(true)
  const [users, setUsers]         = useState([])
  const [search, setSearch]       = useState('')
  const [filterType, setFilterType] = useState('')
  const [filterStatus, setFilterStatus] = useState(() => (REQUEST_STATUS[linked.get('status')] ? linked.get('status') : ''))
  // Requests a notification pointed to (keyed like the rows below: "KIND-recordId").
  const highlight = useHighlight()

  // A link opened while already on this page (e.g. from the bell) switches the view / status too.
  useEffect(() => {
    const params = new URLSearchParams(location.search)
    if (params.get('view') === 'requests') { setView('requests'); setViewing(null) }
    const status = params.get('status')
    if (REQUEST_STATUS[status]) setFilterStatus(status)
  }, [location.key]) // eslint-disable-line react-hooks/exhaustive-deps
  const [dateFilter, setDateFilter] = useState('')
  // Admin can narrow to one person ('' = everyone). Staff aren't filtered here - the backend
  // already limits them to their accountable assets' history and their own requests.
  const [performer, setPerformer] = useState('')
  const [moreFilters, setMoreFilters] = useState(false)
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
    if (seesAll) getUsers().then(({ data }) => setUsers(data)).catch(() => {})
  }, [seesAll])

  useEffect(() => {
    if (view === 'history') fetchHistory(debouncedSearch)
    else fetchRequests(performer || null)
  }, [view, debouncedSearch, performer, fetchHistory, fetchRequests])

  const refresh = (silent = false) => {
    if (view === 'history') fetchHistory(debouncedSearch, silent)
    else fetchRequests(performer || null, silent)
  }

  // Admin-Staff's "Notify admin": the request shows up in the administrators' notification bell.
  const handleRemind = async (r) => {
    setReminding(true)
    try {
      await remindAdmin(r.kind, r.recordId)
      toast.show(`Administrators were notified about the ${REQUEST_KIND[r.kind]?.label?.toLowerCase() ?? ''} request for ${r.propertyNumber}.`, 'success')
      const { data } = await getEditRequests(performer || null)
      setRequests(data)
      setViewing(data.find((x) => x.kind === r.kind && x.recordId === r.recordId) ?? r)
    } catch (err) {
      toast.show(err.response?.data?.message || 'Could not notify the administrators. Try again.', 'error')
    } finally {
      setReminding(false)
    }
  }

  // Admin approves / rejects a staff request from its details window.
  const handleApprove = async (r) => {
    try {
      await REQUEST_KIND[r.kind].approve(r.recordId)
      toast.show(`Request approved: ${r.propertyNumber} ${REQUEST_KIND[r.kind].done}.`, 'success')
      setViewing(null)
      fetchRequests(performer || null)
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to approve the request.', 'error')
    }
  }

  const handleReject = async (note) => {
    await REQUEST_KIND[rejecting.kind].reject(rejecting.recordId, note)
    toast.show('Request rejected.', 'success')
    setViewing(null)
    fetchRequests(performer || null)
  }

  // Keep the list current as assets / requests change anywhere (no loading flicker).
  useEventStream('asset', () => refresh(true))
  useEventStream('maintenance', () => refresh(true))
  useEventStream('disposal', () => refresh(true))

  useEffect(() => { setPage(1) }, [view, debouncedSearch, filterType, filterStatus, dateFilter, performer, highlight.ids])
  useEffect(() => { if (performer) setMoreFilters(true) }, [performer])

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
  const requestRows = useMemo(() => highlightedFirst(filteredRequests, highlight.ids, requestKey),
    [filteredRequests, highlight.ids])
  const highlightedCount = useMemo(() => requestRows.filter((r) => highlight.ids.has(requestKey(r))).length,
    [requestRows, highlight.ids])

  const isHistory = view === 'history'
  const rows   = isHistory ? filteredHistory : requestRows
  const total  = isHistory ? history.length : requests.length
  const paged  = rows.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)
  const activeFilters = [search.trim(), isHistory ? filterType : filterStatus, dateFilter, performer].filter(Boolean).length
  const clearFilters = () => { setSearch(''); setFilterType(''); setFilterStatus(''); setDateFilter(''); setPerformer('') }
  const requestsLabel = seesAll ? 'Staff requests' : 'My requests'

  const personOptions = users.map((u) => [String(u.id), `${u.fullName || u.username}${u.role === 'ADMIN' ? ' (Admin)' : u.role === 'ADMIN_STAFF' ? ' (Admin-Staff)' : ''}`])

  return (
    <MainLayout>
      <div className="flex flex-col gap-2.5 mb-4">
        <div className="flex flex-col sm:flex-row sm:items-center gap-2">
          <SearchBox value={search} onChange={setSearch} label={isHistory ? 'Search asset history' : 'Search requests'}
            placeholder={isHistory ? 'Search by asset, property no. or person' : 'Search by asset, person or details'} />
          {/* Two lists on one page: what happened to assets, and maintenance/disposal/transfer requests */}
          <div className="grid grid-cols-2 sm:inline-flex sm:self-auto rounded-lg border border-slate-300 dark:border-zinc-700 p-0.5 bg-white dark:bg-zinc-900" role="tablist">
            {[['history', 'History'], ['requests', requestsLabel]].map(([key, label]) => (
              <button key={key} role="tab" aria-selected={view === key} onClick={() => { setView(key); setViewing(null) }}
                className={`text-sm px-3.5 py-2 sm:py-1.5 rounded-md font-medium whitespace-nowrap transition-colors ${
                  view === key ? 'bg-slate-900 text-white dark:bg-white dark:text-zinc-900' : 'text-slate-700 dark:text-zinc-300 hover:bg-slate-100 dark:hover:bg-zinc-800'
                }`}>{label}</button>
            ))}
          </div>
        </div>
        <FilterBar activeCount={activeFilters} onClear={clearFilters} moreOpen={moreFilters} onMoreToggle={setMoreFilters}
          more={seesAll ? (
            <FilterSelect label={isHistory ? 'Done by' : 'Requested by'} value={performer} onChange={setPerformer} options={personOptions} anyLabel="Anyone" />
          ) : null}>
          {isHistory
            ? <FilterSelect label="Event" value={filterType} onChange={setFilterType} options={Object.entries(EVENT).map(([k, e]) => [k, e.label])} />
            : <FilterSelect label="Status" value={filterStatus} onChange={setFilterStatus} options={Object.entries(REQUEST_STATUS).map(([k, s]) => [k, s.label])} />}
          <FilterSelect label="When" value={dateFilter} onChange={setDateFilter} options={WHEN} anyLabel="Any time" />
        </FilterBar>
      </div>

      {!isHistory && highlight.active && !loading && (
        <HighlightNotice count={highlightedCount} noun="request" title={highlight.title} onClear={highlight.clear} />
      )}

      <ListCard title={isHistory ? 'Asset history' : requestsLabel} filtered={rows.length !== total}
        count={rows.length} total={total} noun={isHistory ? 'entry' : 'request'} loading={loading}
        actions={<RefreshButton onClick={() => refresh()} />}
        footer={!loading && <Pager page={page} pageSize={PAGE_SIZE} total={rows.length} onPage={setPage} />}>
        {loading ? <ListSkeleton /> : rows.length === 0 ? (
          <ListEmpty>{total === 0 ? (isHistory ? 'No history recorded yet.' : 'No requests yet.') : 'Nothing matches your search or filters.'}</ListEmpty>
        ) : isHistory ? (
          <DataTable columns={HISTORY_COLUMNS} rows={paged} rowKey={(h) => h.id} onOpen={setViewing} selectedKey={viewing?.id}
            caption="Asset history. Select an entry to see its details." />
        ) : (
          <DataTable columns={REQUEST_COLUMNS} rows={paged} rowKey={requestKey} onOpen={setViewing}
            selectedKey={viewing ? requestKey(viewing) : null} highlightKeys={highlight.ids}
            caption="Requests. Select a request to see its details." />
        )}
      </ListCard>

      {viewing && isHistory && (
        <DetailModal
          title={viewing.asset?.description || 'History entry'}
          onClose={() => setViewing(null)}
          subtitle={<>
            <span className="text-slate-600 dark:text-zinc-400">Property No.</span>
            <span className="font-mono font-semibold text-slate-900 dark:text-zinc-100">{viewing.asset?.propertyNumber || 'N/A'}</span>
            <span className="text-slate-300 dark:text-zinc-600" aria-hidden="true">·</span>
            <MappedBadge map={EVENT} value={viewing.eventType} />
          </>}
          footer={viewing.asset?.propertyNumber && (
            <ModalAction label="Open asset" onClick={() => navigate(`/assets?search=${encodeURIComponent(viewing.asset.propertyNumber)}`)} />
          )}
        >
          <DetailGrid>
            <DetailSection title="What happened">
              <DetailField label="Date" value={fmtDate(viewing.eventDate || viewing.createdAt)} />
              <DetailField label="Done by" value={personName(viewing.performedBy)} />
              <DetailField label="From office" value={viewing.fromOffice?.officeName} />
              <DetailField label="To office" value={viewing.toOffice?.officeName} />
            </DetailSection>
            <DetailSection title="Asset">
              <DetailField label="PAR Number" value={viewing.asset?.parNumber} mono />
            </DetailSection>
            <DetailSection title="Notes" wide>
              <DetailField label="Notes" value={viewing.notes} />
            </DetailSection>
          </DetailGrid>
        </DetailModal>
      )}

      {viewing && !isHistory && (
        <DetailModal
          title={viewing.assetDescription || 'Request'}
          escDisabled={!!rejecting}
          onClose={() => setViewing(null)}
          subtitle={<>
            <span className="text-slate-600 dark:text-zinc-400">Property No.</span>
            <span className="font-mono font-semibold text-slate-900 dark:text-zinc-100">{viewing.propertyNumber || 'N/A'}</span>
            <span className="text-slate-300 dark:text-zinc-600" aria-hidden="true">·</span>
            <MappedBadge map={REQUEST_KIND} value={viewing.kind} />
            <MappedBadge map={REQUEST_STATUS} value={viewing.approvalStatus} />
          </>}
          footer={<>
            {isAdmin && viewing.approvalStatus === 'PENDING_APPROVAL' && <>
              <ModalAction label="Approve request" icon={ICON.check} tone="primary" onClick={() => handleApprove(viewing)} />
              <ModalAction label="Reject" icon={ICON.x} tone="danger" onClick={() => setRejecting(viewing)} />
            </>}
            {viewing.propertyNumber && (
              <ModalAction label="Open asset" onClick={() => navigate(`/assets?search=${encodeURIComponent(viewing.propertyNumber)}`)} />
            )}
            {canRemind && viewing.approvalStatus === 'PENDING_APPROVAL' && (
              <ModalAction label={reminding ? 'Notifying…' : 'Notify admin'} icon={ICON.bell} disabled={reminding}
                onClick={() => handleRemind(viewing)} />
            )}
          </>}
        >
          <DetailGrid>
            <DetailSection title="Request">
              <DetailField label="Requested by" value={viewing.requestedByName} />
              <DetailField label="Requested" value={fmtDate(viewing.requestedAt)} />
              <DetailField label="PAR Number" value={viewing.parNumber} mono />
            </DetailSection>
            <DetailSection title="Review">
              <DetailField label="Status" value={REQUEST_STATUS[viewing.approvalStatus]?.label} />
              <DetailField label="Reviewed by" value={viewing.approvalStatus === 'PENDING_APPROVAL' ? 'Not yet reviewed' : viewing.reviewedByName} />
              <DetailField label="Reviewed" value={viewing.reviewedAt ? fmtDate(viewing.reviewedAt) : 'N/A'} />
              {viewing.reviewNote && <DetailField label="Reason given" value={viewing.reviewNote} />}
              {viewing.reminderCount > 0 && (
                <DetailField label="Admin reminded" value={`${viewing.reminderCount === 1 ? 'Once' : `${viewing.reminderCount} times`}, last ${fmtDate(viewing.lastRemindedAt)} by ${viewing.lastRemindedByName || 'Admin-Staff'}`} />
              )}
            </DetailSection>
            <DetailSection title="Details" wide>
              <DetailField label="Details" value={viewing.detail} />
            </DetailSection>
          </DetailGrid>
        </DetailModal>
      )}

      {rejecting && (
        <RejectRequestModal
          record={{ ...rejecting, kind: rejecting.kind.toLowerCase(), id: rejecting.recordId }}
          describe={() => `${rejecting.propertyNumber}: ${rejecting.assetDescription}`}
          onClose={() => setRejecting(null)}
          onConfirm={handleReject}
        />
      )}
    </MainLayout>
  )
}

export default AssetHistory
