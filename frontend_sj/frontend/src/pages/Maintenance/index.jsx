import { Fragment, useState, useEffect, useCallback, useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useSelector } from 'react-redux'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import { useEventStream } from '../../hooks/useEventStream'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import { ApprovalBadge, ApprovalActions, RejectRequestModal, isApproved } from '../../components/common/ApprovalControls'
import GroupDevicesTable, { groupEntries, recordMatches } from '../Assets/GroupDevicesTable'
import { AssetGroupDrawerById } from '../Assets/AssetGroupDrawer'
import DeviceRow from '../Assets/DeviceRow'
import AddMaintenanceModal from './AddMaintenanceModal'
import EvidenceModal from './EvidenceModal'
import { getMaintenance, createMaintenance, updateMaintenance, deleteMaintenance, approveMaintenance, rejectMaintenance } from '../../services/maintenanceService'
import { getAssets } from '../../services/assetService'
import { getUsers } from '../../services/userService'

const STATUS_BADGE = {
  COMPLETED: 'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  ONGOING:   'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  SCHEDULED: 'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
}

const TYPE_BADGE = {
  PREVENTIVE: 'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  CORRECTIVE: 'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
  REPAIR:     'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
}

function formatDate(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}

const PAGE_SIZE = 8
const HEADERS = ['Asset', 'Type', 'Findings', 'Status', 'Date', 'Assigned To', 'Cost', 'Evidence', '']

function Maintenance() {
  const toast    = useToast()
  const location = useLocation()

  const [records, setRecords]   = useState([])
  const [loading, setLoading]   = useState(true)
  const [assets, setAssets]     = useState([])
  const [users, setUsers]       = useState([])
  const [search, setSearch]     = useState('')
  const [filterStatus, setFilterStatus]   = useState('')
  const [filterType, setFilterType]       = useState('')
  const [assetFilter, setAssetFilter]     = useState('')
  const [showAdd, setShowAdd]   = useState(false)
  const [editing, setEditing]   = useState(null)
  const [deleting, setDeleting] = useState(null)
  const [rejecting, setRejecting] = useState(null)
  // ?pending=1 (e.g. from the dashboard's Pending Approvals) opens with only requests awaiting approval
  const [pendingOnly, setPendingOnly] = useState(() => new URLSearchParams(window.location.search).get('pending') === '1')
  const isAdmin = useSelector((s) => s.auth.user?.role === 'ADMIN')
  const [viewingEvidence, setViewingEvidence] = useState(null)
  const [page, setPage]         = useState(1)

  // Records whose devices belong to the same group (same model — added together or auto-grouped)
  // show as one expandable row; every record inside is still a complete record.
  const navigate = useNavigate()
  const [expanded, setExpanded] = useState(() => new Set())
  const [groupId, setGroupId]   = useState(null)   // group whose drawer is open
  const [groupExiting, setGroupExiting] = useState(false)
  const toggleExpanded = (key) => setExpanded((prev) => {
    const next = new Set(prev)
    if (next.has(key)) next.delete(key); else next.add(key)
    return next
  })
  const closeGroup = useCallback(() => {
    setGroupExiting(true)
    setTimeout(() => { setGroupId(null); setGroupExiting(false) }, 220)
  }, [])

  const debouncedSearch = useDebounce(search, 300)

  // Pre-filter by assetId URL param
  useEffect(() => {
    const params = new URLSearchParams(location.search)
    const assetId = params.get('assetId')
    if (assetId) setAssetFilter(assetId)
  }, [location.search])

  const fetchRecords = useCallback(async (q = '', { silent = false } = {}) => {
    if (!silent) setLoading(true)
    try {
      const { data } = await getMaintenance(q)
      setRecords(data)
    } catch {
      if (!silent) toast.show('Failed to load maintenance records.', 'error')
    } finally {
      if (!silent) setLoading(false)
    }
  }, [toast])

  const load = useCallback(async () => {
    Promise.all([getAssets().catch(() => ({ data: [] })), getUsers().catch(() => ({ data: [] }))])
      .then(([assetRes, userRes]) => { setAssets(assetRes.data); setUsers(userRes.data) })
    fetchRecords(search)
  }, [fetchRecords, search]) // eslint-disable-line

  useEffect(() => {
    Promise.all([getAssets().catch(() => ({ data: [] })), getUsers().catch(() => ({ data: [] }))])
      .then(([assetRes, userRes]) => { setAssets(assetRes.data); setUsers(userRes.data) })
  }, [])

  useEffect(() => { fetchRecords(debouncedSearch) }, [debouncedSearch, fetchRecords])
  useEffect(() => { setPage(1) }, [debouncedSearch, filterStatus, filterType, assetFilter])

  useEventStream('maintenance', ({ action, id, data }) => {
    if (action === 'DELETED') { setRecords((prev) => prev.filter((r) => r.id !== id)); return }
    if (!data) { fetchRecords(search); return }
    setRecords((prev) => {
      const exists = prev.some((r) => r.id === data.id)
      return exists ? prev.map((r) => (r.id === data.id ? data : r)) : [data, ...prev]
    })
  })

  const handleCreate = async (payload, idempotencyKey) => {
    const { data } = await createMaintenance(payload, idempotencyKey)
    // The SSE 'maintenance' CREATED event (emitted server-side before this
    // response returns) can already have added this record via the listener
    // above — check first so a fast round-trip doesn't insert it twice.
    setRecords((prev) => (prev.some((r) => r.id === data.id) ? prev.map((r) => (r.id === data.id ? data : r)) : [data, ...prev]))
    toast.show(isApproved(data) ? 'Maintenance record added.' : 'Request sent — an administrator needs to approve it before you can edit it.', 'success')
  }

  const handleUpdate = async (payload) => {
    const { data } = await updateMaintenance(editing.id, payload)
    setRecords((prev) => prev.map((r) => (r.id === data.id ? data : r)))
    setEditing(null)
    toast.show('Record updated.', 'success')
  }

  const handleDelete = async () => {
    try {
      await deleteMaintenance(deleting.id)
      setRecords((prev) => prev.filter((r) => r.id !== deleting.id))
      toast.show('Record deleted.', 'warning')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to delete.', 'error')
    } finally {
      setDeleting(null)
    }
  }

  const upsert = (data) => setRecords((prev) => prev.map((r) => (r.id === data.id ? data : r)))

  const handleApprove = async (rec) => {
    try {
      const { data } = await approveMaintenance(rec.id)
      upsert(data)
      toast.show('Request approved.', 'success')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to approve the request.', 'error')
    }
  }

  const handleReject = async (note) => {
    const { data } = await rejectMaintenance(rejecting.id, note)
    upsert(data)
    toast.show('Request rejected.', 'warning')
  }

  const pendingCount = records.filter((r) => r.approvalStatus === 'PENDING_APPROVAL').length

  const filtered = useMemo(() => {
    return records.filter((r) => {
      if (pendingOnly && r.approvalStatus !== 'PENDING_APPROVAL') return false
      if (filterStatus && r.status !== filterStatus) return false
      if (filterType && r.maintenanceType !== filterType) return false
      if (assetFilter && String(r.asset?.id) !== assetFilter) return false
      return true
    })
  }, [records, pendingOnly, filterStatus, filterType, assetFilter])

  // group records by their device's group; a lone record stays a plain row
  const entries = useMemo(() => groupEntries(filtered, (r) => r.asset?.groupId), [filtered])
  const totalPages = Math.max(1, Math.ceil(entries.length / PAGE_SIZE))
  const paged = entries.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const chevronButton = (key, open, title) => (
    <button
      type="button"
      onClick={(e) => { e.stopPropagation(); toggleExpanded(key) }}
      title={title}
      aria-expanded={open}
      className="p-0.5 rounded text-slate-400 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all"
    >
      <svg xmlns="http://www.w3.org/2000/svg" className={`h-4 w-4 transition-transform duration-150 ${open ? 'rotate-90' : ''}`} viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />
      </svg>
    </button>
  )

  const infoButton = (g) => (
    <div className="flex items-center justify-end">
      <button onClick={(e) => { e.stopPropagation(); setGroupId(g.groupId) }} title="Group details & lifecycle"
        className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" /></svg>
      </button>
    </div>
  )

  const assetCell = (g, open) => {
    const recs = g.members
    const devices = new Set(recs.map((r) => r.asset?.id)).size
    return (
      <td className="px-5 py-3.5">
        <div className="flex items-center gap-2">
          {chevronButton(g.key, open, open ? 'Hide records' : `Show all ${recs.length} records`)}
          <div className="min-w-0">
            <span className="px-1.5 py-0.5 rounded-full text-2xs font-semibold bg-brand-500/10 text-brand-400 ring-1 ring-brand-500/20">{recs.length} records</span>
            <p className="text-sm font-medium text-slate-900 dark:text-white truncate max-w-[160px] mt-0.5">{recs[0].asset?.description}</p>
            <p className="text-2xs text-slate-400 dark:text-zinc-500">{devices} device{devices !== 1 ? 's' : ''} · same model</p>
          </div>
        </div>
      </td>
    )
  }

  const commonOrVarious = (list, pick, render) => {
    const vals = [...new Set(list.map(pick))]
    return vals.length === 1 ? render(vals[0]) : <span className="text-slate-400 dark:text-zinc-500">Various</span>
  }

  const renderRecordRow = (r, { child = false } = {}) => (
                  <tr key={r.id} className={`hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100 ${child ? 'bg-slate-50/50 dark:bg-zinc-900/30' : ''}`}>
                    <td className="px-5 py-3.5">
                      <p className="font-mono text-xs text-slate-500 dark:text-zinc-400">{r.asset?.propertyNumber}</p>
                      {r.asset?.parNumber && <p className="font-mono text-2xs text-slate-400 dark:text-zinc-500">PAR: {r.asset.parNumber}</p>}
                      <p className="text-sm font-medium text-slate-900 dark:text-white truncate max-w-[160px]">{r.asset?.description}</p>
                    </td>
                    <td className="px-5 py-3.5 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${TYPE_BADGE[r.maintenanceType] || ''}`}>{r.maintenanceType}</span>
                    </td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs max-w-[160px]">
                      <span className="block truncate" title={r.findings}>{r.findings}</span>
                    </td>
                    <td className="px-5 py-3.5 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${STATUS_BADGE[r.status] || ''}`}>{r.status}</span>
                      <ApprovalBadge record={r} />
                    </td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{formatDate(r.maintenanceDate)}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{r.assignedTo?.fullName || r.assignedTo?.username || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">
                      {r.cost != null ? `₱${Number(r.cost).toLocaleString('en-PH', { minimumFractionDigits: 2 })}` : '—'}
                    </td>
                    <td className="px-5 py-3.5 whitespace-nowrap">
                      <button onClick={() => setViewingEvidence(r)} title="View evidence photos"
                        className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md text-xs font-medium text-slate-500 dark:text-zinc-400 hover:text-brand-500 dark:hover:text-brand-400 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                          <path fillRule="evenodd" d="M2 6a2 2 0 012-2h1.586a1 1 0 00.707-.293l1.121-1.121A2 2 0 018.828 2h2.344a2 2 0 011.414.586l1.121 1.121A1 1 0 0014.414 4H16a2 2 0 012 2v8a2 2 0 01-2 2H4a2 2 0 01-2-2V6zm8 2a3 3 0 100 6 3 3 0 000-6z" clipRule="evenodd" />
                        </svg>
                        Evidence
                      </button>
                    </td>
                    <td className="px-5 py-3.5">
                      <div className="flex items-center justify-end gap-1">
                        {isAdmin && <ApprovalActions record={r} onApprove={handleApprove} onReject={setRejecting} />}
                        {(isAdmin || isApproved(r)) && (
                        <button onClick={() => setEditing(r)} title="Edit"
                          className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" /></svg>
                        </button>
                        )}
                        {isAdmin && (
                        <button onClick={() => setDeleting(r)} title="Delete"
                          className="p-1.5 rounded-md text-zinc-500 hover:text-red-400 hover:bg-red-950/40 transition-all duration-150">
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" /></svg>
                        </button>
                        )}
                      </div>
                    </td>
                  </tr>
  )

  const renderGroupHeader = (g, open) => {
    const recs = g.members
    return (
      <tr key={g.key} onClick={() => toggleExpanded(g.key)}
        className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100 cursor-pointer">
        {assetCell(g, open)}
        <td className="px-5 py-3.5 whitespace-nowrap">
          {commonOrVarious(recs, (r) => r.maintenanceType, (v) => (
            <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${TYPE_BADGE[v] || ''}`}>{v}</span>
          ))}
        </td>
        <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs">{recs.length} records across {new Set(recs.map((r) => r.asset?.id)).size} devices</td>
        <td className="px-5 py-3.5">
          <div className="flex flex-wrap gap-1">
            {Object.entries(recs.reduce((acc, r) => { acc[r.status] = (acc[r.status] || 0) + 1; return acc }, {})).map(([st, n]) => (
              <span key={st} className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${STATUS_BADGE[st] || ''}`}>{n} {st}</span>
            ))}
          </div>
        </td>
        <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">
          {formatDate(recs.reduce((m, r) => (r.maintenanceDate && (!m || r.maintenanceDate > m) ? r.maintenanceDate : m), null))}
          <span className="block text-2xs text-slate-400 dark:text-zinc-600">latest</span>
        </td>
        <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">
          {commonOrVarious(recs, (r) => r.assignedTo?.fullName || r.assignedTo?.username || '—', (v) => v)}
        </td>
        <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">
          {`₱${recs.reduce((n, r) => n + Number(r.cost || 0), 0).toLocaleString('en-PH', { minimumFractionDigits: 2 })}`}
          <span className="block text-2xs text-slate-400 dark:text-zinc-600">total</span>
        </td>
        <td className="px-5 py-3.5" />
        <td className="px-5 py-3.5">{infoButton(g)}</td>
      </tr>
    )
  }

  const renderGroupPanel = (g) => (
    <tr key={`${g.key}:panel`} className="bg-slate-50/60 dark:bg-zinc-900/40">
      <td colSpan={HEADERS.length} className="px-5 py-4">
        <GroupDevicesTable
          members={g.members}
          headers={HEADERS}
          matches={recordMatches}
          noun="records"
          placeholder="Search property no., PAR no., serial no. or person…"
          renderRow={(r) => renderRecordRow(r, { child: true })}
        />
      </td>
    </tr>
  )

  return (
    <MainLayout>
      {assetFilter && (
        <div className="mb-4 flex items-center gap-3 px-4 py-3 rounded-lg bg-blue-500/10 border border-blue-500/20">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-blue-400 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M3 3a1 1 0 011-1h12a1 1 0 011 1v3a1 1 0 01-.293.707L12 11.414V15a1 1 0 01-.293.707l-2 2A1 1 0 018 17v-5.586L3.293 6.707A1 1 0 013 6V3z" clipRule="evenodd" />
          </svg>
          <p className="text-sm text-blue-400">Filtered to a specific asset.</p>
          <button onClick={() => setAssetFilter('')} className="ml-auto text-xs text-blue-400 hover:text-blue-300 font-medium">Clear filter</button>
        </div>
      )}

      <div className="flex flex-col gap-3 mb-5">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
          <div className="relative w-full sm:max-w-xs">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
            </svg>
            <input type="text" placeholder="Search asset, findings…" value={search} onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
          </div>
          <Button size="md" className="self-start sm:self-auto" onClick={() => setShowAdd(true)}>
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
            </svg>
            {isAdmin ? 'Add Maintenance' : 'Request Maintenance'}
          </Button>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {(isAdmin || pendingCount > 0) && (
            <button onClick={() => setPendingOnly((v) => !v)}
              className={`text-xs px-2.5 py-1.5 rounded-lg border font-medium transition-all ${
                pendingOnly
                  ? 'bg-amber-500 text-white border-amber-500'
                  : 'border-amber-500/40 text-amber-600 dark:text-amber-400 hover:bg-amber-500/10'
              }`}>Awaiting approval{pendingCount > 0 ? ` (${pendingCount})` : ''}</button>
          )}
          {[['', 'All Status'], ['COMPLETED', 'Completed'], ['ONGOING', 'Ongoing'], ['SCHEDULED', 'Scheduled']].map(([val, label]) => (
            <button key={val} onClick={() => setFilterStatus(val)}
              className={`text-xs px-2.5 py-1.5 rounded-lg border font-medium transition-all ${
                filterStatus === val
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-zinc-900 border-slate-900 dark:border-white'
                  : 'border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800'
              }`}>{label}</button>
          ))}
          <div className="relative">
            <select value={filterType} onChange={(e) => setFilterType(e.target.value)}
              className="appearance-none text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 px-3 py-1.5 pr-8 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all">
              <option value="">All Types</option>
              <option value="PREVENTIVE">Preventive</option>
              <option value="CORRECTIVE">Corrective</option>
              <option value="REPAIR">Repair</option>
            </select>
            <div className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 dark:text-zinc-500">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
            </div>
          </div>
        </div>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Maintenance Records</p>
          {!loading && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {filtered.length}{filtered.length !== records.length ? ` of ${records.length}` : ''} record{filtered.length !== 1 ? 's' : ''}
            </span>
          )}
        </div>

        {loading ? (
          <div className="divide-y divide-slate-100 dark:divide-zinc-800">
            {Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="flex items-center gap-4 px-5 py-3.5">
                <div className="animate-pulse h-3 w-32 rounded bg-slate-200 dark:bg-zinc-800" />
                <div className="animate-pulse h-5 w-20 rounded-full bg-slate-200 dark:bg-zinc-800" />
                <div className="animate-pulse h-3 w-40 rounded bg-slate-200 dark:bg-zinc-800 ml-auto" />
              </div>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-2 text-zinc-600">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            <p className="text-sm text-zinc-500">{records.length === 0 ? 'No maintenance records yet.' : 'No records match your filters.'}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {HEADERS.map((h, i) => (
                    <th key={`${h}${i}`} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((entry) => {
                  if (entry.type === 'group') {
                    const open = expanded.has(entry.key)
                    return (
                      <Fragment key={entry.key}>
                        {renderGroupHeader(entry, open)}
                        {open && renderGroupPanel(entry)}
                      </Fragment>
                    )
                  }
                  return renderRecordRow(entry.item)
                })}
              </tbody>
            </table>
          </div>
        )}

        {!loading && entries.length > PAGE_SIZE && (
          <div className="px-5 py-3 border-t border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
            <p className="text-xs text-slate-400 dark:text-zinc-500">
              {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, entries.length)} of {entries.length}
            </p>
            <div className="flex items-center gap-1">
              <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}
                className="px-2.5 py-1.5 text-xs rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">Prev</button>
              <span className="text-xs text-slate-400 px-2">{page} / {totalPages}</span>
              <button onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                className="px-2.5 py-1.5 text-xs rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">Next</button>
            </div>
          </div>
        )}
      </div>

      {groupId && (
        <AssetGroupDrawerById
          groupId={groupId}
          exiting={groupExiting}
          onClose={closeGroup}
          renderDeviceRow={(m) => (
            <DeviceRow key={m.id} asset={m} onOpen={(a) => navigate(`/assets?search=${encodeURIComponent(a.propertyNumber)}`)} />
          )}
        />
      )}

      {showAdd  && <AddMaintenanceModal onClose={() => setShowAdd(false)} onSave={handleCreate} assets={assets} users={users} requestMode={!isAdmin} />}
      {editing  && <AddMaintenanceModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} assets={assets} users={users} />}
      {viewingEvidence && (
        <EvidenceModal record={viewingEvidence} onClose={() => setViewingEvidence(null)} />
      )}
      {rejecting && (
        <RejectRequestModal
          record={rejecting}
          describe={(r) => `${r.asset?.propertyNumber || ''} — ${r.asset?.description || ''}`}
          onClose={() => setRejecting(null)}
          onConfirm={handleReject}
        />
      )}
      {deleting && (
        <ConfirmDialog
          title="Delete this maintenance record?"
          message="This record will be permanently removed."
          confirmLabel="Delete"
          onConfirm={handleDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
    </MainLayout>
  )
}

export default Maintenance
