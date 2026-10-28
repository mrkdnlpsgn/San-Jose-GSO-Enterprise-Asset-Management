import { useState, useEffect, useCallback, useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useSelector } from 'react-redux'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import { useEventStream } from '../../hooks/useEventStream'
import MainLayout from '../../components/layout/MainLayout'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import EvidenceModal from '../../components/common/EvidenceModal'
import { RejectRequestModal, isApproved } from '../../components/common/ApprovalControls'
import {
  SearchBox, FilterSelect, FilterToggle, FilterBar, ScopeNotice, ListCard, RefreshButton, LazyFooter, useLazyRows,
  ListSkeleton, ListEmpty, DataTable, PrimaryCell, MutedCell, MappedBadge, ICON, fmtDate, fmtPeso, personName,
} from '../../components/common/ListKit'
import DetailModal, { DetailGrid, DetailSection, DetailField, ModalAction } from '../../components/common/DetailModal'
import AddDisposalModal from './AddDisposalModal'
import { getDisposal, updateDisposal, deleteDisposal, approveDisposal, rejectDisposal, getDisposalById } from '../../services/disposalService'
import { getAssets } from '../../services/assetService'
import { getUsers } from '../../services/userService'
import DraftRows from '../../components/common/DraftRows'
import { useDraftList } from '../../hooks/useFormDraft'

const STATUS = {
  PENDING:   { label: 'Pending',   tone: 'amber' },
  APPROVED:  { label: 'Approved',  tone: 'blue' },
  COMPLETED: { label: 'Completed', tone: 'green' },
}
const METHOD = {
  SALE:        { label: 'Sale',        tone: 'blue' },
  TRANSFER:    { label: 'Transfer',    tone: 'violet' },
  DESTRUCTION: { label: 'Destruction', tone: 'red' },
  OTHERS:      { label: 'Others',      tone: 'slate' },
}
// Only shown when a record is a staff request that isn't approved (yet).
const APPROVAL = {
  APPROVED:         null,
  PENDING_APPROVAL: { label: 'Awaiting approval', tone: 'amber' },
  REJECTED:         { label: 'Request rejected',  tone: 'red' },
}


// The table keeps what tells records apart; the reason, findings, appraisal and sale details,
// the request trail and photos are in the window a row opens.
const COLUMNS = [
  { key: 'asset', label: 'Asset', cell: (r, open) => (
    <PrimaryCell code={r.asset?.propertyNumber} title={r.asset?.description} open={open}
      extra={<div className="sm:hidden mt-1 flex flex-wrap gap-1"><MappedBadge map={STATUS} value={r.disposalStatus} /><MappedBadge map={APPROVAL} value={r.approvalStatus} /></div>} />
  ) },
  { key: 'method', label: 'Method', className: 'hidden md:table-cell w-[8.5rem]', cell: (r) => <MappedBadge map={METHOD} value={r.recommendedMethod} /> },
  { key: 'status', label: 'Status', className: 'hidden sm:table-cell w-[11rem]', cell: (r) => (
    <div className="flex flex-col items-start gap-1"><MappedBadge map={STATUS} value={r.disposalStatus} /><MappedBadge map={APPROVAL} value={r.approvalStatus} /></div>
  ) },
  { key: 'date', label: 'Inspected', className: 'hidden lg:table-cell w-[8.5rem]', cell: (r) => <MutedCell>{fmtDate(r.inspectionDate)}</MutedCell> },
  { key: 'who', label: 'Recorded by', className: 'hidden xl:table-cell w-[18%]', cell: (r) => <MutedCell>{personName(r.recordedBy)}</MutedCell> },
]

function Disposal() {
  const toast    = useToast()
  const location = useLocation()
  const navigate = useNavigate()
  const isAdmin  = useSelector((s) => s.auth.user?.role === 'ADMIN')

  const [records, setRecords]   = useState([])
  const [loading, setLoading]   = useState(true)
  const [assets, setAssets]     = useState([])
  const [users, setUsers]       = useState([])
  const [search, setSearch]     = useState('')
  const [filterStatus, setFilterStatus] = useState('')
  const [filterMethod, setFilterMethod] = useState('')
  const [assetFilter, setAssetFilter]   = useState('')
  // ?pending=1 (e.g. from the dashboard's Pending Approvals) opens with only requests awaiting approval
  const [pendingOnly, setPendingOnly] = useState(() => new URLSearchParams(window.location.search).get('pending') === '1')
  const [moreFilters, setMoreFilters] = useState(false)
  const lazy = useLazyRows()
  const [viewing, setViewing]   = useState(null)   // record whose details window is open
  const [editing, setEditing]   = useState(null)
  const [deleting, setDeleting] = useState(null)
  const [rejecting, setRejecting] = useState(null)
  const [viewingEvidence, setViewingEvidence] = useState(null)

  const { drafts, discard: discardDraft } = useDraftList('disposal')
  // Reopen the form a draft came from; it restores the draft itself.
  const continueDraft = async (d) => {
    const record = records.find((r) => String(r.id) === d.id) || (await getDisposalById(d.id).catch(() => null))?.data
    if (!record) { discardDraft(d.key); toast.show('That record no longer exists, so its draft was removed.', 'error'); return }
    setEditing(record)
  }
  // Draft rows use the table's columns: draft fields laid over the saved record.
  const draftRecord = (d) => {
    const base = records.find((r) => String(r.id) === d.id) || {}
    return { ...base, ...d.data, asset: base.asset, recordedBy: base.recordedBy }
  }
  const draftColumns = COLUMNS.map((c) => ({ className: `px-4 py-3 align-top ${c.className || ''}`, render: (r) => c.cell(r) }))

  const debouncedSearch = useDebounce(search, 300)

  // Pre-filter by assetId URL param
  useEffect(() => {
    const assetId = new URLSearchParams(location.search).get('assetId')
    if (assetId) setAssetFilter(assetId)
  }, [location.search])

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

  // The full asset list (about 2 MB) and the users are only needed by the edit form, so they
  // load the first time it opens instead of every time this page does.
  const [formListsLoaded, setFormListsLoaded] = useState(false)
  useEffect(() => {
    if (!editing || formListsLoaded) return
    setFormListsLoaded(true)
    Promise.all([getAssets('', { summary: true }).catch(() => ({ data: [] })), getUsers().catch(() => ({ data: [] }))])
      .then(([assetRes, userRes]) => { setAssets(assetRes.data); setUsers(userRes.data) })
  }, [editing, formListsLoaded])

  useEffect(() => { fetchRecords(debouncedSearch) }, [debouncedSearch, fetchRecords])
  useEffect(() => { lazy.reset() }, [debouncedSearch, filterStatus, filterMethod, assetFilter, pendingOnly])
  useEffect(() => { if (filterMethod) setMoreFilters(true) }, [filterMethod])

  const upsert = (data) => {
    setRecords((prev) => prev.map((r) => (r.id === data.id ? data : r)))
    setViewing((v) => (v?.id === data.id ? data : v))
  }

  useEventStream('disposal', ({ action, id, data }) => {
    if (action === 'DELETED') {
      setRecords((prev) => prev.filter((r) => r.id !== id))
      setViewing((v) => (v?.id === id ? null : v))
      return
    }
    if (!data) { fetchRecords(search, { silent: true }); return }
    setRecords((prev) => (prev.some((r) => r.id === data.id) ? prev.map((r) => (r.id === data.id ? data : r)) : [data, ...prev]))
    setViewing((v) => (v?.id === data.id ? data : v))
  })

  const handleUpdate = async (payload) => {
    const { data } = await updateDisposal(editing.id, payload)
    upsert(data)
    setEditing(null)
    toast.show('Record updated.', 'success')
  }

  const handleDelete = async () => {
    try {
      await deleteDisposal(deleting.id)
      setRecords((prev) => prev.filter((r) => r.id !== deleting.id))
      setViewing(null)
      toast.show('Record deleted.', 'warning')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to delete.', 'error')
    } finally {
      setDeleting(null)
    }
  }

  const handleApprove = async (rec) => {
    try {
      const { data } = await approveDisposal(rec.id)
      upsert(data)
      toast.show('Request approved.', 'success')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to approve the request.', 'error')
    }
  }

  const handleReject = async (note) => {
    const { data } = await rejectDisposal(rejecting.id, note)
    upsert(data)
    toast.show('Request rejected.', 'warning')
  }

  const pendingCount = records.filter((r) => r.approvalStatus === 'PENDING_APPROVAL').length

  const filtered = useMemo(() => records.filter((r) => {
    if (pendingOnly && r.approvalStatus !== 'PENDING_APPROVAL') return false
    if (filterStatus && r.disposalStatus !== filterStatus) return false
    if (filterMethod && r.recommendedMethod !== filterMethod) return false
    if (assetFilter && String(r.asset?.id) !== assetFilter) return false
    return true
  }), [records, pendingOnly, filterStatus, filterMethod, assetFilter])

  const paged = filtered.slice(0, lazy.shown)
  const activeFilters = [search.trim(), filterStatus, filterMethod, pendingOnly].filter(Boolean).length
  const clearFilters = () => { setSearch(''); setFilterStatus(''); setFilterMethod(''); setPendingOnly(false) }

  const v = viewing
  const canEdit = v && (isAdmin || isApproved(v))
  const isPending = v?.approvalStatus === 'PENDING_APPROVAL'

  return (
    <MainLayout>
      {assetFilter && (
        <ScopeNotice onClear={() => setAssetFilter('')}>Showing the disposal records of one asset.</ScopeNotice>
      )}

      <div className="flex flex-col gap-2.5 mb-4">
        <div className="flex items-stretch gap-2">
          <SearchBox value={search} onChange={setSearch} label="Search disposal records"
            placeholder="Search by asset, property no. or reason" />
        </div>
        <FilterBar activeCount={activeFilters} onClear={clearFilters} moreOpen={moreFilters} onMoreToggle={setMoreFilters}
          more={<FilterSelect label="Method" value={filterMethod} onChange={setFilterMethod} options={Object.entries(METHOD).map(([k, m]) => [k, m.label])} />}>
          <FilterSelect label="Status" value={filterStatus} onChange={setFilterStatus} options={Object.entries(STATUS).map(([k, s]) => [k, s.label])} />
          {(isAdmin || pendingCount > 0) && (
            <FilterToggle on={pendingOnly} onChange={setPendingOnly}>Awaiting approval{pendingCount > 0 ? ` (${pendingCount})` : ''}</FilterToggle>
          )}
        </FilterBar>
      </div>

      <ListCard title={activeFilters > 0 || assetFilter ? 'Matching records' : 'Disposal records'} filtered={filtered.length !== records.length}
        count={filtered.length} total={records.length} loading={loading}
        actions={<RefreshButton onClick={() => fetchRecords(search)} />}
        footer={!loading && <LazyFooter lazy={lazy} total={filtered.length} />}>
        {loading ? <ListSkeleton /> : filtered.length === 0 && drafts.length === 0 ? (
          <ListEmpty>{records.length === 0 ? 'No disposal records yet.' : 'No records match your search or filters.'}</ListEmpty>
        ) : (
          <DataTable columns={COLUMNS} rows={paged} rowKey={(r) => r.id} onOpen={setViewing} selectedKey={v?.id}
            caption="Disposal records. Select a record to see its details." wideEnd={drafts.length > 0}
            leading={<DraftRows drafts={drafts} columns={draftColumns} toRecord={draftRecord} onContinue={continueDraft} onDiscard={discardDraft} />} />
        )}
      </ListCard>

      {v && (
        <DetailModal
          title={v.asset?.description || 'Disposal record'}
          label={`Disposal record: ${v.asset?.propertyNumber || ''} ${v.asset?.description || ''}`}
          escDisabled={!!(viewingEvidence || deleting || rejecting || editing)}
          onClose={() => setViewing(null)}
          subtitle={<>
            <span className="text-slate-600 dark:text-zinc-400">Property No.</span>
            <span className="font-mono font-semibold text-slate-900 dark:text-zinc-100">{v.asset?.propertyNumber || 'N/A'}</span>
            <span className="text-slate-300 dark:text-zinc-600" aria-hidden="true">·</span>
            <MappedBadge map={METHOD} value={v.recommendedMethod} />
            <MappedBadge map={STATUS} value={v.disposalStatus} />
            <MappedBadge map={APPROVAL} value={v.approvalStatus} />
          </>}
          actions={[
            ...(canEdit ? [{ label: 'Edit', icon: ICON.edit, onClick: () => setEditing(v) }] : []),
            { label: 'Photos', icon: ICON.camera, onClick: () => setViewingEvidence(v) },
          ]}
          footer={<>
            {isAdmin && isPending && <>
              <ModalAction label="Approve request" icon={ICON.check} tone="primary" onClick={() => handleApprove(v)} />
              <ModalAction label="Reject" icon={ICON.x} tone="danger" onClick={() => setRejecting(v)} />
            </>}
            {v.asset?.propertyNumber && (
              <ModalAction label="Open asset" onClick={() => navigate(`/assets?search=${encodeURIComponent(v.asset.propertyNumber)}`)} />
            )}
            {isAdmin && <span className="sm:ml-auto"><ModalAction label="Delete record" icon={ICON.trash} tone="danger" onClick={() => setDeleting(v)} /></span>}
          </>}
        >
          <DetailGrid>
            <DetailSection title="Disposal">
              <DetailField label="Inspection date" value={fmtDate(v.inspectionDate)} />
              <DetailField label="Approved by" value={personName(v.approvedBy)} />
              <DetailField label="Recorded by" value={personName(v.recordedBy)} />
              <DetailField label="Recorded" value={`${fmtDate(v.createdAt)} · updated ${fmtDate(v.updatedAt)}`} />
            </DetailSection>
            <DetailSection title="Value">
              <DetailField label="Appraised value" value={fmtPeso(v.appraisedValue)} />
              <DetailField label="Amount received" value={fmtPeso(v.amount)} />
              <DetailField label="O.R. Number" value={v.orNumber} mono />
            </DetailSection>
            <DetailSection title="Reason & findings" wide>
              <DetailField label="Reason" value={v.reason} />
              <DetailField label="Inspection findings" value={v.inspectionFindings} />
            </DetailSection>
            <DetailSection title="Asset">
              <DetailField label="PAR Number" value={v.asset?.parNumber} mono />
              <DetailField label="Office" value={v.asset?.office?.officeName} />
            </DetailSection>
            {(v.requestedByName || v.reviewNote || v.approvalStatus !== 'APPROVED') && (
              <DetailSection title="Request">
                <DetailField label="Requested by" value={v.requestedByName} />
                <DetailField label="Approval" value={APPROVAL[v.approvalStatus]?.label || 'Approved'} />
                {v.reviewNote && <DetailField label="Reason given" value={v.reviewNote} />}
              </DetailSection>
            )}
          </DetailGrid>
        </DetailModal>
      )}

      {viewingEvidence && (
        <EvidenceModal
          path={`/disposal/${viewingEvidence.id}/evidence`}
          title="Disposal Evidence"
          subtitle={`${viewingEvidence.asset?.propertyNumber || ''}: ${viewingEvidence.asset?.description || ''}`}
          onClose={() => setViewingEvidence(null)}
        />
      )}
      {editing  && <AddDisposalModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} assets={assets} users={users} />}
      {rejecting && (
        <RejectRequestModal
          record={rejecting}
          describe={(r) => `${r.asset?.propertyNumber || ''}: ${r.asset?.description || ''}`}
          onClose={() => setRejecting(null)}
          onConfirm={handleReject}
        />
      )}
      {deleting && (
        <ConfirmDialog
          title="Delete this disposal record?"
          message="It moves to Recovery, where an administrator can restore it."
          confirmLabel="Delete"
          onConfirm={handleDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
    </MainLayout>
  )
}

export default Disposal
