import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useToast } from '../../context/ToastContext'
import { RejectRequestModal } from '../../components/common/ApprovalControls'
import {
  SearchBox, FilterSelect, FilterToggle, FilterBar, ListCard, RefreshButton, LazyFooter, useLazyRows,
  ListSkeleton, ListEmpty, DataTable, PrimaryCell, MutedCell, MappedBadge, ICON, fmtDate,
} from '../../components/common/ListKit'
import DetailModal, { DetailGrid, DetailSection, DetailField, ModalAction } from '../../components/common/DetailModal'
import { approveTransfer, rejectTransfer } from '../../services/transferService'

// The Requests tab of Transfer Asset: transfers filed by staff, laid out like the Maintenance and
// Disposal lists. Admins approve or reject them from the window a row opens; staff follow their own.

const STATUS = {
  PENDING_APPROVAL: { label: 'Awaiting approval', tone: 'amber' },
  APPROVED:         { label: 'Approved',          tone: 'green' },
  REJECTED:         { label: 'Rejected',          tone: 'red' },
}

const INPUT = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3.5 py-2.5 text-sm text-slate-800 dark:text-zinc-100 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

const route = (r) => `${r.fromOfficeName || 'Unassigned'} to ${r.toOfficeName}`
const changesEndUser = (r) => !!r.toPersonnelId && r.toPersonnelId !== r.currentPersonnelId
// a PAR No. starts with the asset's acquisition year-month (YYYY-MM:SERIAL)
const parPrefix = (acquisitionDate) => (acquisitionDate ? `${String(acquisitionDate).slice(0, 7)}:` : '')

const COLUMNS = [
  { key: 'asset', label: 'Asset', cell: (r, open) => (
    <PrimaryCell code={r.propertyNumber} title={r.assetDescription} open={open}
      extra={<div className="sm:hidden mt-1"><MappedBadge map={STATUS} value={r.status} /></div>} />
  ) },
  { key: 'route', label: 'Transfer', className: 'hidden md:table-cell w-[30%]', cell: (r) => (
    <MutedCell sub={r.toPersonnelName}>{route(r)}</MutedCell>
  ) },
  { key: 'status', label: 'Status', className: 'hidden sm:table-cell w-[10rem]', cell: (r) => <MappedBadge map={STATUS} value={r.status} /> },
  { key: 'by', label: 'Requested', className: 'hidden lg:table-cell w-[13rem]', cell: (r) => (
    <MutedCell sub={fmtDate(r.requestedAt)}>{r.requestedByName || 'Staff'}</MutedCell>
  ) },
]

function TransferRequests({ requests, loading, isAdmin, isAdminStaff, assetItems, onReload, onApproved }) {
  const { show }  = useToast()
  const navigate  = useNavigate()
  const lazy      = useLazyRows()
  const [search, setSearch]             = useState('')
  const [filterStatus, setFilterStatus] = useState('')
  // admins open on what needs them; everyone else on all their requests
  const [pendingOnly, setPendingOnly]   = useState(isAdmin)
  const [viewing, setViewing]           = useState(null)
  const [rejecting, setRejecting]       = useState(null)
  const [approving, setApproving]       = useState(false)
  const [newPar, setNewPar]             = useState('')

  useEffect(() => { lazy.reset() }, [search, filterStatus, pendingOnly]) // eslint-disable-line react-hooks/exhaustive-deps

  // keep the open window on the latest copy of its request
  useEffect(() => {
    setViewing((v) => (v ? requests.find((r) => r.id === v.id) || null : v))
  }, [requests])

  const open = (r) => {
    setViewing(r)
    setNewPar(changesEndUser(r) ? parPrefix(assetItems.find((a) => a.id === r.assetId)?.acquisitionDate) : '')
  }

  const pendingCount = requests.filter((r) => r.status === 'PENDING_APPROVAL').length

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return requests.filter((r) => {
      if (pendingOnly && r.status !== 'PENDING_APPROVAL') return false
      if (filterStatus && r.status !== filterStatus) return false
      if (q && ![r.propertyNumber, r.assetDescription, r.fromOfficeName, r.toOfficeName, r.toPersonnelName, r.requestedByName]
        .some((f) => f?.toLowerCase().includes(q))) return false
      return true
    })
  }, [requests, search, filterStatus, pendingOnly])

  const paged = filtered.slice(0, lazy.shown)
  const activeFilters = [search.trim(), filterStatus, pendingOnly].filter(Boolean).length
  const clearFilters = () => { setSearch(''); setFilterStatus(''); setPendingOnly(false) }

  const v = viewing
  const isPending = v?.status === 'PENDING_APPROVAL'
  const needsPar = !!v && changesEndUser(v)
  const parReady = !needsPar || (newPar.includes(':') && !newPar.trim().endsWith(':'))

  const approve = async () => {
    setApproving(true)
    try {
      const { data } = await approveTransfer(v.id, needsPar ? newPar.trim() : null)
      onApproved(data)
      show(`Approved: ${v.propertyNumber} moved to ${v.toOfficeName}.${needsPar ? ' Print its return slip and new PAR from the asset\'s details.' : ''}`, 'success')
      onReload()
    } catch (err) {
      show(err.response?.data?.message || 'Failed to approve the request.', 'error')
    } finally {
      setApproving(false)
    }
  }

  const reject = async (note) => {
    await rejectTransfer(rejecting.id, note)
    show(`Rejected the transfer of ${rejecting.propertyNumber}.`, 'warning')
    onReload()
  }

  const emptyText = requests.length > 0 ? 'No requests match your search or filters.'
    : isAdmin ? 'No transfer requests yet. Transfers filed by staff appear here for your approval.'
    : isAdminStaff ? 'No transfer requests yet.'
    : "You haven't sent any transfer requests. Transfers you file wait here for an administrator."

  return (
    <>
      <div className="flex flex-col gap-2.5 mb-4">
        <div className="flex items-stretch gap-2">
          <SearchBox value={search} onChange={setSearch} label="Search transfer requests"
            placeholder="Search by asset, property no., office or person" />
        </div>
        <FilterBar activeCount={activeFilters} onClear={clearFilters}>
          <FilterSelect label="Status" value={filterStatus} onChange={setFilterStatus} options={Object.entries(STATUS).map(([k, s]) => [k, s.label])} />
          <FilterToggle on={pendingOnly} onChange={setPendingOnly}>Awaiting approval{pendingCount > 0 ? ` (${pendingCount})` : ''}</FilterToggle>
        </FilterBar>
      </div>

      <ListCard title={activeFilters > 0 ? 'Matching requests' : isAdmin || isAdminStaff ? 'Transfer requests' : 'My transfer requests'}
        filtered={filtered.length !== requests.length} count={filtered.length} total={requests.length} noun="request" loading={loading}
        actions={<RefreshButton onClick={onReload} />}
        footer={!loading && <LazyFooter lazy={lazy} total={filtered.length} />}>
        {loading ? <ListSkeleton /> : filtered.length === 0 ? (
          <ListEmpty>{emptyText}</ListEmpty>
        ) : (
          <DataTable columns={COLUMNS} rows={paged} rowKey={(r) => r.id} onOpen={open} selectedKey={v?.id}
            caption="Transfer requests. Select a request to see its details." />
        )}
      </ListCard>

      {v && (
        <DetailModal
          title={v.assetDescription || 'Transfer request'}
          label={`Transfer request: ${v.propertyNumber || ''} ${v.assetDescription || ''}`}
          escDisabled={!!rejecting}
          onClose={() => setViewing(null)}
          subtitle={<>
            <span className="text-slate-600 dark:text-zinc-400">Property No.</span>
            <span className="font-mono font-semibold text-slate-900 dark:text-zinc-100">{v.propertyNumber || 'N/A'}</span>
            <span className="text-slate-300 dark:text-zinc-600" aria-hidden="true">·</span>
            <MappedBadge map={STATUS} value={v.status} />
          </>}
          footer={<>
            {isAdmin && isPending && <>
              <ModalAction label={approving ? 'Approving…' : needsPar ? 'Approve with this PAR' : 'Approve request'} icon={ICON.check} tone="primary"
                onClick={approve} disabled={approving || !parReady} />
              <ModalAction label="Reject" icon={ICON.x} tone="danger" onClick={() => setRejecting(v)} disabled={approving} />
            </>}
            {v.propertyNumber && (
              <ModalAction label="Open asset" onClick={() => navigate(`/assets?search=${encodeURIComponent(v.propertyNumber)}`)} />
            )}
          </>}
        >
          <DetailGrid>
            <DetailSection title="From">
              <DetailField label="Office" value={v.fromOfficeName || 'Unassigned'} />
              <DetailField label="Accountable" value={v.currentPersonnelName} />
            </DetailSection>
            <DetailSection title="To">
              <DetailField label="Office" value={v.toOfficeName} />
              <DetailField label="Location" value={v.toLocation && v.toLocation !== v.toOfficeName ? v.toLocation : null} />
              <DetailField label="Accountable" value={v.toPersonnelName} />
            </DetailSection>
            <DetailSection title="Request" wide>
              <DetailField label="Reason" value={v.reason} />
              <DetailField label="Requested by" value={`${v.requestedByName || 'Staff'} · ${fmtDate(v.requestedAt)}`} />
              {v.reviewedByName && (
                <DetailField label={v.status === 'REJECTED' ? 'Rejected by' : 'Approved by'} value={`${v.reviewedByName} · ${fmtDate(v.reviewedAt)}`} />
              )}
              {v.reviewNote && <DetailField label="Reason given" value={v.reviewNote} />}
            </DetailSection>
            {isAdmin && isPending && needsPar && (
              <DetailSection title="New PAR" wide>
                <div className="space-y-2">
                  <p className="text-sm text-slate-600 dark:text-zinc-300">
                    {v.currentPersonnelName ? `${v.currentPersonnelName} returns the asset on a Property Return Slip. ` : ''}
                    Enter the PAR No. for {v.toPersonnelName}.
                  </p>
                  <label htmlFor="approve-par" className="sr-only">New PAR No.</label>
                  <input id="approve-par" value={newPar} onChange={(e) => setNewPar(e.target.value)} maxLength={50}
                    placeholder="YYYY-MM:SERIAL" aria-describedby="approve-par-hint" className={`${INPUT} font-mono`} />
                  <p id="approve-par-hint" className="text-xs text-slate-500 dark:text-zinc-400">Format YYYY-MM:SERIAL, starting with the acquisition month.</p>
                </div>
              </DetailSection>
            )}
          </DetailGrid>
        </DetailModal>
      )}

      {rejecting && (
        <RejectRequestModal
          record={{ ...rejecting, kind: 'transfer' }}
          describe={(r) => `${r.propertyNumber || ''}: ${r.assetDescription || ''}`}
          onClose={() => setRejecting(null)}
          onConfirm={reject}
        />
      )}
    </>
  )
}

export default TransferRequests
