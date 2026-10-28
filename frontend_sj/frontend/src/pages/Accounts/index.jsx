import { useState, useEffect, useCallback, useMemo } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useSelector } from 'react-redux'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import { usePolling } from '../../hooks/usePolling'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import UserModal from './UserModal'
import DeactivateAccountModal from './DeactivateAccountModal'
import ResetPasswordModal from './ResetPasswordModal'
import { getUsers, createUser, updateUser, deactivateUser, resetPassword } from '../../services/userService'
import MyAccountTab from './MyAccountTab'
import { ROLE_OPTIONS, roleLabel } from '../../utils/roles'
import { getAuditLogs, getAuditArchiveSummary, runAuditArchive, exportAuditArchive } from '../../services/auditLogService'
import DraftRows from '../../components/common/DraftRows'
import { useDraftList } from '../../hooks/useFormDraft'
import {
  SearchBox, FilterSelect, FilterBar, ListCard, RefreshButton, Pager, ListSkeleton, ListEmpty,
  DataTable, PrimaryCell, MutedCell, MappedBadge, StatusBadge, ICON,
} from '../../components/common/ListKit'
import DetailModal, { DetailGrid, DetailSection, DetailField, ModalAction } from '../../components/common/DetailModal'

// ── Helpers ───────────────────────────────────────────────────────────────────
function formatDateTime(dt) {
  if (!dt) return 'N/A'
  return new Date(dt).toLocaleString('en-PH', {
    year: 'numeric', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  })
}

// Audit entries store an action like ASSET_UPDATED and a module like "Assets". The Action
// filter groups actions by what happened (the verb at the end); the badge shows the action
// itself in words ("Asset updated").
const ACTION_KIND = {
  ADDED:   { label: 'Added',                tone: 'green' },
  CHANGED: { label: 'Changed',              tone: 'blue' },
  REMOVED: { label: 'Removed',              tone: 'red' },
  REVIEW:  { label: 'Requests & approvals', tone: 'amber' },
  OTHER:   { label: 'Other',                tone: 'slate' },
}
function actionKind(action = '') {
  if (/(CREATED|ADDED|ENABLED)$/.test(action)) return 'ADDED'
  if (/(UPDATED|CHANGED|TRANSFERRED)$/.test(action)) return 'CHANGED'
  if (/(DELETED|REMOVED|DEACTIVATED|DISABLED)$/.test(action)) return 'REMOVED'
  if (/(REQUESTED|APPROVED|REJECTED)$/.test(action)) return 'REVIEW'
  return 'OTHER'
}
const actionText = (action = '') => {
  const t = action.replace(/_/g, ' ').toLowerCase().replace(/2fa/, '2-step sign-in').replace(/ai/, 'AI')
  return t.charAt(0).toUpperCase() + t.slice(1)
}
const ActionBadge = ({ action }) => <StatusBadge tone={ACTION_KIND[actionKind(action)].tone}>{actionText(action)}</StatusBadge>
const MODULE = {
  Assets:       { label: 'Assets',        tone: 'green' },
  Maintenance:  { label: 'Maintenance',   tone: 'amber' },
  Disposal:     { label: 'Disposal',      tone: 'red' },
  AssetHistory: { label: 'Asset history', tone: 'violet' },
  Users:        { label: 'Accounts',      tone: 'slate' },
  Personnel:    { label: 'Personnel',     tone: 'slate' },
  Offices:      { label: 'Offices',       tone: 'blue' },
  Categories:   { label: 'Categories',    tone: 'blue' },
}
const AUDIT_PAGE_SIZE = 5
const ACCOUNTS_PAGE_SIZE = 5

const roleBadge = (u) => <StatusBadge tone={u.role === 'ADMIN' ? 'green' : u.role === 'ADMIN_STAFF' ? 'blue' : 'slate'}>{roleLabel(u.role)}</StatusBadge>
const NO_OFFICE = <span className="italic text-amber-800 dark:text-amber-300">Not assigned</span>

// The account list keeps who it is, where they work and whether they can sign in; email,
// 2-step status and the actions (edit, reset password, deactivate) are in the window a row opens.
const ACCOUNT_COLUMNS = [
  { key: 'name', label: 'Account', cell: (u, open) => (
    <PrimaryCell code={u.username ? `@${u.username}` : ''} title={u.fullName || u.username} open={open}
      extra={<div className="md:hidden mt-1 flex flex-wrap gap-1">{roleBadge(u)}{u.isActive === false && <StatusBadge tone="red">Inactive</StatusBadge>}</div>} />
  ) },
  { key: 'office', label: 'Office', className: 'hidden sm:table-cell w-[28%]', cell: (u) => (u.officeName ? <MutedCell>{u.officeName}</MutedCell> : <p className="text-sm">{NO_OFFICE}</p>) },
  { key: 'role', label: 'Role & status', className: 'hidden md:table-cell w-[13rem]', cell: (u) => (
    <div className="flex flex-wrap gap-1">{roleBadge(u)}{u.isActive === false ? <StatusBadge tone="red">Inactive</StatusBadge> : <StatusBadge tone="green">Active</StatusBadge>}</div>
  ) },
  { key: 'email', label: 'Email', className: 'hidden xl:table-cell w-[22%]', cell: (u) => (u.email ? <MutedCell>{u.email}</MutedCell> : <p className="text-sm italic text-amber-800 dark:text-amber-300">No email</p>) },
]

// ── Accounts tab ──────────────────────────────────────────────────────────────
function AccountsTab() {
  const toast = useToast()
  const me    = useSelector((s) => s.auth.user?.username)
  const [users, setUsers]           = useState([])
  const [loading, setLoading]       = useState(true)
  const [showCreate, setShowCreate] = useState(false)
  const [editing, setEditing]       = useState(null)
  const { drafts, discard: discardDraft } = useDraftList('account')
  // Reopen the form a draft came from; it restores the draft itself.
  const continueDraft = async (d) => {
    if (d.id === 'new') { setShowCreate(true); return }
    const record = users.find((r) => String(r.id) === d.id)
    if (!record) { discardDraft(d.key); toast.show('That record no longer exists, so its draft was removed.', 'error'); return }
    setEditing(record)
  }

  // Draft rows use the table's columns: draft fields laid over the saved account (if editing).
  const draftRecord = (d) => {
    const base = d.id === 'new' ? {} : users.find((u) => String(u.id) === d.id) || {}
    return { ...base, ...d.data }
  }
  const draftColumns = ACCOUNT_COLUMNS.map((c) => ({ className: `px-4 py-3 align-top ${c.className || ''}`, render: (u) => c.cell(u) }))
  const [deleting, setDeleting]     = useState(null)
  const [resetting, setResetting]   = useState(null)
  const [search, setSearch]         = useState('')
  const [viewing, setViewing]       = useState(null)
  const [filterRole, setFilterRole] = useState('')
  const [filterActive, setFilterActive] = useState('')
  const [page, setPage]             = useState(1)

  const debouncedSearch = useDebounce(search, 300)

  const fetchUsers = useCallback(async (q = '') => {
    try {
      const { data } = await getUsers(q)
      setUsers(data)
    } catch {
      toast.show('Failed to load accounts.', 'error')
    } finally {
      setLoading(false)
    }
  }, [toast])

  useEffect(() => { fetchUsers(debouncedSearch) }, [debouncedSearch, fetchUsers])

  const handleCreate = async (form, idempotencyKey) => {
    const { data } = await createUser(form, idempotencyKey)
    setUsers((prev) => [...prev, data])
    const message = form.generatePassword
      ? `Account for ${data.fullName || data.username} created. Credentials emailed to ${data.email}.`
      : `Account for ${data.fullName || data.username} created.`
    toast.show(message, 'success')
  }

  const handleUpdate = async (form) => {
    const { data } = await updateUser(editing.id, form)
    setUsers((prev) => prev.map((u) => (u.id === data.id ? data : u)))
    setViewing((v) => (v?.id === data.id ? data : v))
    toast.show('Account updated.', 'success')
  }

  // Errors are shown inside DeactivateAccountModal, so they're rethrown from here.
  const handleDeactivate = async (transferToUserId) => {
    await deactivateUser(deleting.id, transferToUserId ? { transferToUserId } : undefined)
    const name = deleting.fullName || deleting.username
    await fetchUsers(debouncedSearch) // status and asset counts changed
    setViewing(null)
    if (transferToUserId) {
      const to = users.find((u) => u.id === transferToUserId)
      toast.show(`"${name}" deactivated. Assets transferred to ${to?.fullName || to?.username || 'the selected account'}.`, 'warning')
    } else {
      toast.show(`"${name}" deactivated.`, 'warning')
    }
  }

  const handleResetPassword = async (newPassword) => {
    await resetPassword(resetting.id, { newPassword })
    toast.show(`Password reset for "${resetting.fullName || resetting.username}".`, 'success')
  }

  useEffect(() => { setPage(1) }, [debouncedSearch, filterRole, filterActive])
  const filtered = useMemo(() => users.filter((u) => {
    if (filterRole && u.role !== filterRole) return false
    if (filterActive === 'ACTIVE' && u.isActive === false) return false
    if (filterActive === 'INACTIVE' && u.isActive !== false) return false
    return true
  }), [users, filterRole, filterActive])
  const paged = filtered.slice((page - 1) * ACCOUNTS_PAGE_SIZE, page * ACCOUNTS_PAGE_SIZE)
  const activeFilters = [search.trim(), filterRole, filterActive].filter(Boolean).length
  const v = viewing

  return (
    <>
      <div className="flex flex-col gap-2.5 mb-4">
        <div className="flex items-stretch gap-2">
          <SearchBox value={search} onChange={setSearch} label="Search accounts" placeholder="Search by name, username, email or office" />
          <Button size="md" className="whitespace-nowrap flex-shrink-0" onClick={() => setShowCreate(true)}>
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 sm:mr-1.5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">{ICON.plus}</svg>
            <span className="sr-only sm:not-sr-only">Add Account</span>
          </Button>
        </div>
        <FilterBar activeCount={activeFilters} onClear={() => { setSearch(''); setFilterRole(''); setFilterActive('') }}>
          <FilterSelect label="Role" value={filterRole} onChange={setFilterRole} options={ROLE_OPTIONS.map((r) => [r.value, r.label])} />
          <FilterSelect label="Status" value={filterActive} onChange={setFilterActive} options={[['ACTIVE', 'Active'], ['INACTIVE', 'Inactive']]} />
        </FilterBar>
      </div>

      <ListCard title={activeFilters > 0 ? 'Matching accounts' : 'All accounts'} filtered={filtered.length !== users.length}
        count={filtered.length} total={users.length} noun="account" loading={loading}
        actions={<RefreshButton onClick={() => fetchUsers(debouncedSearch)} />}
        footer={!loading && <Pager page={page} pageSize={ACCOUNTS_PAGE_SIZE} total={filtered.length} onPage={setPage} />}>
        {loading ? <ListSkeleton rows={4} /> : filtered.length === 0 && drafts.length === 0 ? (
          <ListEmpty>{users.length === 0 ? 'No accounts yet. Add one with the button above.' : 'No accounts match your search or filters.'}</ListEmpty>
        ) : (
          <DataTable columns={ACCOUNT_COLUMNS} rows={paged} rowKey={(u) => u.id} onOpen={setViewing} selectedKey={v?.id} wideEnd={drafts.length > 0}
            caption="Accounts. Select an account to see its details."
            leading={<DraftRows drafts={drafts} columns={draftColumns} toRecord={draftRecord} onContinue={continueDraft} onDiscard={discardDraft} />} />
        )}
      </ListCard>

      {v && (
        <DetailModal
          title={v.fullName || v.username}
          escDisabled={!!(editing || resetting || deleting)}
          onClose={() => setViewing(null)}
          subtitle={<>
            <span className="font-mono font-semibold text-slate-900 dark:text-zinc-100">@{v.username}</span>
            <span className="text-slate-300 dark:text-zinc-600" aria-hidden="true">·</span>
            {roleBadge(v)}
            {v.isActive === false ? <StatusBadge tone="red">Inactive</StatusBadge> : <StatusBadge tone="green">Active</StatusBadge>}
            {v.twoFactorEnabled && <TwoStepChip />}
          </>}
          actions={[
            { label: 'Edit', icon: ICON.edit, onClick: () => setEditing(v) },
            { label: 'Reset password', onClick: () => setResetting(v) },
          ]}
          footer={v.isActive && v.username !== me && (
            <span className="sm:ml-auto"><ModalAction label="Deactivate account" tone="danger" onClick={() => setDeleting(v)} /></span>
          )}
        >
          <DetailGrid>
            <DetailSection title="Account">
              <DetailField label="Full name" value={v.fullName} />
              <DetailField label="Username" value={`@${v.username}`} mono />
              <DetailField label="Email" value={v.email || 'No email on file: "Forgot password" won\'t work for this account'} />
            </DetailSection>
            <DetailSection title="Work">
              <DetailField label="Office" value={v.officeName || 'Not assigned. Set it on the Personnel page'} />
              <DetailField label="Role" value={roleLabel(v.role)} />
              <DetailField label="2-step sign-in" value={v.twoFactorEnabled ? 'On (a code is emailed at sign-in)' : 'Off'} />
            </DetailSection>
          </DetailGrid>
        </DetailModal>
      )}

      {showCreate && <UserModal onClose={() => setShowCreate(false)} onSave={handleCreate} />}
      {editing   && <UserModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} />}
      {resetting && <ResetPasswordModal user={resetting} onClose={() => setResetting(null)} onSave={handleResetPassword} />}
      {deleting  && (
        <DeactivateAccountModal user={deleting} accounts={users} onClose={() => setDeleting(null)} onConfirm={handleDeactivate} />
      )}
    </>
  )
}

// ── Audit log archive ─────────────────────────────────────────────────────────
// Old entries leave the live list (keeps it fast) but are kept in an archive that can be
// downloaded as a spreadsheet-friendly CSV, optionally for a date range.
function formatDate(dt) {
  if (!dt) return 'N/A'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}

function AuditArchivePanel({ onArchived }) {
  const toast                       = useToast()
  const [summary, setSummary]       = useState(null)
  const [from, setFrom]             = useState('')
  const [to, setTo]                 = useState('')
  const [exporting, setExporting]   = useState(false)
  const [archiving, setArchiving]   = useState(false)

  const load = useCallback(async () => {
    try {
      const { data } = await getAuditArchiveSummary()
      setSummary(data)
    } catch {
      setSummary(null)
    }
  }, [])

  useEffect(() => { load() }, [load])

  const retention = summary?.retentionDays
  const retentionLabel = !retention ? '' : retention % 365 === 0
    ? `${retention / 365} year${retention === 365 ? '' : 's'}`
    : `${retention} days`

  const handleExport = async () => {
    if (from && to && from > to) { toast.show('The start date is after the end date.', 'error'); return }
    setExporting(true)
    try {
      const { data } = await exportAuditArchive(from, to)
      const url = URL.createObjectURL(data)
      const a = document.createElement('a')
      a.href = url
      a.download = `audit-logs-archive${from ? `-from-${from}` : ''}${to ? `-to-${to}` : ''}.csv`
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)
    } catch {
      toast.show('Failed to export the archive.', 'error')
    } finally {
      setExporting(false)
    }
  }

  const handleArchiveNow = async () => {
    setArchiving(true)
    try {
      const { data } = await runAuditArchive()
      setSummary(data)
      toast.show(data.moved > 0
        ? `Moved ${data.moved} old ${data.moved === 1 ? 'entry' : 'entries'} to the archive.`
        : 'Nothing to archive. No entries are older than the limit.', 'success')
      if (data.moved > 0) onArchived?.()
    } catch {
      toast.show('Failed to archive old entries.', 'error')
    } finally {
      setArchiving(false)
    }
  }

  const inputCls = 'px-2.5 py-1.5 text-sm rounded-md border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 focus:outline-none focus:ring-2 focus:ring-brand-500'

  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 px-5 py-4 space-y-3">
      <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-2">
        <div>
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Archive</p>
          <p className="text-xs text-slate-500 dark:text-zinc-400 mt-0.5">
            {summary
              ? <>Entries older than {retentionLabel} move here every night, so the list above stays fast. Nothing is deleted.{' '}
                  {summary.archivedCount > 0
                    ? <>{summary.archivedCount.toLocaleString()} archived {summary.archivedCount === 1 ? 'entry' : 'entries'}, {formatDate(summary.archivedOldest)} – {formatDate(summary.archivedNewest)}.</>
                    : 'The archive is empty.'}</>
              : 'Loading…'}
          </p>
        </div>
        <Button variant="ghost" size="sm" className="self-start whitespace-nowrap -ml-3 sm:ml-0" onClick={handleArchiveNow} disabled={archiving || !summary}>
          {archiving ? 'Archiving…' : 'Archive old entries now'}
        </Button>
      </div>
      {summary?.archivedCount > 0 && (
        <div className="flex flex-col sm:flex-row sm:items-end gap-2.5">
          <label className="flex flex-col gap-1 text-xs text-slate-500 dark:text-zinc-400">
            From
            <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className={inputCls} />
          </label>
          <label className="flex flex-col gap-1 text-xs text-slate-500 dark:text-zinc-400">
            To
            <input type="date" value={to} onChange={(e) => setTo(e.target.value)} className={inputCls} />
          </label>
          <Button variant="secondary" size="md" onClick={handleExport} disabled={exporting}>
            {exporting ? 'Exporting…' : 'Export archive (CSV)'}
          </Button>
          <p className="text-xs text-slate-400 dark:text-zinc-500 sm:ml-1 sm:mb-2">Leave the dates empty to export everything.</p>
        </div>
      )}
    </div>
  )
}

// ── Audit Logs tab ────────────────────────────────────────────────────────────
const AUDIT_COLUMNS = [
  { key: 'what', label: 'What happened', cell: (l, open) => (
    <PrimaryCell code={formatDateTime(l.loggedAt)} title={l.details} open={open}
      extra={<div className="sm:hidden mt-1 flex flex-wrap gap-1"><ActionBadge action={l.action} /><MappedBadge map={MODULE} value={l.module} /></div>} />
  ) },
  { key: 'action', label: 'Action', className: 'hidden sm:table-cell w-[15rem]', cell: (l) => <div className="truncate"><ActionBadge action={l.action} /></div> },
  { key: 'module', label: 'Area', className: 'hidden lg:table-cell w-[9rem]', cell: (l) => <MappedBadge map={MODULE} value={l.module} /> },
  { key: 'by', label: 'By', className: 'hidden xl:table-cell w-[12%]', cell: (l) => <MutedCell>{l.user?.username || 'System'}</MutedCell> },
]

function AuditLogsTab() {
  const toast                           = useToast()
  const [logs, setLogs]                 = useState([])
  const [loading, setLoading]           = useState(true)
  const [moduleFilter, setModuleFilter] = useState('')
  const [actionFilter, setActionFilter] = useState('')
  const [viewing, setViewing]           = useState(null)
  const [search, setSearch]             = useState('')
  const [page, setPage]                 = useState(1)

  const debouncedSearch = useDebounce(search, 300)

  const fetchLogs = useCallback(async (q = '', { silent = false } = {}) => {
    if (!silent) setLoading(true)
    try {
      const { data } = await getAuditLogs(q)
      setLogs(data)
    } catch {
      if (!silent) toast.show('Failed to load audit logs.', 'error')
    } finally {
      if (!silent) setLoading(false)
    }
  }, [toast])

  useEffect(() => { fetchLogs(debouncedSearch) }, [debouncedSearch, fetchLogs])

  usePolling(() => fetchLogs(debouncedSearch, { silent: true }), 30000)

  const filtered = logs.filter((l) => {
    if (moduleFilter && l.module !== moduleFilter) return false
    if (actionFilter && actionKind(l.action) !== actionFilter) return false
    return true
  })

  useEffect(() => { setPage(1) }, [debouncedSearch, moduleFilter, actionFilter])

  const paged = filtered.slice((page - 1) * AUDIT_PAGE_SIZE, page * AUDIT_PAGE_SIZE)

  const activeFilters = [search.trim(), moduleFilter, actionFilter].filter(Boolean).length

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-2.5">
        <div className="flex items-stretch gap-2">
          <SearchBox value={search} onChange={setSearch} label="Search audit logs" placeholder="Search what happened or who did it" />
        </div>
        <FilterBar activeCount={activeFilters} onClear={() => { setSearch(''); setModuleFilter(''); setActionFilter('') }}>
          <FilterSelect label="Area" value={moduleFilter} onChange={setModuleFilter} options={Object.entries(MODULE).map(([k, m]) => [k, m.label])} />
          <FilterSelect label="Action" value={actionFilter} onChange={setActionFilter} options={Object.entries(ACTION_KIND).map(([k, a]) => [k, a.label])} />
        </FilterBar>
      </div>

      <ListCard title="Audit logs" filtered={filtered.length !== logs.length} count={filtered.length} total={logs.length} noun="entry" loading={loading}
        actions={<RefreshButton onClick={() => fetchLogs(debouncedSearch)} />}
        footer={!loading && <Pager page={page} pageSize={AUDIT_PAGE_SIZE} total={filtered.length} onPage={setPage} />}>
        {loading ? <ListSkeleton /> : filtered.length === 0 ? (
          <ListEmpty>{logs.length === 0 ? 'No activity recorded yet.' : 'No entries match your search or filters.'}</ListEmpty>
        ) : (
          <DataTable columns={AUDIT_COLUMNS} rows={paged} rowKey={(l) => l.id} onOpen={setViewing} selectedKey={viewing?.id}
            caption="Audit log entries. Select an entry to read it in full." />
        )}
      </ListCard>

      {viewing && (
        <DetailModal
          title={actionText(viewing.action) || 'Audit log entry'}
          onClose={() => setViewing(null)}
          subtitle={<>
            <MappedBadge map={MODULE} value={viewing.module} />
            <span className="text-slate-600 dark:text-zinc-400">{formatDateTime(viewing.loggedAt)}</span>
          </>}
        >
          <DetailGrid>
            <DetailSection title="What happened" wide>
              <DetailField label="Details" value={viewing.details} />
              <DetailField label="Done by" value={viewing.user?.fullName || viewing.user?.username || 'System'} />
              <DetailField label="When" value={formatDateTime(viewing.loggedAt)} />
            </DetailSection>
          </DetailGrid>
        </DetailModal>
      )}

      <AuditArchivePanel onArchived={() => fetchLogs(debouncedSearch)} />
    </div>
  )
}

// ── My Account tab ────────────────────────────────────────────────────────────

// ── Page ──────────────────────────────────────────────────────────────────────
// Account management stays ADMIN-only; audit logs and the user's own profile are
// available to everyone.
const TABS_ADMIN = [
  { id: 'accounts',   label: 'Accounts' },
  { id: 'audit-logs', label: 'Audit Logs' },
  { id: 'my-account', label: 'My Account' },
]
const TABS_STAFF = [
  { id: 'my-account', label: 'My Account' },
]

// Marks accounts that need the emailed sign-in code.
function TwoStepChip({ className = '' }) {
  return (
    <span title="2-step verification is on: signing in needs a code sent to this account's email"
      className={`inline-flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-full text-blue-700 dark:text-blue-300 bg-blue-50 dark:bg-blue-400/10 ${className}`}>
      <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path fillRule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clipRule="evenodd" />
      </svg>
      2-step
    </span>
  )
}

function Accounts() {
  const navigate  = useNavigate()
  const location  = useLocation()
  const user      = useSelector((s) => s.auth.user)
  const isAdmin   = user?.role === 'ADMIN'
  const tabs      = isAdmin ? TABS_ADMIN : TABS_STAFF

  const routeTab  = location.pathname === '/audit-logs' ? 'audit-logs'
                  : location.pathname === '/my-account' ? 'my-account'
                  : 'accounts'
  const activeTab = isAdmin ? routeTab : 'my-account' // audit logs are admin-only

  const switchTab = (id) => {
    if (id === 'audit-logs')       navigate('/audit-logs',  { replace: true })
    else if (id === 'my-account')  navigate('/my-account',  { replace: true })
    else                           navigate('/accounts',    { replace: true })
  }

  return (
    <MainLayout>
      {/* Tabs */}
      <div className="flex items-center gap-1 mb-5 overflow-x-auto overflow-y-hidden shadow-[inset_0_-1px_0_theme(colors.slate.200)] dark:shadow-[inset_0_-1px_0_theme(colors.zinc.800)]">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => switchTab(tab.id)}
            role="tab"
            aria-selected={activeTab === tab.id}
            className={`px-4 py-2.5 text-sm font-medium transition-all border-b-2 ${
              activeTab === tab.id
                ? 'border-brand-600 text-brand-700 dark:text-brand-300'
                : 'border-transparent text-slate-600 dark:text-zinc-400 hover:text-slate-900 dark:hover:text-zinc-200'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {activeTab === 'accounts'   && isAdmin && <AccountsTab />}
      {activeTab === 'audit-logs' && <AuditLogsTab />}
      {activeTab === 'my-account' && <MyAccountTab user={user} />}
    </MainLayout>
  )
}

export default Accounts
