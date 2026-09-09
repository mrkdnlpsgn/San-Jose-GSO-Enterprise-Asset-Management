import { useState, useEffect, useCallback, useMemo } from 'react'
import { useDispatch } from 'react-redux'
import { useLocation } from 'react-router-dom'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import { useEventStream } from '../../hooks/useEventStream'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import AddAssetModal from './AddAssetModal'
import AssetDrawer from './AssetDrawer'
import AssetImportModal from './AssetImportModal'
import AssetQrModal from './AssetQrModal'
import { exportAssetsToExcel } from './assetExcel'
import { setAssets, addAsset, updateAsset, removeAsset } from '../../store/slices/assetSlice'
import { getAssets, createAsset, updateAsset as updateAssetApi, deleteAsset, bulkImportAssets } from '../../services/assetService'
import { getCategories } from '../../services/categoryService'
import { getOffices } from '../../services/officeService'

const CONDITION_BADGE = {
  SERVICEABLE:   'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  REPAIRABLE:    'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  UNSERVICEABLE: 'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
}
const LIFECYCLE_BADGE = {
  REGISTERED:        'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  ASSIGNED:          'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  TRANSFERRED:       'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
  UNDER_MAINTENANCE: 'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  DISPOSED:          'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
  ARCHIVED:          'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20',
}

function fmt(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}
function php(v) {
  if (v == null) return '—'
  return '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 })
}

const PAGE_SIZE = 8

function Assets() {
  const dispatch = useDispatch()
  const toast    = useToast()
  const location = useLocation()

  const [items, setItems]           = useState([])
  const [loading, setLoading]       = useState(true)
  const [categories, setCategories] = useState([])
  const [offices, setOffices]       = useState([])
  const [search, setSearch]         = useState('')
  const [filterCondition, setFilterCondition]   = useState('')
  const [filterLifecycle, setFilterLifecycle]   = useState('')
  const [filterCategory, setFilterCategory]     = useState('')
  const [filterOffice, setFilterOffice]         = useState('')
  const [showAdd, setShowAdd]       = useState(false)
  const [showImport, setShowImport] = useState(false)
  const [editing, setEditing]       = useState(null)
  const [deleting, setDeleting]     = useState(null)
  const [deleteReason, setDeleteReason] = useState('')
  const [selected, setSelected]     = useState(null)
  const [assetDrawerExiting, setAssetDrawerExiting] = useState(false)
  const [page, setPage]             = useState(1)
  const [qrAsset, setQrAsset]       = useState(null)

  const debouncedSearch = useDebounce(search, 300)

  // Plays the drawer's slide-out/fade-out (see AssetDrawer.jsx) before actually
  // unmounting it, mirroring RecordDrawer.jsx's closeDetail in Inventory/index.jsx.
  const closeAssetDrawer = useCallback(() => {
    setAssetDrawerExiting(true)
    setTimeout(() => { setSelected(null); setAssetDrawerExiting(false) }, 220)
  }, [])

  const fetchAssets = useCallback(async (q = '', { silent = false } = {}) => {
    if (!silent) setLoading(true)
    try {
      const { data } = await getAssets(q)
      setItems(data)
      dispatch(setAssets(data))
    } catch {
      if (!silent) toast.show('Failed to load assets.', 'error')
    } finally {
      if (!silent) setLoading(false)
    }
  }, [dispatch, toast])

  const load = useCallback(() => {
    Promise.all([getCategories().catch(() => ({ data: [] })), getOffices().catch(() => ({ data: [] }))])
      .then(([catRes, officeRes]) => { setCategories(catRes.data); setOffices(officeRes.data) })
    fetchAssets(search)
  }, [fetchAssets, search]) // eslint-disable-line

  useEffect(() => {
    Promise.all([getCategories().catch(() => ({ data: [] })), getOffices().catch(() => ({ data: [] }))])
      .then(([catRes, officeRes]) => { setCategories(catRes.data); setOffices(officeRes.data) })
  }, [])

  // Dashboard charts link here with a pre-set filter, e.g. /assets?condition=REPAIRABLE
  useEffect(() => {
    const params = new URLSearchParams(location.search)
    const condition = params.get('condition')
    const lifecycle = params.get('lifecycle')
    const category  = params.get('category')
    const office    = params.get('office')
    const searchParam = params.get('search')
    if (condition) setFilterCondition(condition)
    if (lifecycle) setFilterLifecycle(lifecycle)
    if (category)  setFilterCategory(category)
    if (office)    setFilterOffice(office)
    if (searchParam) setSearch(searchParam)
  }, [location.search])

  useEffect(() => { fetchAssets(debouncedSearch) }, [debouncedSearch, fetchAssets])
  useEffect(() => { setPage(1) }, [debouncedSearch, filterCondition, filterLifecycle, filterCategory, filterOffice])

  useEventStream('asset', ({ action, id, data }) => {
    if (action === 'DELETED') {
      setItems((prev) => prev.filter((a) => a.id !== id))
      dispatch(removeAsset(id))
      return
    }
    if (!data) { fetchAssets(search); return }
    const exists = items.some((a) => a.id === data.id)
    setItems((prev) => (exists ? prev.map((a) => (a.id === data.id ? data : a)) : [data, ...prev]))
    dispatch(exists ? updateAsset(data) : addAsset(data))
  })

  const handleCreate = async (payload, idempotencyKey, wasScanned) => {
    const { data } = await createAsset(payload, idempotencyKey)
    setItems((prev) => [data, ...prev])
    dispatch(addAsset(data))
    toast.show('Asset created.', 'success')
    if (data.condition === 'REPAIRABLE')    toast.show('Maintenance record auto-created.', 'info')
    if (data.condition === 'UNSERVICEABLE') toast.show('Disposal record auto-created.', 'info')
    // Completes the scan → review → QR flow — manual entry keeps today's behavior.
    if (wasScanned) setQrAsset(data)
  }

  const handleUpdate = async (payload) => {
    const { data } = await updateAssetApi(editing.id, payload)
    setItems((prev) => prev.map((a) => (a.id === data.id ? data : a)))
    dispatch(updateAsset(data))
    if (selected?.id === data.id) setSelected(data)
    setEditing(null)
    toast.show('Asset updated.', 'success')
  }

  const handleDelete = async () => {
    try {
      await deleteAsset(deleting.id, { deleteReason })
      setItems((prev) => prev.filter((a) => a.id !== deleting.id))
      dispatch(removeAsset(deleting.id))
      if (selected?.id === deleting.id) setSelected(null)
      toast.show('Asset deleted.', 'warning')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to delete.', 'error')
    } finally {
      setDeleting(null)
      setDeleteReason('')
    }
  }

  const handleImport = async (rows) => {
    try {
      const { data } = await bulkImportAssets(rows)
      const savedItems = data?.saved ?? []
      if (savedItems.length > 0) {
        setItems((prev) => [...savedItems, ...prev])
        dispatch(setAssets([...savedItems, ...items]))
        toast.show(`${savedItems.length} asset${savedItems.length !== 1 ? 's' : ''} imported.`, 'success')
      }
      return data
    } catch (err) {
      toast.show(err.response?.data?.message || 'Import failed.', 'error')
      return { saved: [], failed: rows.map((row) => ({ row, reason: 'Import request failed.' })) }
    }
  }

  const handleExport = () => {
    if (filtered.length === 0) { toast.show('No assets to export.', 'error'); return }
    exportAssetsToExcel(filtered)
    toast.show(`Exported ${filtered.length} asset${filtered.length !== 1 ? 's' : ''}.`, 'success')
  }

  const filtered = useMemo(() => {
    return items.filter((a) => {
      if (filterCondition && a.condition !== filterCondition) return false
      if (filterLifecycle && a.lifecycleStatus !== filterLifecycle) return false
      if (filterCategory && String(a.category?.id) !== filterCategory) return false
      if (filterOffice && String(a.office?.id) !== filterOffice) return false
      return true
    })
  }, [items, filterCondition, filterLifecycle, filterCategory, filterOffice])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  return (
    <MainLayout>
      <div className="flex flex-col gap-3 mb-5">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
          <div className="relative w-full sm:max-w-xs">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
            </svg>
            <input type="text" placeholder="Search assets…" value={search} onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
          </div>
          <div className="flex items-center gap-2 self-start sm:self-auto">
            <Button variant="secondary" size="md" onClick={handleExport}>
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M3 3a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm4.293 8.707a1 1 0 011.414-1.414L9 10.586V17a1 1 0 102 0v-6.414l1.293 1.293a1 1 0 001.414-1.414l-3-3a1 1 0 00-1.414 0l-3 3z" clipRule="evenodd" />
              </svg>
              Export
            </Button>
            <Button variant="secondary" size="md" onClick={() => setShowImport(true)}>
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
              Import
            </Button>
            <Button size="md" onClick={() => setShowAdd(true)}>
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
              </svg>
              Add Asset
            </Button>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {[['', 'All Conditions'], ['SERVICEABLE', 'Serviceable'], ['REPAIRABLE', 'Repairable'], ['UNSERVICEABLE', 'Unserviceable']].map(([val, label]) => (
            <button key={val} onClick={() => setFilterCondition(val)}
              className={`text-xs px-2.5 py-1.5 rounded-lg border font-medium transition-all ${
                filterCondition === val
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-zinc-900 border-slate-900 dark:border-white'
                  : 'border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800'
              }`}>{label}</button>
          ))}
          <SelectFilter value={filterLifecycle} onChange={setFilterLifecycle} placeholder="All Statuses"
            options={[['REGISTERED','Registered'],['ASSIGNED','Assigned'],['TRANSFERRED','Transferred'],['UNDER_MAINTENANCE','Under Maintenance'],['DISPOSED','Disposed'],['ARCHIVED','Archived']]} />
          <SelectFilter value={filterCategory} onChange={setFilterCategory} placeholder="All Categories"
            options={categories.map((c) => [String(c.id), c.categoryName])} />
          <SelectFilter value={filterOffice} onChange={setFilterOffice} placeholder="All Offices"
            options={offices.map((o) => [String(o.id), o.officeName])} />
        </div>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">All Assets</p>
          {!loading && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {filtered.length}{filtered.length !== items.length ? ` of ${items.length}` : ''} asset{filtered.length !== 1 ? 's' : ''}
            </span>
          )}
          <button onClick={() => fetchAssets(search)} className="ml-auto p-1.5 rounded-md text-slate-400 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all" title="Refresh">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clipRule="evenodd" /></svg>
          </button>
        </div>

        {loading ? (
          <div className="divide-y divide-slate-100 dark:divide-zinc-800">
            {Array.from({ length: 6 }).map((_, i) => (
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
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
            </svg>
            <p className="text-sm text-zinc-500">{items.length === 0 ? 'No assets registered yet.' : 'No assets match your filters.'}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Property No.', 'Description', 'Category', 'Qty (Property Card)', 'Qty (Physical Count)', 'Shortage/Overage Qty', 'Shortage/Overage Value', 'Location', 'Unit Value', 'Date', 'Remarks', ''].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((a) => (
                  <tr key={a.id}
                    onClick={() => setSelected(a)}
                    className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100 cursor-pointer">
                    <td className="px-5 py-3.5 whitespace-nowrap">
                      <span className="font-mono text-xs text-slate-600 dark:text-zinc-300">{a.propertyNumber}</span>
                    </td>
                    <td className="px-5 py-3.5">
                      <p className="text-sm font-medium text-slate-900 dark:text-white truncate max-w-[180px]">{a.description}</p>
                    </td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{a.category?.categoryName || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap text-center">{a.quantity ?? '—'}</td>
                    <td className="px-5 py-3.5 text-xs whitespace-nowrap text-center">
                      {a.physicalCount != null ? a.physicalCount : <span className="text-slate-400 dark:text-zinc-600">—</span>}
                    </td>
                    {(() => {
                      const diff = a.physicalCount != null ? a.physicalCount - (a.quantity ?? 0) : null
                      const val  = diff != null ? diff * Number(a.unitValue ?? 0) : null
                      const color = diff == null ? '' : diff < 0 ? 'text-red-400' : diff > 0 ? 'text-emerald-400' : 'text-slate-400 dark:text-zinc-500'
                      return (
                        <>
                          <td className={`px-5 py-3.5 text-xs whitespace-nowrap text-center font-medium ${color}`}>
                            {diff == null ? <span className="text-slate-400 dark:text-zinc-600">—</span> : diff > 0 ? `+${diff}` : diff}
                          </td>
                          <td className={`px-5 py-3.5 text-xs whitespace-nowrap text-center font-medium ${color}`}>
                            {val == null ? <span className="text-slate-400 dark:text-zinc-600">—</span> : (val > 0 ? '+' : '') + '₱' + Math.abs(val).toLocaleString('en-PH', { minimumFractionDigits: 2 })}
                          </td>
                        </>
                      )
                    })()}
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{a.office?.officeName || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{php(a.unitValue)}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{fmt(a.acquisitionDate)}</td>
                    <td className="px-5 py-3.5 text-xs max-w-[200px]">
                      <div className="flex flex-col gap-1">
                        <span className={`inline-flex items-center self-start px-2 py-0.5 rounded-full text-xs font-semibold ${CONDITION_BADGE[a.condition] || ''}`}>{a.condition}</span>
                        {a.remarks && <span className="text-slate-500 dark:text-zinc-400 truncate" title={a.remarks}>{a.remarks}</span>}
                      </div>
                    </td>
                    <td className="px-5 py-3.5" onClick={(e) => e.stopPropagation()}>
                      <div className="flex items-center justify-end gap-1">
                        <button onClick={() => setEditing(a)} title="Edit"
                          className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" /></svg>
                        </button>
                        <button onClick={() => setDeleting(a)} title="Delete"
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

      {selected && (
        <AssetDrawer
          asset={selected}
          exiting={assetDrawerExiting}
          onClose={closeAssetDrawer}
          onEdit={(a) => { setEditing(a); setSelected(null) }}
        />
      )}

      {showAdd && (
        <AddAssetModal
          onClose={() => setShowAdd(false)}
          onSave={handleCreate}
          categories={categories}
          offices={offices}
          onCategoryCreated={(cat) => setCategories((prev) => [...prev, cat])}
        />
      )}
      {editing && (
        <AddAssetModal
          initial={editing}
          onClose={() => setEditing(null)}
          onSave={handleUpdate}
          categories={categories}
          offices={offices}
          onCategoryCreated={(cat) => setCategories((prev) => [...prev, cat])}
        />
      )}
      {showImport && <AssetImportModal onClose={() => setShowImport(false)} onImport={handleImport} />}
      {qrAsset && <AssetQrModal asset={qrAsset} onClose={() => setQrAsset(null)} />}
      {deleting && (
        <ConfirmDialog
          title="Delete this asset?"
          message={
            <div className="space-y-3">
              <p className="text-sm text-slate-600 dark:text-zinc-300">
                <span className="font-semibold">{deleting.propertyNumber}</span> — {deleting.description} will be archived and removed from the active list.
              </p>
              <div>
                <label className="text-xs font-medium text-slate-600 dark:text-zinc-400">Reason (optional)</label>
                <input
                  type="text"
                  value={deleteReason}
                  onChange={(e) => setDeleteReason(e.target.value)}
                  placeholder="Enter reason for deletion…"
                  className="mt-1 w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3 py-2 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-brand-500"
                />
              </div>
            </div>
          }
          confirmLabel="Delete Asset"
          onConfirm={handleDelete}
          onCancel={() => { setDeleting(null); setDeleteReason('') }}
        />
      )}
    </MainLayout>
  )
}

function SelectFilter({ value, onChange, placeholder, options }) {
  return (
    <div className="relative">
      <select value={value} onChange={(e) => onChange(e.target.value)}
        className="appearance-none text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 px-3 py-1.5 pr-8 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all">
        <option value="">{placeholder}</option>
        {options.map(([val, label]) => <option key={val} value={val}>{label}</option>)}
      </select>
      <div className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 dark:text-zinc-500">
        <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
      </div>
    </div>
  )
}

export default Assets
