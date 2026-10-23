import { useState, useEffect, useCallback, useMemo, useRef, lazy, Suspense } from 'react'
import { useDispatch, useSelector } from 'react-redux'
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
// loaded on first use: it brings the QR drawing code
const QrExportModal = lazy(() => import('./QrExportModal'))
import { Badge, CONDITION_BADGE, LIFECYCLE_BADGE } from './assetBadges'
import { FilterSelect, FilterBar, SearchBox, SearchRow } from '../../components/common/ListKit'
import { exportAssetsToExcel } from './assetExcel'
import { setAssets, addAsset, updateAsset, removeAsset } from '../../store/slices/assetSlice'
import { getAssets, createAsset, updateAsset as updateAssetApi, deleteAsset, bulkImportAssets, getAssetById } from '../../services/assetService'
import { getCategories } from '../../services/categoryService'
import { getOffices } from '../../services/officeService'
import { getPersonnel } from '../../services/personnelService'
import DraftRows from '../../components/common/DraftRows'
import { useDraftList } from '../../hooks/useFormDraft'

const PAGE_SIZE = 25

// The table shows only what identifies an asset and where it stands; everything else (PAR,
// values, dates, quantities, shortage/overage, specs) is in the drawer that opens on click, and
// in the Excel export. Columns drop away on narrow screens instead of scrolling sideways.
const COLUMNS = [
  { label: 'Asset',                  th: '' },
  { label: 'Category',               th: 'hidden lg:table-cell w-[16%]' },
  { label: 'Office / Accountable',   th: 'hidden md:table-cell w-[26%]' },
  { label: 'Condition',              th: 'hidden sm:table-cell w-[9rem]' },
  { label: 'Status',                 th: 'hidden xl:table-cell w-[10rem]' },
]
const TD = 'px-4 py-3 align-top'

const toRow = (a) => ({
  propertyNumber: a.propertyNumber,
  description: a.description,
  categoryName: a.category?.categoryName,
  officeName: a.office?.officeName,
  accountableName: a.accountablePerson?.fullName,
  condition: a.condition,
  lifecycleStatus: a.lifecycleStatus,
})

// One table cell's content. onOpen (saved assets only) makes the description a button, so the
// drawer opens from the keyboard too, not just by clicking the row.
function assetCell(i, r, onOpen) {
  const muted = 'text-slate-600 dark:text-zinc-400'
  switch (i) {
    case 0: return (
      <div className="min-w-0">
        <p className={`font-mono text-xs ${muted}`}>{r.propertyNumber || <span className="italic">Property No. auto-generated</span>}</p>
        {onOpen ? (
          <button type="button" onClick={(e) => { e.stopPropagation(); onOpen() }}
            className="block max-w-full text-left text-sm font-medium text-slate-900 dark:text-white truncate hover:underline rounded">
            {r.description}
          </button>
        ) : (
          <p className="text-sm font-medium text-slate-900 dark:text-white truncate">{r.description || <span className={`italic font-normal ${muted}`}>No description yet</span>}</p>
        )}
        {/* What the hidden columns would say, on screens too narrow to show them */}
        <p className={`md:hidden text-xs ${muted} truncate mt-0.5`}>{r.officeName || 'No office'}</p>
        <div className="sm:hidden mt-1"><Badge map={CONDITION_BADGE} value={r.condition} /></div>
      </div>
    )
    case 1: return <p className={`text-sm ${muted} truncate`}>{r.categoryName || 'N/A'}</p>
    case 2: return (
      <div className="min-w-0">
        <p className="text-sm text-slate-700 dark:text-zinc-200 truncate">{r.officeName || 'N/A'}</p>
        <p className={`text-xs truncate mt-0.5 ${r.accountableName ? muted : 'italic text-amber-800 dark:text-amber-300'}`}>
          {r.accountableName || 'No accountable person'}
        </p>
      </div>
    )
    case 3: return <Badge map={CONDITION_BADGE} value={r.condition} />
    case 4: return <Badge map={LIFECYCLE_BADGE} value={r.lifecycleStatus} />
    default: return null
  }
}

function Assets() {
  const dispatch = useDispatch()
  const isAdmin  = useSelector((s) => s.auth.user?.role === 'ADMIN')
  const toast    = useToast()
  const location = useLocation()

  // Start from the list another page (e.g. Dashboard) already loaded, so the table shows at once;
  // the first fetch below then refreshes it in the background.
  const cachedAssets = useSelector((s) => s.assets.items)
  const refreshCacheSilently = useRef(cachedAssets.length > 0)
  const [items, setItems]           = useState(cachedAssets)
  const [loading, setLoading]       = useState(cachedAssets.length === 0)
  const [categories, setCategories] = useState([])
  const [offices, setOffices]       = useState([])
  const [personnel, setPersonnel]   = useState([])
  const [search, setSearch]         = useState('')
  const [filterCondition, setFilterCondition]   = useState('')
  const [filterLifecycle, setFilterLifecycle]   = useState('')
  const [filterCategory, setFilterCategory]     = useState('')
  const [filterOffice, setFilterOffice]         = useState('')
  const [showMoreFilters, setShowMoreFilters]   = useState(false)
  // A Category or Status filter set from a link (e.g. the Dashboard) must stay visible.
  useEffect(() => { if (filterCategory || filterLifecycle) setShowMoreFilters(true) }, [filterCategory, filterLifecycle])
  const activeFilters = [search.trim(), filterCondition, filterOffice, filterCategory, filterLifecycle].filter(Boolean).length
  const clearFilters = () => {
    setSearch(''); setFilterCondition(''); setFilterOffice(''); setFilterCategory(''); setFilterLifecycle('')
  }
  const [showAdd, setShowAdd]       = useState(false)
  const [showImport, setShowImport] = useState(false)
  // Bulk QR export: while choosing, rows get tick boxes and a click ticks instead of opening.
  const [choosing, setChoosing]     = useState(false)
  const [chosen, setChosen]         = useState(() => new Set())
  const [showQrExport, setShowQrExport] = useState(false)
  const [editing, setEditing]       = useState(null)
  const { drafts, discard: discardDraft } = useDraftList('asset')
  // Reopen the form a draft came from; it restores the draft itself.
  const continueDraft = async (d) => {
    if (d.id === 'new') { setShowAdd(true); return }
    // the list holds summaries; the form needs the full record, or saving would drop fields
    const record = (await getAssetById(d.id).catch(() => null))?.data
    if (!record) { discardDraft(d.key); toast.show('That record no longer exists, so its draft was removed.', 'error'); return }
    setEditing(record)
  }

  // Draft rows use the table's columns: draft fields laid over the saved asset (if editing).
  const draftRecord = (d) => {
    const f = d.data || {}
    const base = d.id === 'new' ? {} : items.find((a) => String(a.id) === d.id) || {}
    const cat = String(f.categoryId || '').startsWith('pre:')
      ? f.categoryId.slice(4)
      : categories.find((c) => String(c.id) === String(f.categoryId))?.categoryName
    return {
      propertyNumber: f.propertyNumber || base.propertyNumber,
      description: f.description || base.description,
      categoryName: cat || base.category?.categoryName,
      officeName: offices.find((o) => String(o.id) === String(f.officeId))?.officeName || base.office?.officeName,
      accountableName: personnel.find((p) => String(p.id) === String(f.personnelId))?.fullName || base.accountablePerson?.fullName,
      condition: f.condition || base.condition,
      lifecycleStatus: base.lifecycleStatus,
    }
  }
  // Same cells as a saved asset's row (see AssetCells), so drafts line up with the table.
  const draftColumns = COLUMNS.map((_, i) => ({ className: `${TD} ${COLUMNS[i].th}`, render: (r) => assetCell(i, r) }))
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
      const { data } = await getAssets(q, { summary: true })
      setItems(data)
      dispatch(setAssets(data))
    } catch {
      if (!silent) toast.show('Failed to load assets.', 'error')
    } finally {
      if (!silent) setLoading(false)
    }
  }, [dispatch, toast])

  const load = useCallback(() => {
    Promise.all([getCategories().catch(() => ({ data: [] })), getOffices().catch(() => ({ data: [] })), getPersonnel().catch(() => ({ data: [] }))])
      .then(([catRes, officeRes, personnelRes]) => { setCategories(catRes.data); setOffices(officeRes.data); setPersonnel(personnelRes.data) })
    fetchAssets(search)
  }, [fetchAssets, search]) // eslint-disable-line

  // The lists for the filters and the forms load after the asset list, so they don't compete
  // with it for the server (a small one: requests sent together slow each other down).
  const refsRequested = useRef(false)
  useEffect(() => {
    if (loading || refsRequested.current) return
    refsRequested.current = true
    Promise.all([getCategories().catch(() => ({ data: [] })), getOffices().catch(() => ({ data: [] })), getPersonnel().catch(() => ({ data: [] }))])
      .then(([catRes, officeRes, personnelRes]) => { setCategories(catRes.data); setOffices(officeRes.data); setPersonnel(personnelRes.data) })
  }, [loading])

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

  useEffect(() => {
    fetchAssets(debouncedSearch, { silent: refreshCacheSilently.current })
    refreshCacheSilently.current = false
  }, [debouncedSearch, fetchAssets])
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
    // The SSE 'asset' CREATED event (emitted server-side before this response
    // returns) can already have added this asset via the listener above -
    // check first so a fast round-trip doesn't insert it a second time.
    setItems((prev) => (prev.some((a) => a.id === data.id) ? prev.map((a) => (a.id === data.id ? data : a)) : [data, ...prev]))
    dispatch(addAsset(data))
    toast.show('Asset created.', 'success')
    if (data.condition === 'REPAIRABLE')    toast.show('Maintenance record auto-created.', 'info')
    if (data.condition === 'UNSERVICEABLE') toast.show('Disposal record auto-created.', 'info')
    // Completes the scan → review → QR flow - manual entry keeps today's behavior.
    if (wasScanned) setQrAsset(data)
  }

  const handleUpdate = async (payload) => {
    const { data } = await updateAssetApi(editing.id, payload)
    setItems((prev) => prev.map((a) => (a.id === data.id ? data : a)))
    dispatch(updateAsset(data))
    if (selected?.id === data.id) setSelected(data)
    setEditing(null)
    toast.show(data.pendingRequest
      ? `Asset updated. ${data.pendingRequest === 'MAINTENANCE' ? 'Maintenance' : 'Disposal'} request sent. An administrator needs to approve it.`
      : 'Asset updated.', 'success')
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

  // The list holds summaries, so the spreadsheet loads the full records first (same search and
  // filters as on screen).
  const [exporting, setExporting] = useState(false)
  const handleExport = async () => {
    if (filtered.length === 0) { toast.show('No assets to export.', 'error'); return }
    setExporting(true)
    try {
      const { data } = await getAssets(debouncedSearch)
      const rows = data.filter(matchesFilters)
      await exportAssetsToExcel(rows)
      toast.show(`Exported ${rows.length} asset${rows.length !== 1 ? 's' : ''}.`, 'success')
    } catch {
      toast.show('Could not prepare the spreadsheet. Try again.', 'error')
    } finally {
      setExporting(false)
    }
  }

  const matchesFilters = (a) => {
    if (filterCondition && a.condition !== filterCondition) return false
    if (filterLifecycle && a.lifecycleStatus !== filterLifecycle) return false
    if (filterCategory && String(a.category?.id) !== filterCategory) return false
    if (filterOffice && String(a.office?.id) !== filterOffice) return false
    return true
  }
  const filtered = useMemo(() => items.filter(matchesFilters),
    [items, filterCondition, filterLifecycle, filterCategory, filterOffice]) // eslint-disable-line react-hooks/exhaustive-deps

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const toggleChosen = (ids, on) => setChosen((prev) => {
    const next = new Set(prev)
    ids.forEach((id) => (on ? next.add(id) : next.delete(id)))
    return next
  })
  const pageAllChosen = paged.length > 0 && paged.every((a) => chosen.has(a.id))
  const allFilteredChosen = filtered.length > 0 && filtered.every((a) => chosen.has(a.id))
  const stopChoosing = () => { setChoosing(false); setChosen(new Set()) }

  // One row per asset (each asset is one physical item). The whole row opens the drawer with
  // the complete details, edit, QR, photos and delete.
  const renderAssetRow = (a) => {
    const row = toRow(a)
    const isChosen = chosen.has(a.id)
    const open = choosing ? () => toggleChosen([a.id], !isChosen) : () => setSelected(a)
    return (
      <tr key={a.id} onClick={open}
        className={`hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100 cursor-pointer ${
          (choosing ? isChosen : selected?.id === a.id) ? 'bg-slate-50 dark:bg-zinc-800/40' : ''}`}>
        {choosing && (
          <td className={`${TD} pr-0`} onClick={(e) => e.stopPropagation()}>
            <input type="checkbox" checked={isChosen} onChange={(e) => toggleChosen([a.id], e.target.checked)}
              aria-label={`Choose ${a.propertyNumber}`} className="mt-1 h-4 w-4 accent-brand-600 cursor-pointer" />
          </td>
        )}
        {COLUMNS.map((c, i) => (
          <td key={c.label} className={`${TD} ${c.th}`}>{assetCell(i, row, i === 0 && !choosing ? open : undefined)}</td>
        ))}
        <td className={`${TD} text-right text-slate-500 dark:text-zinc-400`} aria-hidden="true">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 inline-block mt-1" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" /></svg>
        </td>
      </tr>
    )
  }


  return (
    <MainLayout>
      {/* Toolbar: one search box and the main action, then a few plainly labelled filters.
          Category and Status sit behind "More filters" so the everyday view stays simple. */}
      <div className="flex flex-col gap-2.5 mb-4">
        <SearchRow>
          <SearchBox value={search} onChange={setSearch} label="Search assets"
            placeholder="Search by property no., description, serial no. or person" />
          {isAdmin && (
            <Button size="md" onClick={() => setShowAdd(true)} className="whitespace-nowrap flex-shrink-0">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 sm:mr-1.5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
              </svg>
              <span className="sr-only sm:not-sr-only">Add Asset</span>
            </Button>
          )}
        </SearchRow>

        <FilterBar activeCount={activeFilters} onClear={clearFilters} moreOpen={showMoreFilters} onMoreToggle={setShowMoreFilters}
          more={<>
            <FilterSelect label="Category" value={filterCategory} onChange={setFilterCategory}
              options={categories.map((c) => [String(c.id), c.categoryName])} />
            <FilterSelect label="Status" value={filterLifecycle} onChange={setFilterLifecycle}
              options={[['ASSIGNED', 'Assigned'], ['TRANSFERRED', 'Transferred'], ['UNDER_MAINTENANCE', 'Under maintenance'], ['DISPOSED', 'Disposed']]} />
          </>}>
          <FilterSelect label="Condition" value={filterCondition} onChange={setFilterCondition}
            options={[['SERVICEABLE', 'Serviceable'], ['REPAIRABLE', 'Repairable'], ['UNSERVICEABLE', 'Unserviceable']]} />
          {/* staff only ever see their own office's assets, so they get no office filter */}
          {isAdmin && (
            <FilterSelect label="Office" value={filterOffice} onChange={setFilterOffice}
              options={offices.map((o) => [String(o.id), o.officeName])} />
          )}
        </FilterBar>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-x-3">
          <p className="min-w-0 truncate text-sm font-semibold text-slate-700 dark:text-zinc-300">
            {activeFilters > 0 ? <>Matching<span className="hidden sm:inline"> assets</span></> : 'All assets'}
          </p>
          {!loading && (
            <span className="flex-shrink-0 whitespace-nowrap text-xs font-medium text-slate-600 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {filtered.length.toLocaleString('en-PH')}{filtered.length !== items.length ? ` of ${items.length.toLocaleString('en-PH')}` : ''}
              {/* "128 of 2,423" is clear enough on phones, where the title needs the room */}
              <span className={filtered.length !== items.length ? 'hidden sm:inline' : ''}> asset{filtered.length !== 1 ? 's' : ''}</span>
            </span>
          )}
          {/* The list's own actions: QR codes, download what's shown, bring in a spreadsheet, refresh */}
          <div className="ml-auto flex flex-shrink-0 items-center gap-1">
            <button type="button" onClick={() => (choosing ? stopChoosing() : setChoosing(true))} aria-pressed={choosing}
              aria-label="Export QR codes" title="Export QR codes"
              className={`flex items-center gap-1.5 p-1.5 sm:px-2.5 rounded-md text-sm font-medium transition-colors ${
                choosing ? 'bg-brand-500/10 text-brand-700 dark:text-brand-300' : 'text-slate-700 dark:text-zinc-300 hover:bg-slate-100 dark:hover:bg-zinc-800'}`}>
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} aria-hidden="true"><path strokeLinecap="round" strokeLinejoin="round" d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zM18 18h2v2h-2zM14 18h2M18 14h2" /></svg>
              <span className="hidden sm:inline">QR codes</span>
            </button>
            {/* icon only on phones; the labels stay for screen readers */}
            <button type="button" onClick={handleExport} disabled={exporting} aria-label="Download Excel" title="Download Excel"
              className="flex items-center gap-1.5 p-1.5 sm:px-2.5 rounded-md text-sm font-medium text-slate-700 dark:text-zinc-300 hover:bg-slate-100 dark:hover:bg-zinc-800 disabled:opacity-60 transition-colors">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
              <span className="hidden sm:inline">{exporting ? 'Preparing…' : 'Download Excel'}</span>
            </button>
            {isAdmin && (
              <button type="button" onClick={() => setShowImport(true)} aria-label="Import" title="Import"
                className="flex items-center gap-1.5 p-1.5 sm:px-2.5 rounded-md text-sm font-medium text-slate-700 dark:text-zinc-300 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-colors">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M3 3a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm4.293 8.707a1 1 0 011.414-1.414L9 10.586V17a1 1 0 102 0v-6.414l1.293 1.293a1 1 0 001.414-1.414l-3-3a1 1 0 00-1.414 0l-3 3z" clipRule="evenodd" /></svg>
                <span className="hidden sm:inline">Import</span>
              </button>
            )}
          <button onClick={() => fetchAssets(search)} aria-label="Refresh the list" className="p-1.5 rounded-md text-slate-600 dark:text-zinc-400 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all" title="Refresh">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clipRule="evenodd" /></svg>
          </button>
          </div>
        </div>

        {choosing && (
          <div role="region" aria-label="Choose assets for QR export"
            className="px-5 py-2.5 border-b border-slate-200 dark:border-zinc-800 bg-brand-500/5 flex flex-wrap items-center gap-x-3 gap-y-2">
            <p className="text-sm text-slate-700 dark:text-zinc-200" aria-live="polite">
              <span className="font-semibold">{chosen.size.toLocaleString('en-PH')}</span> chosen
            </p>
            {!allFilteredChosen && filtered.length > 0 && (
              <button type="button" onClick={() => toggleChosen(filtered.map((a) => a.id), true)}
                className="text-sm font-medium text-brand-700 dark:text-brand-300 hover:underline">
                Choose all {filtered.length.toLocaleString('en-PH')}{activeFilters > 0 || search ? ' shown' : ''}
              </button>
            )}
            {chosen.size > 0 && (
              <button type="button" onClick={() => setChosen(new Set())}
                className="text-sm font-medium text-slate-700 dark:text-zinc-300 hover:underline">Clear</button>
            )}
            <div className="ml-auto flex items-center gap-2">
              <Button variant="secondary" size="sm" onClick={stopChoosing}>Cancel</Button>
              <Button size="sm" onClick={() => setShowQrExport(true)} disabled={chosen.size === 0 || chosen.size > 1000}>
                Export QR codes
              </Button>
            </div>
            {chosen.size > 1000 && (
              <p className="basis-full text-xs text-red-700 dark:text-red-300" role="alert">Export at most 1,000 QR codes at a time.</p>
            )}
            {chosen.size === 0 && (
              <p className="basis-full text-xs text-slate-600 dark:text-zinc-400">Tick the assets whose QR codes you want, then press Export QR codes.</p>
            )}
          </div>
        )}

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
          <div className="flex flex-col items-center justify-center py-16 gap-2 text-slate-500 dark:text-zinc-400">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
            </svg>
            <p className="text-sm text-slate-600 dark:text-zinc-400">{items.length === 0 ? 'No assets registered yet.' : 'No assets match your filters.'}</p>
          </div>
        ) : (
          <div>
            <table className="w-full table-fixed text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <caption className="sr-only">Assets. Select an asset to see its complete details.</caption>
              <thead>
                <tr>
                  {choosing && (
                    <th scope="col" className="w-10 pl-4 py-3 text-left">
                      <input type="checkbox" checked={pageAllChosen} onChange={(e) => toggleChosen(paged.map((a) => a.id), e.target.checked)}
                        aria-label="Choose every asset on this page" className="h-4 w-4 accent-brand-600 cursor-pointer" />
                    </th>
                  )}
                  {COLUMNS.map((c) => (
                    <th key={c.label} scope="col" className={`px-4 py-3 text-left text-xs font-semibold text-slate-600 dark:text-zinc-400 uppercase tracking-wide ${c.th}`}>{c.label}</th>
                  ))}
                  {/* Wide enough for a draft row's Continue / Discard buttons */}
                  <th scope="col" className={drafts.length ? 'w-[8.5rem]' : 'w-10'}><span className="sr-only">Open</span></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {/* unsaved drafts have no QR code yet, so they step aside while choosing */}
                {!choosing && <DraftRows drafts={drafts} columns={draftColumns} toRecord={draftRecord} onContinue={continueDraft} onDiscard={discardDraft} />}
                {paged.map((a) => renderAssetRow(a))}
              </tbody>
            </table>
          </div>
        )}

        {!loading && filtered.length > PAGE_SIZE && (
          <div className="px-5 py-3 border-t border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
            <p className="text-xs text-slate-600 dark:text-zinc-400">
              {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filtered.length)} of {filtered.length}
            </p>
            <div className="flex items-center gap-1">
              <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}
                className="px-2.5 py-1.5 text-xs rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">Prev</button>
              <span className="text-xs text-slate-600 dark:text-zinc-400 px-2">Page {page} of {totalPages}</span>
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
          onDelete={isAdmin ? (a) => { setDeleting(a); setSelected(null) } : undefined}
        />
      )}

      {showAdd && (
        <AddAssetModal
          onClose={() => setShowAdd(false)}
          onSave={handleCreate}
          categories={categories}
          offices={offices}
          personnel={personnel}
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
          personnel={personnel}
          staffMode={!isAdmin}
          onCategoryCreated={(cat) => setCategories((prev) => [...prev, cat])}
        />
      )}
      {showImport && <AssetImportModal onClose={() => setShowImport(false)} onImport={handleImport} />}
      {showQrExport && (
        <Suspense fallback={null}>
          <QrExportModal ids={[...chosen]} onClose={() => setShowQrExport(false)}
            onDone={() => { setShowQrExport(false); stopChoosing() }} />
        </Suspense>
      )}
      {qrAsset && <AssetQrModal asset={qrAsset} onClose={() => setQrAsset(null)} />}
      {deleting && (
        <ConfirmDialog
          title="Delete this asset?"
          message={
            <div className="space-y-3">
              <p className="text-sm text-slate-600 dark:text-zinc-300">
                <span className="font-semibold">{deleting.propertyNumber}</span>: {deleting.description} will be archived and removed from the active list.
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

export default Assets
