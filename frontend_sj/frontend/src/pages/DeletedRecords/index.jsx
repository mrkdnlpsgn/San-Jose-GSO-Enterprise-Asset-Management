import { useState, useEffect, useMemo } from 'react'
import MainLayout from '../../components/layout/MainLayout'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import { useToast } from '../../context/ToastContext'
import {
  getDeletedAssets, getDeletedMaintenance, getDeletedDisposal,
  restoreDeletedAsset, restoreDeletedMaintenance, restoreDeletedDisposal,
} from '../../services/deletedRecordsService'
import { useDebounce } from '../../hooks/useDebounce'
import { usePolling } from '../../hooks/usePolling'

const MAINTENANCE_TYPE_BADGE = {
  PREVENTIVE: 'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  CORRECTIVE: 'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
  REPAIR:     'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
}
const MAINTENANCE_STATUS_BADGE = {
  COMPLETED: 'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  ONGOING:   'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  SCHEDULED: 'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
}
const DISPOSAL_METHOD_BADGE = {
  AUCTION:  'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  DONATION: 'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  TRANSFER: 'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
}
const PAGE_SIZE = 8

const DISPOSAL_STATUS_BADGE = {
  PENDING:   'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  APPROVED:  'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  COMPLETED: 'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
}

function fmtDateTime(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleString('en-PH', {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}

function Badge({ className, children }) {
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${className || 'bg-slate-500/10 text-slate-400 ring-1 ring-slate-500/20'}`}>
      {children}
    </span>
  )
}

// One shared shape for all three tabs: fetch on mount, filter by a search
// predicate, render into the standard overflow-x-auto table used everywhere
// else in the app (see pages/Offices/index.jsx), plus a Restore button as
// the last column — this is otherwise read-only (no edit, no re-delete).
function DeletedTab({ fetcher, restoreFn, columns, matches, emptyMessage, recordLabel }) {
  const toast = useToast()
  const [rows, setRows]       = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch]   = useState('')
  const [restoring, setRestoring] = useState(null) // row pending confirmation
  const [busyId, setBusyId]       = useState(null) // row currently being restored
  const [page, setPage]           = useState(1)
  const debouncedSearch       = useDebounce(search)

  useEffect(() => {
    let alive = true
    setLoading(true)
    fetcher()
      .then(({ data }) => { if (alive) setRows(data) })
      .catch(() => { if (alive) setRows([]) })
      .finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [fetcher])

  // Background poll — never touches `loading`, so a silent refresh can't
  // flash the skeleton back in over rows already on screen.
  usePolling(() => {
    fetcher().then(({ data }) => setRows(data)).catch(() => {})
  }, 30000)

  const filtered = useMemo(() => {
    const q = debouncedSearch.trim().toLowerCase()
    if (!q) return rows
    return rows.filter((r) => matches(r, q))
  }, [rows, debouncedSearch, matches])

  useEffect(() => { setPage(1) }, [debouncedSearch])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const handleRestore = async () => {
    const row = restoring
    setRestoring(null)
    setBusyId(row.id)
    try {
      await restoreFn(row.id)
      setRows((prev) => prev.filter((r) => r.id !== row.id))
      toast.show(`${recordLabel} restored.`, 'success')
    } catch (err) {
      toast.show(err.response?.data?.message || `Failed to restore ${recordLabel.toLowerCase()}.`, 'error')
    } finally {
      setBusyId(null)
    }
  }

  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex flex-col sm:flex-row sm:items-center gap-3">
        <div className="flex items-center gap-3 flex-1">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300 whitespace-nowrap">Recycle Bin</p>
          {!loading && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {filtered.length} record{filtered.length !== 1 ? 's' : ''}
            </span>
          )}
        </div>
        <div className="relative w-full sm:max-w-xs">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
          </svg>
          <input
            type="text"
            placeholder="Search…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all"
          />
        </div>
      </div>

      {loading ? (
        <div className="divide-y divide-slate-100 dark:divide-zinc-800">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="flex items-center gap-3 px-5 py-3.5">
              <div className="animate-pulse h-3 w-48 rounded bg-slate-200 dark:bg-zinc-800" />
              <div className="animate-pulse h-3 w-32 rounded bg-slate-200 dark:bg-zinc-800 ml-auto" />
            </div>
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-zinc-600">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
          <p className="text-sm text-zinc-400 font-medium">{rows.length === 0 ? emptyMessage : 'No records match your search'}</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
            <thead>
              <tr>
                {columns.map((col) => (
                  <th key={col.key} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">
                    {col.label}
                  </th>
                ))}
                <th className="px-5 py-3 text-right text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">
                  Restore
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
              {paged.map((row) => (
                <tr key={row.id} className="hover:bg-slate-50/60 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                  {columns.map((col) => (
                    <td key={col.key} className="px-5 py-3.5 text-slate-600 dark:text-zinc-300 whitespace-nowrap">
                      {col.render ? col.render(row) : (row[col.key] ?? '—')}
                    </td>
                  ))}
                  <td className="px-5 py-3.5 whitespace-nowrap text-right">
                    <button
                      onClick={() => setRestoring(row)}
                      disabled={busyId === row.id}
                      title={`Restore this ${recordLabel.toLowerCase()}`}
                      className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md text-xs font-medium text-brand-600 dark:text-brand-400 hover:bg-brand-50 dark:hover:bg-brand-500/10 transition-all duration-150 disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                        <path fillRule="evenodd" d="M15.312 11.424a5.5 5.5 0 01-9.201 2.466l-.312-.311h2.433a.75.75 0 000-1.5H3.989a.75.75 0 00-.75.75v4.242a.75.75 0 001.5 0v-2.43l.31.31a7 7 0 0011.712-3.138.75.75 0 00-1.449-.39zm1.23-3.723a.75.75 0 00.219-.53V2.929a.75.75 0 00-1.5 0V5.36l-.31-.31A7 7 0 002.239 8.188a.75.75 0 101.448.389A5.5 5.5 0 0112.88 6.11l.311.31h-2.432a.75.75 0 000 1.5h4.243a.75.75 0 00.53-.219z" clipRule="evenodd" />
                      </svg>
                      Restore
                    </button>
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

      {restoring && (
        <ConfirmDialog
          title={`Restore this ${recordLabel.toLowerCase()}?`}
          message="It will reappear in its original list, exactly as it was before deletion."
          confirmLabel="Restore"
          onConfirm={handleRestore}
          onCancel={() => setRestoring(null)}
        />
      )}
    </div>
  )
}

const assetColumns = [
  { key: 'propertyNumber', label: 'Property Number', render: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.propertyNumber}</span> },
  { key: 'description', label: 'Description' },
  { key: 'categoryName', label: 'Category' },
  { key: 'officeName', label: 'Office' },
  { key: 'deletedByUsername', label: 'Deleted By' },
  { key: 'deletedAt', label: 'Deleted At', render: (r) => fmtDateTime(r.deletedAt) },
  { key: 'deleteReason', label: 'Reason', render: (r) => r.deleteReason || '—' },
]
const assetMatches = (r, q) =>
  r.propertyNumber?.toLowerCase().includes(q) ||
  r.description?.toLowerCase().includes(q) ||
  r.categoryName?.toLowerCase().includes(q) ||
  r.officeName?.toLowerCase().includes(q) ||
  r.deletedByUsername?.toLowerCase().includes(q)

const maintenanceColumns = [
  { key: 'propertyNumber', label: 'Property Number', render: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.propertyNumber}</span> },
  { key: 'assetDescription', label: 'Asset Description' },
  { key: 'maintenanceType', label: 'Type', render: (r) => <Badge className={MAINTENANCE_TYPE_BADGE[r.maintenanceType]}>{r.maintenanceType}</Badge> },
  { key: 'status', label: 'Status', render: (r) => <Badge className={MAINTENANCE_STATUS_BADGE[r.status]}>{r.status}</Badge> },
  { key: 'deletedByUsername', label: 'Deleted By' },
  { key: 'deletedAt', label: 'Deleted At', render: (r) => fmtDateTime(r.deletedAt) },
  { key: 'deleteReason', label: 'Reason', render: (r) => r.deleteReason || '—' },
]
const maintenanceMatches = (r, q) =>
  r.propertyNumber?.toLowerCase().includes(q) ||
  r.assetDescription?.toLowerCase().includes(q) ||
  r.maintenanceType?.toLowerCase().includes(q) ||
  r.status?.toLowerCase().includes(q) ||
  r.deletedByUsername?.toLowerCase().includes(q)

const disposalColumns = [
  { key: 'propertyNumber', label: 'Property Number', render: (r) => <span className="font-medium text-slate-900 dark:text-white">{r.propertyNumber}</span> },
  { key: 'assetDescription', label: 'Asset Description' },
  { key: 'recommendedMethod', label: 'Method', render: (r) => <Badge className={DISPOSAL_METHOD_BADGE[r.recommendedMethod]}>{r.recommendedMethod}</Badge> },
  { key: 'disposalStatus', label: 'Status', render: (r) => <Badge className={DISPOSAL_STATUS_BADGE[r.disposalStatus]}>{r.disposalStatus}</Badge> },
  { key: 'deletedByUsername', label: 'Deleted By' },
  { key: 'deletedAt', label: 'Deleted At', render: (r) => fmtDateTime(r.deletedAt) },
  { key: 'deleteReason', label: 'Reason', render: (r) => r.deleteReason || '—' },
]
const disposalMatches = (r, q) =>
  r.propertyNumber?.toLowerCase().includes(q) ||
  r.assetDescription?.toLowerCase().includes(q) ||
  r.recommendedMethod?.toLowerCase().includes(q) ||
  r.disposalStatus?.toLowerCase().includes(q) ||
  r.deletedByUsername?.toLowerCase().includes(q)

const TABS = [
  { id: 'assets', label: 'Assets', fetcher: getDeletedAssets, restoreFn: restoreDeletedAsset, columns: assetColumns, matches: assetMatches, emptyMessage: 'No deleted assets.', recordLabel: 'Asset' },
  { id: 'maintenance', label: 'Maintenance', fetcher: getDeletedMaintenance, restoreFn: restoreDeletedMaintenance, columns: maintenanceColumns, matches: maintenanceMatches, emptyMessage: 'No deleted maintenance records.', recordLabel: 'Maintenance record' },
  { id: 'disposal', label: 'Disposal', fetcher: getDeletedDisposal, restoreFn: restoreDeletedDisposal, columns: disposalColumns, matches: disposalMatches, emptyMessage: 'No deleted disposal records.', recordLabel: 'Disposal record' },
]

function DeletedRecords() {
  const [activeTab, setActiveTab] = useState('assets')
  const tab = TABS.find((t) => t.id === activeTab)

  return (
    <MainLayout>
      <div className="flex items-center gap-1 mb-5 border-b border-slate-200 dark:border-zinc-800 overflow-x-auto">
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => setActiveTab(t.id)}
            className={`px-4 py-2.5 text-sm font-medium transition-all border-b-2 -mb-px whitespace-nowrap ${
              activeTab === t.id
                ? 'border-brand-500 text-brand-500 dark:text-brand-400'
                : 'border-transparent text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-300'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <DeletedTab
        key={tab.id}
        fetcher={tab.fetcher}
        restoreFn={tab.restoreFn}
        columns={tab.columns}
        matches={tab.matches}
        emptyMessage={tab.emptyMessage}
        recordLabel={tab.recordLabel}
      />
    </MainLayout>
  )
}

export default DeletedRecords
