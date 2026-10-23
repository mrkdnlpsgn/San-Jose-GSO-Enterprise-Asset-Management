import { useState, useEffect, useMemo, useRef } from 'react'
import MainLayout from '../../components/layout/MainLayout'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import { useToast } from '../../context/ToastContext'
import {
  getDeletedAssets, getDeletedMaintenance, getDeletedDisposal,
  restoreDeletedAsset, restoreDeletedMaintenance, restoreDeletedDisposal,
  requestDeleteOtp, permanentDeleteAsset, permanentDeleteMaintenance, permanentDeleteDisposal,
} from '../../services/deletedRecordsService'
import { useDebounce } from '../../hooks/useDebounce'
import { usePolling } from '../../hooks/usePolling'
import {
  SearchBox, ListCard, RefreshButton, Pager, ListSkeleton, ListEmpty, DataTable, PrimaryCell, MutedCell, MappedBadge, ICON, fmtDate,
} from '../../components/common/ListKit'
import DetailModal, { DetailGrid, DetailSection, DetailField, ModalAction } from '../../components/common/DetailModal'

const RESEND_COOLDOWN_SECONDS = 60

// Step-up 2FA before an irreversible delete: emails a one-time code on open,
// then requires it back before calling permanentDeleteFn. Two states - the
// code is either in flight (sending/sent/cooldown) or being verified - kept
// separate from ConfirmDialog since neither its single-button flow nor its
// styling fit a two-step, form-carrying confirmation.
function PermanentDeleteModal({ recordLabel, onClose, onConfirm }) {
  const toast = useToast()
  const [sending, setSending]   = useState(false)
  const [sent, setSent]         = useState(false)
  const [cooldown, setCooldown] = useState(0)
  const [otp, setOtp]           = useState('')
  const [error, setError]       = useState('')
  const [deleting, setDeleting] = useState(false)
  const cooldownRef = useRef(null)

  const startCooldown = () => {
    setCooldown(RESEND_COOLDOWN_SECONDS)
    clearInterval(cooldownRef.current)
    cooldownRef.current = setInterval(() => {
      setCooldown((c) => {
        if (c <= 1) { clearInterval(cooldownRef.current); return 0 }
        return c - 1
      })
    }, 1000)
  }

  const sendCode = async () => {
    setSending(true)
    setError('')
    try {
      await requestDeleteOtp()
      setSent(true)
      startCooldown()
      toast.show('Verification code sent to your email.', 'info')
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to send verification code.')
    } finally {
      setSending(false)
    }
  }

  useEffect(() => {
    sendCode()
    return () => clearInterval(cooldownRef.current)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const handleConfirm = async () => {
    if (otp.trim().length !== 6) { setError('Enter the 6-digit code from your email.'); return }
    setDeleting(true)
    setError('')
    try {
      await onConfirm(otp.trim())
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to verify code.')
      setDeleting(false)
    }
  }

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 animate-fade-slide" role="alertdialog" aria-modal="true">
      <div className="absolute inset-0 bg-black/30 dark:bg-zinc-950/80" onClick={onClose} />
      <div className="relative bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 rounded-xl shadow-2xl shadow-black/10 dark:shadow-black/60 w-full max-w-sm p-6">
        <div className="w-11 h-11 rounded-full bg-red-50 dark:bg-red-950 flex items-center justify-center mx-auto mb-4">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-red-500 dark:text-red-400" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M10 1a4.5 4.5 0 00-4.5 4.5V9H5a2 2 0 00-2 2v6a2 2 0 002 2h10a2 2 0 002-2v-6a2 2 0 00-2-2h-.5V5.5A4.5 4.5 0 0010 1zm3 8V5.5a3 3 0 10-6 0V9h6z" clipRule="evenodd" />
          </svg>
        </div>

        <h2 className="text-sm font-semibold text-gov-700 dark:text-white text-center">
          Permanently delete this {recordLabel.toLowerCase()}?
        </h2>
        <p className="text-xs text-slate-500 dark:text-zinc-400 text-center mt-2 leading-relaxed">
          This cannot be undone. The record will be completely removed, not just moved out of Recovery.
          {sending ? ' Sending a verification code to your email…' :
            sent ? ' Enter the verification code we emailed you to confirm.' : ''}
        </p>

        {sent && (
          <div className="mt-4">
            <input
              type="text"
              inputMode="numeric"
              maxLength={6}
              autoFocus
              placeholder="6-digit code"
              value={otp}
              onChange={(e) => { setOtp(e.target.value.replace(/\D/g, '')); setError('') }}
              className="w-full text-center tracking-[0.5em] font-mono text-lg rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 bg-white dark:bg-zinc-800 text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500 transition-all"
            />
            <div className="flex justify-center mt-2">
              <button
                type="button"
                onClick={sendCode}
                disabled={cooldown > 0 || sending}
                className="text-xs font-medium text-brand-600 dark:text-brand-400 hover:underline disabled:opacity-40 disabled:no-underline disabled:cursor-not-allowed"
              >
                {cooldown > 0 ? `Resend code in ${cooldown}s` : 'Resend code'}
              </button>
            </div>
          </div>
        )}

        {error && <p className="text-xs text-red-700 dark:text-red-300 text-center mt-3" role="alert">{error}</p>}

        <div className="flex gap-3 mt-6">
          <button
            onClick={onClose}
            className="flex-1 py-2.5 text-sm font-semibold rounded-md bg-slate-100 dark:bg-zinc-800 text-slate-700 dark:text-zinc-300 border border-slate-200 dark:border-zinc-700 hover:bg-slate-200 dark:hover:bg-zinc-700 transition-all duration-150 active:scale-[0.97]"
          >
            Cancel
          </button>
          <button
            onClick={handleConfirm}
            disabled={!sent || deleting || otp.trim().length !== 6}
            className="flex-1 py-2.5 text-sm font-semibold rounded-md bg-red-600 text-white hover:bg-red-500 active:bg-red-700 transition-all duration-150 active:scale-[0.97] disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {deleting ? 'Deleting…' : 'Permanently Delete'}
          </button>
        </div>
      </div>
    </div>
  )
}

const MAINTENANCE_TYPE = {
  PREVENTIVE: { label: 'Preventive', tone: 'blue' },
  CORRECTIVE: { label: 'Corrective', tone: 'violet' },
  REPAIR:     { label: 'Repair',     tone: 'amber' },
}
const DISPOSAL_METHOD = {
  SALE:        { label: 'Sale',        tone: 'blue' },
  TRANSFER:    { label: 'Transfer',    tone: 'violet' },
  DESTRUCTION: { label: 'Destruction', tone: 'red' },
  OTHERS:      { label: 'Others',      tone: 'slate' },
}
const PAGE_SIZE = 5

function fmtDateTime(dt) {
  if (!dt) return 'N/A'
  return new Date(dt).toLocaleString('en-PH', {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}

// One shared shape for all three tabs: fetch on mount, filter by a search predicate, a compact
// table (record, kind, who deleted it, when), and a details window with the reason and the two
// actions - Restore, or Permanently delete (which asks for an emailed code first).
function DeletedTab({ fetcher, restoreFn, permanentDeleteFn, columns, matches, details, emptyMessage, recordLabel, searchHint }) {
  const toast = useToast()
  const [rows, setRows]       = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch]   = useState('')
  const [viewing, setViewing]     = useState(null)
  const [restoring, setRestoring] = useState(null) // row pending confirmation
  const [deleting, setDeleting]   = useState(null) // row pending permanent-delete 2FA
  const [page, setPage]           = useState(1)
  const debouncedSearch       = useDebounce(search)

  const load = () => fetcher().then(({ data }) => setRows(data)).catch(() => {})
  useEffect(() => {
    let alive = true
    setLoading(true)
    fetcher()
      .then(({ data }) => { if (alive) setRows(data) })
      .catch(() => { if (alive) setRows([]) })
      .finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [fetcher])

  // Background poll - never touches `loading`, so a silent refresh can't
  // flash the skeleton back in over rows already on screen.
  usePolling(load, 30000)

  const filtered = useMemo(() => {
    const q = debouncedSearch.trim().toLowerCase()
    if (!q) return rows
    return rows.filter((r) => matches(r, q))
  }, [rows, debouncedSearch, matches])

  useEffect(() => { setPage(1) }, [debouncedSearch])
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const handleRestore = async () => {
    const row = restoring
    setRestoring(null)
    try {
      await restoreFn(row.id)
      setRows((prev) => prev.filter((r) => r.id !== row.id))
      setViewing(null)
      toast.show(`${recordLabel} restored.`, 'success')
    } catch (err) {
      toast.show(err.response?.data?.message || `Failed to restore ${recordLabel.toLowerCase()}.`, 'error')
    }
  }

  const handlePermanentDelete = async (otp) => {
    const row = deleting
    await permanentDeleteFn(row.id, otp)
    setRows((prev) => prev.filter((r) => r.id !== row.id))
    setDeleting(null)
    setViewing(null)
    toast.show(`${recordLabel} permanently deleted.`, 'warning')
  }

  const v = viewing

  return (
    <>
      <div className="flex items-stretch gap-2 mb-4">
        <SearchBox value={search} onChange={setSearch} label={`Search deleted ${recordLabel.toLowerCase()}s`} placeholder={searchHint} />
      </div>

      <ListCard title="Recovery" filtered={filtered.length !== rows.length} count={filtered.length} total={rows.length} loading={loading}
        actions={<RefreshButton onClick={load} />}
        footer={!loading && <Pager page={page} pageSize={PAGE_SIZE} total={filtered.length} onPage={setPage} />}>
        {loading ? <ListSkeleton rows={5} /> : filtered.length === 0 ? (
          <ListEmpty>{rows.length === 0 ? emptyMessage : 'No records match your search.'}</ListEmpty>
        ) : (
          <DataTable columns={columns} rows={paged} rowKey={(r) => r.id} onOpen={setViewing} selectedKey={v?.id}
            caption={`Deleted ${recordLabel.toLowerCase()}s. Select one to restore it or delete it permanently.`} />
        )}
      </ListCard>

      {v && (
        <DetailModal
          title={v.description || v.assetDescription || recordLabel}
          label={`Deleted ${recordLabel.toLowerCase()}: ${v.propertyNumber || ''}`}
          escDisabled={!!(restoring || deleting)}
          onClose={() => setViewing(null)}
          subtitle={<>
            <span className="text-slate-600 dark:text-zinc-400">Property No.</span>
            <span className="font-mono font-semibold text-slate-900 dark:text-zinc-100">{v.propertyNumber || 'N/A'}</span>
          </>}
          footer={<>
            <ModalAction label={`Restore ${recordLabel.toLowerCase()}`} icon={ICON.restore} tone="primary" onClick={() => setRestoring(v)} />
            <span className="sm:ml-auto"><ModalAction label="Delete permanently" icon={ICON.trash} tone="danger" onClick={() => setDeleting(v)} /></span>
          </>}
        >
          <DetailGrid>
            <DetailSection title={recordLabel}>{details(v)}</DetailSection>
            <DetailSection title="Deletion">
              <DetailField label="Deleted by" value={v.deletedByUsername} />
              <DetailField label="Deleted" value={fmtDateTime(v.deletedAt)} />
              <DetailField label="Reason" value={v.deleteReason} />
            </DetailSection>
          </DetailGrid>
        </DetailModal>
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

      {deleting && (
        <PermanentDeleteModal
          recordLabel={recordLabel}
          onClose={() => setDeleting(null)}
          onConfirm={handlePermanentDelete}
        />
      )}
    </>
  )
}

// Columns every tab shares after its own first two.
const deletedCols = [
  { key: 'by', label: 'Deleted by', className: 'hidden lg:table-cell w-[16%]', cell: (r) => <MutedCell>{r.deletedByUsername}</MutedCell> },
  { key: 'at', label: 'Deleted', className: 'hidden sm:table-cell w-[10rem]', cell: (r) => <MutedCell>{fmtDate(r.deletedAt)}</MutedCell> },
]
const recordCell = (title) => (r, open) => (
  <PrimaryCell code={r.propertyNumber} title={title(r)} open={open}
    extra={<p className="sm:hidden text-xs text-slate-600 dark:text-zinc-400 mt-0.5">Deleted {fmtDate(r.deletedAt)}</p>} />
)

const assetColumns = [
  { key: 'record', label: 'Asset', cell: recordCell((r) => r.description) },
  { key: 'office', label: 'Office', className: 'hidden md:table-cell w-[24%]', cell: (r) => <MutedCell sub={r.categoryName}>{r.officeName}</MutedCell> },
  ...deletedCols,
]
const assetMatches = (r, q) =>
  r.propertyNumber?.toLowerCase().includes(q) ||
  r.parNumber?.toLowerCase().includes(q) ||
  r.description?.toLowerCase().includes(q) ||
  r.categoryName?.toLowerCase().includes(q) ||
  r.officeName?.toLowerCase().includes(q) ||
  r.deletedByUsername?.toLowerCase().includes(q)

const maintenanceColumns = [
  { key: 'record', label: 'Maintenance of', cell: recordCell((r) => r.assetDescription) },
  { key: 'type', label: 'Type', className: 'hidden md:table-cell w-[9rem]', cell: (r) => <MappedBadge map={MAINTENANCE_TYPE} value={r.maintenanceType} /> },
  ...deletedCols,
]
const maintenanceMatches = (r, q) =>
  r.propertyNumber?.toLowerCase().includes(q) ||
  r.parNumber?.toLowerCase().includes(q) ||
  r.assetDescription?.toLowerCase().includes(q) ||
  r.maintenanceType?.toLowerCase().includes(q) ||
  r.status?.toLowerCase().includes(q) ||
  r.deletedByUsername?.toLowerCase().includes(q)

const disposalColumns = [
  { key: 'record', label: 'Disposal of', cell: recordCell((r) => r.assetDescription) },
  { key: 'method', label: 'Method', className: 'hidden md:table-cell w-[9rem]', cell: (r) => <MappedBadge map={DISPOSAL_METHOD} value={r.recommendedMethod} /> },
  ...deletedCols,
]
const disposalMatches = (r, q) =>
  r.propertyNumber?.toLowerCase().includes(q) ||
  r.parNumber?.toLowerCase().includes(q) ||
  r.assetDescription?.toLowerCase().includes(q) ||
  r.recommendedMethod?.toLowerCase().includes(q) ||
  r.disposalStatus?.toLowerCase().includes(q) ||
  r.deletedByUsername?.toLowerCase().includes(q)

const lower = (s) => (s ? String(s).charAt(0) + String(s).slice(1).toLowerCase() : '')

const TABS = [
  { id: 'assets', label: 'Assets', fetcher: getDeletedAssets, restoreFn: restoreDeletedAsset, permanentDeleteFn: permanentDeleteAsset,
    columns: assetColumns, matches: assetMatches, emptyMessage: 'No deleted assets.', recordLabel: 'Asset',
    searchHint: 'Search by property no., description, office or who deleted it',
    details: (r) => (<>
      <DetailField label="PAR Number" value={r.parNumber} mono />
      <DetailField label="Category" value={r.categoryName} />
      <DetailField label="Office" value={r.officeName} />
    </>) },
  { id: 'maintenance', label: 'Maintenance', fetcher: getDeletedMaintenance, restoreFn: restoreDeletedMaintenance, permanentDeleteFn: permanentDeleteMaintenance,
    columns: maintenanceColumns, matches: maintenanceMatches, emptyMessage: 'No deleted maintenance records.', recordLabel: 'Maintenance record',
    searchHint: 'Search by property no., asset or who deleted it',
    details: (r) => (<>
      <DetailField label="PAR Number" value={r.parNumber} mono />
      <DetailField label="Type" value={MAINTENANCE_TYPE[r.maintenanceType]?.label || r.maintenanceType} />
      <DetailField label="Status" value={lower(r.status)} />
    </>) },
  { id: 'disposal', label: 'Disposal', fetcher: getDeletedDisposal, restoreFn: restoreDeletedDisposal, permanentDeleteFn: permanentDeleteDisposal,
    columns: disposalColumns, matches: disposalMatches, emptyMessage: 'No deleted disposal records.', recordLabel: 'Disposal record',
    searchHint: 'Search by property no., asset or who deleted it',
    details: (r) => (<>
      <DetailField label="PAR Number" value={r.parNumber} mono />
      <DetailField label="Method" value={DISPOSAL_METHOD[r.recommendedMethod]?.label || r.recommendedMethod} />
      <DetailField label="Status" value={lower(r.disposalStatus)} />
    </>) },
]

function DeletedRecords() {
  const [activeTab, setActiveTab] = useState('assets')
  const tab = TABS.find((t) => t.id === activeTab)

  return (
    <MainLayout>
      <div role="tablist" className="flex items-center gap-1 mb-4 overflow-x-auto overflow-y-hidden shadow-[inset_0_-1px_0_theme(colors.slate.200)] dark:shadow-[inset_0_-1px_0_theme(colors.zinc.800)]">
        {TABS.map((t) => (
          <button
            key={t.id}
            role="tab"
            aria-selected={activeTab === t.id}
            onClick={() => setActiveTab(t.id)}
            className={`px-4 py-2.5 text-sm font-medium transition-all border-b-2 whitespace-nowrap ${
              activeTab === t.id
                ? 'border-brand-600 text-brand-700 dark:text-brand-300'
                : 'border-transparent text-slate-600 dark:text-zinc-400 hover:text-slate-900 dark:hover:text-zinc-200'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <DeletedTab key={tab.id} {...tab} />
    </MainLayout>
  )
}

export default DeletedRecords
