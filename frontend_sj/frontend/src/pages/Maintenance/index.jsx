import { useState, useEffect, useCallback, useMemo } from 'react'
import { useLocation } from 'react-router-dom'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import { useEventStream } from '../../hooks/useEventStream'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import AddMaintenanceModal from './AddMaintenanceModal'
import EvidenceModal from './EvidenceModal'
import { getMaintenance, createMaintenance, updateMaintenance, deleteMaintenance } from '../../services/maintenanceService'
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
  const [viewingEvidence, setViewingEvidence] = useState(null)
  const [page, setPage]         = useState(1)

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
    setRecords((prev) => [data, ...prev])
    toast.show('Maintenance record added.', 'success')
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

  const filtered = useMemo(() => {
    return records.filter((r) => {
      if (filterStatus && r.status !== filterStatus) return false
      if (filterType && r.maintenanceType !== filterType) return false
      if (assetFilter && String(r.asset?.id) !== assetFilter) return false
      return true
    })
  }, [records, filterStatus, filterType, assetFilter])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

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
            Add Maintenance
          </Button>
        </div>
        <div className="flex flex-wrap items-center gap-2">
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
                  {['Asset', 'Type', 'Findings', 'Status', 'Date', 'Assigned To', 'Cost', 'Evidence', ''].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((r) => (
                  <tr key={r.id} className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                    <td className="px-5 py-3.5">
                      <p className="font-mono text-xs text-slate-500 dark:text-zinc-400">{r.asset?.propertyNumber}</p>
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
                        <button onClick={() => setEditing(r)} title="Edit"
                          className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" /></svg>
                        </button>
                        <button onClick={() => setDeleting(r)} title="Delete"
                          className="p-1.5 rounded-md text-zinc-500 hover:text-red-400 hover:bg-red-950/40 transition-all duration-150">
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" /></svg>
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {!loading && filtered.length > PAGE_SIZE && (
          <div className="px-5 py-3 border-t border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
            <p className="text-xs text-slate-400 dark:text-zinc-500">
              {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filtered.length)} of {filtered.length}
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

      {showAdd  && <AddMaintenanceModal onClose={() => setShowAdd(false)} onSave={handleCreate} assets={assets} users={users} />}
      {editing  && <AddMaintenanceModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} assets={assets} users={users} />}
      {viewingEvidence && (
        <EvidenceModal record={viewingEvidence} onClose={() => setViewingEvidence(null)} />
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
