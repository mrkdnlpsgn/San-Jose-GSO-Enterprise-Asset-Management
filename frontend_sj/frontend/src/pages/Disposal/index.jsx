import { useState, useEffect, useCallback, useMemo } from 'react'
import { useLocation } from 'react-router-dom'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import { useEventStream } from '../../hooks/useEventStream'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import AddDisposalModal from './AddDisposalModal'
import { getDisposal, createDisposal, updateDisposal, deleteDisposal } from '../../services/disposalService'
import { getAssets } from '../../services/assetService'
import { getUsers } from '../../services/userService'

const STATUS_BADGE = {
  PENDING:   'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  APPROVED:  'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  COMPLETED: 'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
}
const METHOD_BADGE = {
  SALE:        'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  TRANSFER:    'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
  DESTRUCTION: 'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
  OTHERS:      'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
}

function fmt(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}

function fmtMoney(n) {
  if (n == null) return '—'
  return `₱${Number(n).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

const PAGE_SIZE = 8

function Disposal() {
  const toast    = useToast()
  const location = useLocation()

  const [records, setRecords]   = useState([])
  const [loading, setLoading]   = useState(true)
  const [assets, setAssets]     = useState([])
  const [users, setUsers]       = useState([])
  const [search, setSearch]     = useState('')
  const [filterStatus, setFilterStatus]   = useState('')
  const [filterMethod, setFilterMethod]   = useState('')
  const [assetFilter, setAssetFilter]     = useState('')
  const [showAdd, setShowAdd]   = useState(false)
  const [editing, setEditing]   = useState(null)
  const [deleting, setDeleting] = useState(null)
  const [page, setPage]         = useState(1)

  useEffect(() => {
    const params = new URLSearchParams(location.search)
    const assetId = params.get('assetId')
    if (assetId) setAssetFilter(assetId)
  }, [location.search])

  const debouncedSearch = useDebounce(search, 300)

  const fetchRecords = useCallback(async (q = '', { silent = false } = {}) => {
    if (!silent) setLoading(true)
    try {
      const { data } = await getDisposal(q)
      setRecords(data)
    } catch {
      if (!silent) toast.show('Failed to load disposal records.', 'error')
    } finally {
      if (!silent) setLoading(false)
    }
  }, [toast])

  const load = useCallback(() => {
    Promise.all([getAssets().catch(() => ({ data: [] })), getUsers().catch(() => ({ data: [] }))])
      .then(([assetRes, userRes]) => { setAssets(assetRes.data); setUsers(userRes.data) })
    fetchRecords(search)
  }, [fetchRecords, search]) // eslint-disable-line

  useEffect(() => {
    Promise.all([getAssets().catch(() => ({ data: [] })), getUsers().catch(() => ({ data: [] }))])
      .then(([assetRes, userRes]) => { setAssets(assetRes.data); setUsers(userRes.data) })
  }, [])

  useEffect(() => { fetchRecords(debouncedSearch) }, [debouncedSearch, fetchRecords])
  useEffect(() => { setPage(1) }, [debouncedSearch, filterStatus, filterMethod, assetFilter])

  useEventStream('disposal', ({ action, id, data }) => {
    if (action === 'DELETED') { setRecords((prev) => prev.filter((r) => r.id !== id)); return }
    if (!data) { fetchRecords(search); return }
    setRecords((prev) => {
      const exists = prev.some((r) => r.id === data.id)
      return exists ? prev.map((r) => (r.id === data.id ? data : r)) : [data, ...prev]
    })
  })

  const handleCreate = async (payload, idempotencyKey) => {
    const { data } = await createDisposal(payload, idempotencyKey)
    setRecords((prev) => [data, ...prev])
    toast.show('Disposal record added.', 'success')
  }

  const handleUpdate = async (payload) => {
    const { data } = await updateDisposal(editing.id, payload)
    setRecords((prev) => prev.map((r) => (r.id === data.id ? data : r)))
    setEditing(null)
    toast.show('Record updated.', 'success')
  }

  const handleDelete = async () => {
    try {
      await deleteDisposal(deleting.id)
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
      if (filterStatus && r.disposalStatus !== filterStatus) return false
      if (filterMethod && r.recommendedMethod !== filterMethod) return false
      if (assetFilter && String(r.asset?.id) !== assetFilter) return false
      return true
    })
  }, [records, filterStatus, filterMethod, assetFilter])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  return (
    <MainLayout>
      {assetFilter && (
        <div className="mb-4 flex items-center gap-3 px-4 py-3 rounded-lg bg-red-500/10 border border-red-500/20">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-red-400 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M3 3a1 1 0 011-1h12a1 1 0 011 1v3a1 1 0 01-.293.707L12 11.414V15a1 1 0 01-.293.707l-2 2A1 1 0 018 17v-5.586L3.293 6.707A1 1 0 013 6V3z" clipRule="evenodd" />
          </svg>
          <p className="text-sm text-red-400">Filtered to a specific asset.</p>
          <button onClick={() => setAssetFilter('')} className="ml-auto text-xs text-red-400 hover:text-red-300 font-medium">Clear filter</button>
        </div>
      )}

      <div className="flex flex-col gap-3 mb-5">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
          <div className="relative w-full sm:max-w-xs">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
            </svg>
            <input type="text" placeholder="Search asset, reason…" value={search} onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
          </div>
          <Button size="md" className="self-start sm:self-auto" onClick={() => setShowAdd(true)}>
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
            </svg>
            Add Disposal
          </Button>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {[['', 'All Status'], ['PENDING', 'Pending'], ['APPROVED', 'Approved'], ['COMPLETED', 'Completed']].map(([val, label]) => (
            <button key={val} onClick={() => setFilterStatus(val)}
              className={`text-xs px-2.5 py-1.5 rounded-lg border font-medium transition-all ${
                filterStatus === val
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-zinc-900 border-slate-900 dark:border-white'
                  : 'border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800'
              }`}>{label}</button>
          ))}
          <div className="relative">
            <select value={filterMethod} onChange={(e) => setFilterMethod(e.target.value)}
              className="appearance-none text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 px-3 py-1.5 pr-8 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all">
              <option value="">All Methods</option>
              <option value="SALE">Sale</option>
              <option value="TRANSFER">Transfer</option>
              <option value="DESTRUCTION">Destruction</option>
              <option value="OTHERS">Others</option>
            </select>
            <div className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 dark:text-zinc-500">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
            </div>
          </div>
        </div>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Disposal Records</p>
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
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            <p className="text-sm text-zinc-500">{records.length === 0 ? 'No disposal records yet.' : 'No records match your filters.'}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Asset', 'Reason', 'Carrying Amount', 'Method', 'Status', 'Inspection Date', 'Approved By', 'Recorded By', ''].map((h) => (
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
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs max-w-[160px]">
                      <span className="block truncate" title={r.reason}>{r.reason}</span>
                    </td>
                    <td className="px-5 py-3.5 text-xs whitespace-nowrap" title="Informational only — depreciation never gates disposal; condition does.">
                      <p className="font-medium text-slate-700 dark:text-zinc-300">{fmtMoney(r.carryingAmount)}</p>
                      <p className="text-slate-400 dark:text-zinc-500">−{fmtMoney(r.accumulatedDepreciation)} dep.</p>
                    </td>
                    <td className="px-5 py-3.5 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${METHOD_BADGE[r.recommendedMethod] || ''}`}>{r.recommendedMethod}</span>
                    </td>
                    <td className="px-5 py-3.5 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${STATUS_BADGE[r.disposalStatus] || ''}`}>{r.disposalStatus}</span>
                    </td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{fmt(r.inspectionDate)}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{r.approvedBy?.fullName || r.approvedBy?.username || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{r.recordedBy?.fullName || r.recordedBy?.username || '—'}</td>
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

      {showAdd  && <AddDisposalModal onClose={() => setShowAdd(false)} onSave={handleCreate} assets={assets} users={users} />}
      {editing  && <AddDisposalModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} assets={assets} users={users} />}
      {deleting && (
        <ConfirmDialog
          title="Delete this disposal record?"
          message="This record will be permanently removed."
          confirmLabel="Delete"
          onConfirm={handleDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
    </MainLayout>
  )
}

export default Disposal
