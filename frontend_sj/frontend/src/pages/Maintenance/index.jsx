import { useState, useEffect, useCallback, useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useSelector } from 'react-redux'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import { useEventStream } from '../../hooks/useEventStream'
import MainLayout from '../../components/layout/MainLayout'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import { RejectRequestModal, isApproved } from '../../components/common/ApprovalControls'
import {
  SearchBox, FilterSelect, FilterToggle, FilterBar, ScopeNotice, ListCard, RefreshButton, LazyFooter, useLazyRows,
  ListSkeleton, ListEmpty, DataTable, PrimaryCell, MutedCell, MappedBadge, ICON, fmtDate, fmtPeso, personName,
} from '../../components/common/ListKit'
import DetailModal, { DetailGrid, DetailSection, DetailField, ModalAction } from '../../components/common/DetailModal'
import AddMaintenanceModal from './AddMaintenanceModal'
import EvidenceModal from './EvidenceModal'
import { getMaintenance, updateMaintenance, deleteMaintenance, approveMaintenance, rejectMaintenance, getMaintenanceById, getMaintenanceByAsset } from '../../services/maintenanceService'
import { getAssets, getAssetById } from '../../services/assetService'
import MaintenanceLines from '../../components/common/MaintenanceLines'
import { printMaintenanceCard, openMaintenanceCardWindow } from '../../utils/maintenanceCardPrint'
import { getUsers } from '../../services/userService'
import DraftRows from '../../components/common/DraftRows'
import { useDraftList } from '../../hooks/useFormDraft'

const STATUS = {
  COMPLETED: { label: 'Completed', tone: 'green' },
  ONGOING:   { label: 'Ongoing',   tone: 'amber' },
  SCHEDULED: { label: 'Scheduled', tone: 'blue' },
}
const TYPE = {
  PREVENTIVE: { label: 'Preventive', tone: 'blue' },
  CORRECTIVE: { label: 'Corrective', tone: 'violet' },
  REPAIR:     { label: 'Repair',     tone: 'amber' },
}
// Only shown when a record is a staff request that isn't approved (yet).
const APPROVAL = {
  APPROVED:         null,
  PENDING_APPROVAL: { label: 'Awaiting approval', tone: 'amber' },
  REJECTED:         { label: 'Request rejected',  tone: 'red' },
}


// The table keeps what tells records apart; findings, actions taken, cost, the request trail
// and photos are in the window a row opens.
const COLUMNS = [
  { key: 'asset', label: 'Asset', cell: (r, open) => (
    <PrimaryCell code={r.asset?.propertyNumber} title={r.asset?.description} open={open}
      extra={<div className="sm:hidden mt-1 flex flex-wrap gap-1"><MappedBadge map={STATUS} value={r.status} /><MappedBadge map={APPROVAL} value={r.approvalStatus} /></div>} />
  ) },
  { key: 'type', label: 'Type', className: 'hidden md:table-cell w-[8.5rem]', cell: (r) => <MappedBadge map={TYPE} value={r.maintenanceType} /> },
  { key: 'status', label: 'Status', className: 'hidden sm:table-cell w-[11rem]', cell: (r) => (
    <div className="flex flex-col items-start gap-1"><MappedBadge map={STATUS} value={r.status} /><MappedBadge map={APPROVAL} value={r.approvalStatus} /></div>
  ) },
  { key: 'date', label: 'Date', className: 'hidden lg:table-cell w-[8.5rem]', cell: (r) => <MutedCell>{fmtDate(r.maintenanceDate)}</MutedCell> },
  { key: 'who', label: 'Assigned to', className: 'hidden xl:table-cell w-[18%]', cell: (r) => <MutedCell>{personName(r.assignedTo)}</MutedCell> },
]

function Maintenance() {
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
  const [filterType, setFilterType]     = useState('')
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

  const { drafts, discard: discardDraft } = useDraftList('maintenance')
  // Reopen the form a draft came from; it restores the draft itself.
  const continueDraft = async (d) => {
    const record = records.find((r) => String(r.id) === d.id) || (await getMaintenanceById(d.id).catch(() => null))?.data
    if (!record) { discardDraft(d.key); toast.show('That record no longer exists, so its draft was removed.', 'error'); return }
    setEditing(record)
  }
  // Draft rows use the table's columns: draft fields laid over the saved record.
  const draftRecord = (d) => {
    const base = records.find((r) => String(r.id) === d.id) || {}
    return { ...base, ...d.data, asset: base.asset }
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
      const { data } = await getMaintenance(q)
      setRecords(data)
    } catch {
      if (!silent) toast.show('Failed to load maintenance records.', 'error')
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
  useEffect(() => { lazy.reset() }, [debouncedSearch, filterStatus, filterType, assetFilter, pendingOnly])
  useEffect(() => { if (filterType) setMoreFilters(true) }, [filterType])

  const upsert = (data) => {
    setRecords((prev) => prev.map((r) => (r.id === data.id ? data : r)))
    setViewing((v) => (v?.id === data.id ? data : v))
  }

  useEventStream('maintenance', ({ action, id, data }) => {
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
    const { data } = await updateMaintenance(editing.id, payload)
    upsert(data)
    setEditing(null)
    toast.show('Record updated.', 'success')
  }

  const handleDelete = async () => {
    try {
      await deleteMaintenance(deleting.id)
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

  const filtered = useMemo(() => records.filter((r) => {
    if (pendingOnly && r.approvalStatus !== 'PENDING_APPROVAL') return false
    if (filterStatus && r.status !== filterStatus) return false
    if (filterType && r.maintenanceType !== filterType) return false
    if (assetFilter && String(r.asset?.id) !== assetFilter) return false
    return true
  }), [records, pendingOnly, filterStatus, filterType, assetFilter])

  const paged = filtered.slice(0, lazy.shown)
  const activeFilters = [search.trim(), filterStatus, filterType, pendingOnly].filter(Boolean).length
  const clearFilters = () => { setSearch(''); setFilterStatus(''); setFilterType(''); setPendingOnly(false) }

  const v = viewing
  const canEdit = v && (isAdmin || isApproved(v))
  const isPending = v?.approvalStatus === 'PENDING_APPROVAL'

  return (
    <MainLayout>
      {assetFilter && (
        <ScopeNotice onClear={() => setAssetFilter('')}>Showing the maintenance records of one asset.</ScopeNotice>
      )}

      <div className="flex flex-col gap-2.5 mb-4">
        <div className="flex items-stretch gap-2">
          <SearchBox value={search} onChange={setSearch} label="Search maintenance records"
            placeholder="Search by asset, property no. or findings" />
        </div>
        <FilterBar activeCount={activeFilters} onClear={clearFilters} moreOpen={moreFilters} onMoreToggle={setMoreFilters}
          more={<FilterSelect label="Type" value={filterType} onChange={setFilterType} options={Object.entries(TYPE).map(([k, t]) => [k, t.label])} />}>
          <FilterSelect label="Status" value={filterStatus} onChange={setFilterStatus} options={Object.entries(STATUS).map(([k, s]) => [k, s.label])} />
          {(isAdmin || pendingCount > 0) && (
            <FilterToggle on={pendingOnly} onChange={setPendingOnly}>Awaiting approval{pendingCount > 0 ? ` (${pendingCount})` : ''}</FilterToggle>
          )}
        </FilterBar>
      </div>

      <ListCard title={activeFilters > 0 || assetFilter ? 'Matching records' : 'Maintenance records'} filtered={filtered.length !== records.length}
        count={filtered.length} total={records.length} loading={loading}
        actions={<RefreshButton onClick={() => fetchRecords(search)} />}
        footer={!loading && <LazyFooter lazy={lazy} total={filtered.length} />}>
        {loading ? <ListSkeleton /> : filtered.length === 0 && drafts.length === 0 ? (
          <ListEmpty>{records.length === 0 ? 'No maintenance records yet.' : 'No records match your search or filters.'}</ListEmpty>
        ) : (
          <DataTable columns={COLUMNS} rows={paged} rowKey={(r) => r.id} onOpen={setViewing} selectedKey={v?.id}
            caption="Maintenance records. Select a record to see its details." wideEnd={drafts.length > 0}
            leading={<DraftRows drafts={drafts} columns={draftColumns} toRecord={draftRecord} onContinue={continueDraft} onDiscard={discardDraft} />} />
        )}
      </ListCard>

      {v && (
        <DetailModal
          title={v.asset?.description || 'Maintenance record'}
          label={`Maintenance record: ${v.asset?.propertyNumber || ''} ${v.asset?.description || ''}`}
          escDisabled={!!(viewingEvidence || deleting || rejecting || editing)}
          onClose={() => setViewing(null)}
          subtitle={<>
            <span className="text-slate-600 dark:text-zinc-400">Property No.</span>
            <span className="font-mono font-semibold text-slate-900 dark:text-zinc-100">{v.asset?.propertyNumber || 'N/A'}</span>
            <span className="text-slate-300 dark:text-zinc-600" aria-hidden="true">·</span>
            <MappedBadge map={TYPE} value={v.maintenanceType} />
            <MappedBadge map={STATUS} value={v.status} />
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
            {v.asset?.id && (
              <ModalAction label="Print maintenance card" onClick={() => {
                // the window opens on the click; the asset and all its records are loaded after
                const win = openMaintenanceCardWindow()
                Promise.all([getAssetById(v.asset.id), getMaintenanceByAsset(v.asset.id)])
                  .then(([a, m]) => printMaintenanceCard(a.data, m.data, win))
                  .catch(() => { win.close(); toast.show('Could not load the maintenance card.', 'error') })
              }} />
            )}
            {v.asset?.propertyNumber && (
              <ModalAction label="Open asset" onClick={() => navigate(`/assets?search=${encodeURIComponent(v.asset.propertyNumber)}`)} />
            )}
            {isAdmin && <span className="sm:ml-auto"><ModalAction label="Delete record" icon={ICON.trash} tone="danger" onClick={() => setDeleting(v)} /></span>}
          </>}
        >
          <DetailGrid>
            <DetailSection title="Maintenance">
              <DetailField label="Date" value={fmtDate(v.maintenanceDate)} />
              <DetailField label="Assigned to" value={personName(v.assignedTo)} />
              <DetailField label="Cost" value={fmtPeso(v.cost)} />
              <DetailField label="Recorded" value={`${fmtDate(v.createdAt)} · updated ${fmtDate(v.updatedAt)}`} />
            </DetailSection>
            <DetailSection title="Asset">
              <DetailField label="PAR Number" value={v.asset?.parNumber} mono />
              <DetailField label="Office" value={v.asset?.office?.officeName} />
              <DetailField label="Accountable" value={v.asset?.accountablePerson?.fullName} />
            </DetailSection>
            <DetailSection title="Findings & actions" wide>
              <DetailField label="Findings" value={v.findings} />
              <DetailField label="Particular (work done)" value={v.actionsTaken} />
            </DetailSection>
            {v.items?.length > 0 && (
              <DetailSection title="Parts and labor" wide>
                <MaintenanceLines items={v.items} cost={v.cost} />
              </DetailSection>
            )}
            {(v.requestedByName || v.reviewNote || v.approvalStatus !== 'APPROVED') && (
              <DetailSection title="Request" wide>
                <DetailField label="Requested by" value={v.requestedByName} />
                <DetailField label="Approval" value={APPROVAL[v.approvalStatus]?.label || 'Approved'} />
                {v.reviewNote && <DetailField label="Reason given" value={v.reviewNote} />}
              </DetailSection>
            )}
          </DetailGrid>
        </DetailModal>
      )}

      {editing  && <AddMaintenanceModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} assets={assets} users={users} />}
      {viewingEvidence && <EvidenceModal record={viewingEvidence} onClose={() => setViewingEvidence(null)} />}
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
          title="Delete this maintenance record?"
          message="It moves to Recovery, where an administrator can restore it."
          confirmLabel="Delete"
          onConfirm={handleDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
    </MainLayout>
  )
}

export default Maintenance
