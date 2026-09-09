import { useState, useEffect, useCallback } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useSelector, useDispatch } from 'react-redux'
import { setCredentials } from '../../store/slices/authSlice'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import { usePolling } from '../../hooks/usePolling'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import Badge from '../../components/common/Badge'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import UserModal from './UserModal'
import ResetPasswordModal from './ResetPasswordModal'
import { getUsers, createUser, updateUser, deleteUser, changePassword, resetPassword } from '../../services/userService'
import { getAuditLogs } from '../../services/auditLogService'
import { PASSWORD_REQUIREMENTS, isPasswordComplex } from '../../utils/passwordPolicy'

// ── Helpers ───────────────────────────────────────────────────────────────────
function formatDateTime(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleString('en-PH', {
    year: 'numeric', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  })
}

const ACTION_STYLES = {
  CREATE: { bg: 'bg-emerald-500/10 text-emerald-400 ring-emerald-500/20', label: 'CREATE' },
  UPDATE: { bg: 'bg-blue-500/10 text-blue-400 ring-blue-500/20',         label: 'UPDATE' },
  DELETE: { bg: 'bg-red-500/10 text-red-400 ring-red-500/20',            label: 'DELETE' },
}

const MODULE_STYLES = {
  ASSET:       { bg: 'bg-brand-500/10 text-brand-400 ring-brand-500/20' },
  MAINTENANCE: { bg: 'bg-amber-500/10 text-amber-400 ring-amber-500/20' },
  DISPOSAL:    { bg: 'bg-red-500/10 text-red-400 ring-red-500/20' },
  USER:        { bg: 'bg-zinc-500/10 text-zinc-400 ring-zinc-500/20' },
}

const ALL_MODULES  = ['ALL', 'ASSET', 'MAINTENANCE', 'DISPOSAL', 'USER']
const ALL_ACTIONS  = ['ALL', 'CREATE', 'UPDATE', 'DELETE']
const AUDIT_PAGE_SIZE = 8

// ── Accounts tab ──────────────────────────────────────────────────────────────
function AccountsTab() {
  const toast = useToast()
  const [users, setUsers]           = useState([])
  const [loading, setLoading]       = useState(true)
  const [showCreate, setShowCreate] = useState(false)
  const [editing, setEditing]       = useState(null)
  const [deleting, setDeleting]     = useState(null)
  const [resetting, setResetting]   = useState(null)
  const [search, setSearch]         = useState('')

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
      ? `Account for ${data.fullName || data.username} created — credentials emailed to ${data.email}.`
      : `Account for ${data.fullName || data.username} created.`
    toast.show(message, 'success')
  }

  const handleUpdate = async (form) => {
    const { data } = await updateUser(editing.id, form)
    setUsers((prev) => prev.map((u) => (u.id === data.id ? data : u)))
    toast.show('Account updated.', 'success')
  }

  const handleDelete = async () => {
    try {
      await deleteUser(deleting.id)
      setUsers((prev) => prev.filter((u) => u.id !== deleting.id))
      toast.show(`Account "${deleting.fullName || deleting.username}" removed.`, 'warning')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to delete account.', 'error')
    } finally {
      setDeleting(null)
    }
  }

  const handleResetPassword = async (newPassword) => {
    await resetPassword(resetting.id, { newPassword })
    toast.show(`Password reset for "${resetting.fullName || resetting.username}".`, 'success')
  }

  return (
    <>
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-4">
        <div className="relative w-full sm:max-w-xs">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
          </svg>
          <input type="text" placeholder="Search accounts…" value={search} onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
        </div>
        <Button size="md" className="self-start sm:self-auto" onClick={() => setShowCreate(true)}>
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
          </svg>
          Add Account
        </Button>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">All Accounts</p>
          {users.length > 0 && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {users.length} account{users.length !== 1 ? 's' : ''}
            </span>
          )}
        </div>

        {loading ? (
          <div className="divide-y divide-zinc-800/60">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="flex items-center gap-3 px-5 py-3.5">
                <div className="animate-pulse w-8 h-8 rounded-full bg-slate-200 dark:bg-zinc-800 flex-shrink-0" />
                <div className="flex-1 space-y-1.5">
                  <div className="animate-pulse h-3 w-32 rounded bg-slate-200 dark:bg-zinc-800" />
                  <div className="animate-pulse h-3 w-48 rounded bg-slate-200 dark:bg-zinc-800" />
                </div>
                <div className="animate-pulse h-5 w-20 rounded-full bg-slate-200 dark:bg-zinc-800" />
              </div>
            ))}
          </div>
        ) : users.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-zinc-600">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            <p className="text-sm text-zinc-400 font-medium">No accounts yet</p>
            <p className="text-xs text-zinc-600 mt-1">Add a new account using the button above.</p>
          </div>
        ) : (
          <>
            {/* Mobile cards */}
            <div className="md:hidden divide-y divide-slate-100 dark:divide-zinc-800/60">
              {users.map((user) => (
                <div key={user.id} className="flex items-center gap-3 px-4 py-3.5">
                  <div className="w-9 h-9 rounded-full bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 flex items-center justify-center flex-shrink-0">
                    <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300">{(user.fullName || user.username || 'U').charAt(0).toUpperCase()}</span>
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-slate-900 dark:text-white truncate">{user.fullName || user.username}</p>
                    <p className="text-xs text-slate-400 dark:text-zinc-500 truncate mt-0.5">@{user.username}</p>
                    <p className={`text-xs truncate mt-0.5 ${user.email ? 'text-slate-400 dark:text-zinc-500' : 'text-amber-500 dark:text-amber-400 italic'}`}>
                      {user.email || 'No email on file (forgot-password unavailable)'}
                    </p>
                    <div className="mt-1.5 flex items-center gap-1.5">
                      <Badge
                        label={user.role === 'ADMIN' ? 'Administrator' : 'Staff'}
                        color={user.role === 'ADMIN' ? 'green' : 'gray'}
                      />
                      {!user.isActive && (
                        <span className="text-xs text-red-400 bg-red-400/10 px-1.5 py-0.5 rounded-full">Inactive</span>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-1 flex-shrink-0">
                    <button onClick={() => setEditing(user)} title="Edit account"
                      className="p-2 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                        <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                      </svg>
                    </button>
                    <button onClick={() => setResetting(user)} title="Reset password"
                      className="p-2 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                        <path fillRule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clipRule="evenodd" />
                      </svg>
                    </button>
                    <button onClick={() => setDeleting(user)} title="Delete account"
                      className="p-2 rounded-md text-zinc-500 hover:text-red-400 hover:bg-red-950/40 transition-all duration-150">
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                        <path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" />
                      </svg>
                    </button>
                  </div>
                </div>
              ))}
            </div>
            {/* Desktop table */}
            <div className="hidden md:block overflow-x-auto">
              <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
                <thead>
                  <tr>
                    {['Username', 'Email', 'Full Name', 'Role', 'Active', ''].map((h) => (
                      <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                  {users.map((user) => (
                    <tr key={user.id} className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                      <td className="px-5 py-3.5 whitespace-nowrap">
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 rounded-full bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 flex items-center justify-center flex-shrink-0">
                            <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300">{(user.fullName || user.username || 'U').charAt(0).toUpperCase()}</span>
                          </div>
                          <span className="font-mono text-xs text-slate-600 dark:text-zinc-400">@{user.username}</span>
                        </div>
                      </td>
                      <td className="px-5 py-3.5 text-xs whitespace-nowrap">
                        {user.email
                          ? <span className="text-slate-500 dark:text-zinc-400">{user.email}</span>
                          : <span className="text-amber-500 dark:text-amber-400 italic">No email</span>}
                      </td>
                      <td className="px-5 py-3.5 font-medium text-slate-900 dark:text-white whitespace-nowrap">{user.fullName || '—'}</td>
                      <td className="px-5 py-3.5">
                        <Badge
                          label={user.role === 'ADMIN' ? 'Administrator' : 'Staff'}
                          color={user.role === 'ADMIN' ? 'green' : 'gray'}
                        />
                      </td>
                      <td className="px-5 py-3.5">
                        <span className={`inline-flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-full ${user.isActive ? 'text-emerald-600 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-400/10' : 'text-slate-400 dark:text-zinc-600 bg-slate-100 dark:bg-zinc-800'}`}>
                          <span className={`w-1.5 h-1.5 rounded-full ${user.isActive ? 'bg-emerald-500' : 'bg-slate-400'}`} />
                          {user.isActive ? 'Active' : 'Inactive'}
                        </span>
                      </td>
                      <td className="px-5 py-3.5">
                        <div className="flex items-center justify-end gap-1">
                          <button onClick={() => setEditing(user)} title="Edit account"
                            className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                              <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                            </svg>
                          </button>
                          <button onClick={() => setResetting(user)} title="Reset password"
                            className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                              <path fillRule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clipRule="evenodd" />
                            </svg>
                          </button>
                          <button onClick={() => setDeleting(user)} title="Delete account"
                            className="p-1.5 rounded-md text-zinc-500 hover:text-red-400 hover:bg-red-950/40 transition-all duration-150">
                            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                              <path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" />
                            </svg>
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>

      {showCreate && <UserModal onClose={() => setShowCreate(false)} onSave={handleCreate} />}
      {editing   && <UserModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} />}
      {resetting && <ResetPasswordModal user={resetting} onClose={() => setResetting(null)} onSave={handleResetPassword} />}
      {deleting  && (
        <ConfirmDialog
          title="Delete this account?"
          message={`"${deleting.fullName || deleting.username}" will be permanently removed.`}
          confirmLabel="Delete Account"
          onConfirm={handleDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
    </>
  )
}

// ── Audit Logs tab ────────────────────────────────────────────────────────────
function AuditLogsTab() {
  const toast                           = useToast()
  const [logs, setLogs]                 = useState([])
  const [loading, setLoading]           = useState(true)
  const [moduleFilter, setModuleFilter] = useState('ALL')
  const [actionFilter, setActionFilter] = useState('ALL')
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
    if (moduleFilter !== 'ALL' && l.module !== moduleFilter) return false
    if (actionFilter !== 'ALL' && l.action !== actionFilter) return false
    return true
  })

  useEffect(() => { setPage(1) }, [debouncedSearch, moduleFilter, actionFilter])

  const totalPages = Math.max(1, Math.ceil(filtered.length / AUDIT_PAGE_SIZE))
  const paged = filtered.slice((page - 1) * AUDIT_PAGE_SIZE, page * AUDIT_PAGE_SIZE)

  return (
    <div className="space-y-4">
      {/* Filters */}
      <div className="flex flex-col sm:flex-row flex-wrap items-start sm:items-center gap-3">
        <div className="relative w-full sm:flex-1 sm:min-w-[200px] sm:max-w-xs">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
          </svg>
          <input
            type="text" placeholder="Search description or user…"
            value={search} onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all"
          />
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          {ALL_MODULES.map((m) => (
            <button key={m} onClick={() => setModuleFilter(m)}
              className={`text-xs px-2.5 py-1 rounded-full font-medium transition-all ${
                moduleFilter === m
                  ? 'bg-brand-500 text-white'
                  : 'bg-slate-100 dark:bg-zinc-800 text-slate-500 dark:text-zinc-400 hover:bg-slate-200 dark:hover:bg-zinc-700'
              }`}>
              {m}
            </button>
          ))}
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          {ALL_ACTIONS.map((a) => {
            const style = ACTION_STYLES[a]
            return (
              <button key={a} onClick={() => setActionFilter(a)}
                className={`text-xs px-2.5 py-1 rounded-full font-medium transition-all ${
                  actionFilter === a
                    ? (style ? style.bg + ' ring-1' : 'bg-brand-500 text-white')
                    : 'bg-slate-100 dark:bg-zinc-800 text-slate-500 dark:text-zinc-400 hover:bg-slate-200 dark:hover:bg-zinc-700'
                }`}>
                {a}
              </button>
            )
          })}
        </div>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">System Audit Logs</p>
          {!loading && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {filtered.length}{filtered.length !== logs.length ? ` of ${logs.length}` : ''} {logs.length === 1 ? 'entry' : 'entries'}
            </span>
          )}
        </div>

        {loading ? (
          <div className="divide-y divide-zinc-800/60">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="flex items-center gap-4 px-5 py-3.5">
                <div className="animate-pulse h-3 w-28 rounded bg-slate-200 dark:bg-zinc-800" />
                <div className="animate-pulse h-3 w-20 rounded bg-slate-200 dark:bg-zinc-800 ml-auto" />
                <div className="animate-pulse h-5 w-16 rounded-full bg-slate-200 dark:bg-zinc-800" />
                <div className="animate-pulse h-3 w-40 rounded bg-slate-200 dark:bg-zinc-800" />
              </div>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-zinc-600">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            <p className="text-sm text-zinc-500">{logs.length === 0 ? 'No activity recorded yet.' : 'No entries match the current filter.'}</p>
          </div>
        ) : (
          <div className="hidden md:block overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Timestamp', 'Action', 'Module', 'Description', 'Performed By'].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((log) => {
                  const aStyle = ACTION_STYLES[log.action] || { bg: 'bg-slate-100 dark:bg-zinc-700 text-slate-600 dark:text-zinc-300', label: log.action }
                  const mStyle = MODULE_STYLES[log.module] || { bg: 'bg-slate-100 dark:bg-zinc-700 text-slate-600 dark:text-zinc-300' }
                  return (
                    <tr key={log.id} className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                      <td className="px-5 py-3.5 text-xs text-slate-400 dark:text-zinc-500 whitespace-nowrap font-mono">{formatDateTime(log.loggedAt)}</td>
                      <td className="px-5 py-3.5 whitespace-nowrap">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ring-1 ${aStyle.bg}`}>{aStyle.label}</span>
                      </td>
                      <td className="px-5 py-3.5 whitespace-nowrap">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ring-1 ${mStyle.bg}`}>{log.module}</span>
                      </td>
                      <td className="px-5 py-3.5 text-slate-600 dark:text-zinc-300 max-w-md">
                        <span className="block truncate" title={log.details}>{log.details}</span>
                      </td>
                      <td className="px-5 py-3.5 whitespace-nowrap">
                        <div className="flex items-center gap-2">
                          <div className="w-6 h-6 rounded-full bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 flex items-center justify-center flex-shrink-0">
                            <span className="text-[10px] font-semibold text-slate-500 dark:text-zinc-400">{(log.user?.username || 'S').charAt(0).toUpperCase()}</span>
                          </div>
                          <span className="text-slate-500 dark:text-zinc-400 text-xs">{log.user?.username || 'System'}</span>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        {!loading && filtered.length > AUDIT_PAGE_SIZE && (
          <div className="px-5 py-3 border-t border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
            <p className="text-xs text-slate-400 dark:text-zinc-500">
              {(page - 1) * AUDIT_PAGE_SIZE + 1}–{Math.min(page * AUDIT_PAGE_SIZE, filtered.length)} of {filtered.length}
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
    </div>
  )
}

// ── My Account tab ────────────────────────────────────────────────────────────
const INPUT_CLASS =
  'w-full rounded-lg border border-slate-300 dark:border-zinc-700 bg-white dark:bg-zinc-800/60 ' +
  'px-3.5 py-2.5 text-sm text-slate-900 dark:text-white placeholder:text-slate-400 ' +
  'dark:placeholder:text-zinc-600 hover:border-slate-400 dark:hover:border-zinc-600 ' +
  'focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

function MyAccountTab({ user }) {
  const toast                         = useToast()
  const [current, setCurrent]         = useState('')
  const [newPass, setNewPass]         = useState('')
  const [confirm, setConfirm]         = useState('')
  const [showCurrent, setShowCurrent] = useState(false)
  const [showNew, setShowNew]         = useState(false)
  const [saving, setSaving]           = useState(false)
  const [error, setError]             = useState('')

  const complexityMet = isPasswordComplex(newPass)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    if (!complexityMet) { setError('New password does not meet the requirements below.'); return }
    if (newPass !== confirm) { setError('New passwords do not match.'); return }
    setSaving(true)
    try {
      await changePassword({ currentPassword: current, newPassword: newPass })
      toast.show('Password updated successfully.', 'success')
      setCurrent(''); setNewPass(''); setConfirm('')
    } catch (err) {
      setError(err.response?.data?.message || 'Failed to update password.')
    } finally {
      setSaving(false)
    }
  }

  const EyeIcon = ({ open }) => open ? (
    <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
      <path fillRule="evenodd" d="M3.707 2.293a1 1 0 00-1.414 1.414l14 14a1 1 0 001.414-1.414l-1.473-1.473A10.014 10.014 0 0019.542 10C18.268 5.943 14.478 3 10 3a9.958 9.958 0 00-4.512 1.074l-1.78-1.781zm4.261 4.26l1.514 1.515a2.003 2.003 0 012.45 2.45l1.514 1.514a4 4 0 00-5.478-5.478z" clipRule="evenodd" />
      <path d="M12.454 16.697L9.75 13.992a4 4 0 01-3.742-3.741L2.335 6.578A9.98 9.98 0 00.458 10c1.274 4.057 5.065 7 9.542 7 .847 0 1.669-.105 2.454-.303z" />
    </svg>
  ) : (
    <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
      <path d="M10 12a2 2 0 100-4 2 2 0 000 4z" />
      <path fillRule="evenodd" d="M.458 10C1.732 5.943 5.522 3 10 3s8.268 2.943 9.542 7c-1.274 4.057-5.064 7-9.542 7S1.732 14.057.458 10zM14 10a4 4 0 11-8 0 4 4 0 018 0z" clipRule="evenodd" />
    </svg>
  )

  const displayName = user?.fullName || user?.username || 'User'
  const initials = displayName.split(' ').map((n) => n[0]).join('').slice(0, 2).toUpperCase()

  return (
    <div className="flex justify-center">
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 items-start w-full max-w-4xl">
      {/* Profile card */}
      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 p-5">
        <p className="text-xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider mb-4">Profile</p>
        <div className="flex items-center gap-4 mb-4">
          <div className="w-12 h-12 rounded-full bg-brand-500 text-white flex items-center justify-center flex-shrink-0">
            <span className="text-lg font-bold">{initials}</span>
          </div>
          <div>
            <p className="font-semibold text-slate-900 dark:text-white text-sm">{displayName}</p>
            <p className="text-xs font-mono text-brand-400 mt-0.5">@{user?.username}</p>
          </div>
        </div>
        <div className="flex items-center gap-2.5 border-t border-slate-100 dark:border-zinc-800 pt-3">
          <span className="text-xs text-slate-400 dark:text-zinc-500">Role</span>
          <Badge label={user?.role === 'ADMIN' ? 'Administrator' : 'ICT Staff'} color={user?.role === 'ADMIN' ? 'green' : 'gray'} />
        </div>
      </div>

      {/* Change password card */}
      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 p-5">
        <p className="text-xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider mb-4">Change Password</p>

        {error && (
          <div className="flex items-start gap-2 bg-red-50 dark:bg-red-950/50 border border-red-200 dark:border-red-900/60 text-red-600 dark:text-red-400 rounded-lg px-4 py-3 text-sm mb-4">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mt-0.5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
            </svg>
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} noValidate className="space-y-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Current Password</label>
            <div className="relative">
              <input type={showCurrent ? 'text' : 'password'} value={current}
                onChange={(e) => { setCurrent(e.target.value); setError('') }}
                placeholder="Enter current password" className={INPUT_CLASS + ' pr-10'} />
              <button type="button" tabIndex={-1} onClick={() => setShowCurrent(v => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 dark:text-zinc-500 hover:text-slate-600 dark:hover:text-zinc-300 transition-colors">
                <EyeIcon open={showCurrent} />
              </button>
            </div>
          </div>

          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">New Password</label>
            <div className="relative">
              <input type={showNew ? 'text' : 'password'} value={newPass}
                onChange={(e) => { setNewPass(e.target.value); setError('') }}
                placeholder="Enter new password" className={INPUT_CLASS + ' pr-10'} />
              <button type="button" tabIndex={-1} onClick={() => setShowNew(v => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 dark:text-zinc-500 hover:text-slate-600 dark:hover:text-zinc-300 transition-colors">
                <EyeIcon open={showNew} />
              </button>
            </div>
            {newPass && (
              <ul className="mt-1 space-y-0.5">
                {PASSWORD_REQUIREMENTS.map(({ key, label, test }) => {
                  const met = test(newPass)
                  return (
                    <li key={key} className={`flex items-center gap-1.5 text-xs transition-colors ${met ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-400 dark:text-zinc-500'}`}>
                      {met
                        ? <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" /></svg>
                        : <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" /></svg>
                      }
                      {label}
                    </li>
                  )
                })}
              </ul>
            )}
          </div>

          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Confirm New Password</label>
            <input type={showNew ? 'text' : 'password'} value={confirm}
              onChange={(e) => { setConfirm(e.target.value); setError('') }}
              placeholder="Re-enter new password" className={INPUT_CLASS} />
          </div>

          <div className="pt-1">
            <Button type="submit" size="md" disabled={saving || !current || !newPass || !confirm}>
              {saving ? 'Saving…' : 'Update Password'}
            </Button>
          </div>
        </form>
      </div>
    </div>
    </div>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────────
// Account management stays ADMIN-only; audit logs and the user's own profile are
// available to everyone.
const TABS_ADMIN = [
  { id: 'accounts',   label: 'Accounts' },
  { id: 'audit-logs', label: 'Audit Logs' },
  { id: 'my-account', label: 'My Account' },
]
const TABS_STAFF = [
  { id: 'audit-logs', label: 'Audit Logs' },
  { id: 'my-account', label: 'My Account' },
]

function Accounts() {
  const navigate  = useNavigate()
  const location  = useLocation()
  const user      = useSelector((s) => s.auth.user)
  const isAdmin   = user?.role === 'ADMIN'
  const tabs      = isAdmin ? TABS_ADMIN : TABS_STAFF

  const routeTab  = location.pathname === '/audit-logs' ? 'audit-logs'
                  : location.pathname === '/my-account' ? 'my-account'
                  : 'accounts'
  const activeTab = (!isAdmin && routeTab === 'accounts') ? 'audit-logs' : routeTab

  const switchTab = (id) => {
    if (id === 'audit-logs')       navigate('/audit-logs',  { replace: true })
    else if (id === 'my-account')  navigate('/my-account',  { replace: true })
    else                           navigate('/accounts',    { replace: true })
  }

  return (
    <MainLayout>
      {/* Tabs */}
      <div className="flex items-center gap-1 mb-5 border-b border-slate-200 dark:border-zinc-800 overflow-x-auto">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => switchTab(tab.id)}
            className={`px-4 py-2.5 text-sm font-medium transition-all border-b-2 -mb-px ${
              activeTab === tab.id
                ? 'border-brand-500 text-brand-500 dark:text-brand-400'
                : 'border-transparent text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-300'
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
