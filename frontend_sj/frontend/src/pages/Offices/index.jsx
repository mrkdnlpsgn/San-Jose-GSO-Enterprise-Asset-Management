import { useState, useEffect, useCallback } from 'react'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import AlertDialog from '../../components/common/AlertDialog'
import Modal from '../../components/common/Modal'
import { getOffices, createOffice, updateOffice, deleteOffice } from '../../services/officeService'
import { getUsers } from '../../services/userService'
import { newIdempotencyKey } from '../../utils/idempotency'

const PAGE_SIZE = 8

const INPUT_CLASS ='w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

function OfficeModal({ onClose, onSave, initial = null }) {
  const isEditing = !!initial
  const [form, setForm]     = useState({ officeName: initial?.officeName || '', headUserId: initial?.headUser?.id ? String(initial.headUser.id) : '' })
  const [errors, setErrors] = useState({})
  const [saving, setSaving] = useState(false)
  const [users, setUsers]   = useState([])
  const [idempotencyKey] = useState(() => newIdempotencyKey())

  useEffect(() => {
    getUsers().then(({ data }) => setUsers(data)).catch(() => {})
  }, [])

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!form.officeName.trim()) { setErrors({ officeName: 'Office name is required.' }); return }
    setSaving(true)
    try {
      const payload = {
        officeName: form.officeName.trim(),
        headUserId: form.headUserId ? Number(form.headUserId) : null,
      }
      await onSave(payload, idempotencyKey)
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to save.' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title={isEditing ? 'Edit Office' : 'Add Office'} onClose={onClose}>
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Office Name<span className="text-red-400 ml-0.5">*</span></label>
          <input className={INPUT_CLASS} placeholder="e.g. Office of the Mayor" value={form.officeName} onChange={set('officeName')} />
          {errors.officeName && <p className="text-xs text-red-400">{errors.officeName}</p>}
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Head User <span className="text-slate-400 font-normal">(optional)</span></label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.headUserId} onChange={set('headUserId')}>
              <option value="">— None —</option>
              {users.map((u) => <option key={u.id} value={String(u.id)}>{u.fullName || u.username}</option>)}
            </select>
            <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
            </div>
          </div>
        </div>
        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : isEditing ? 'Save Changes' : 'Add Office'}</Button>
        </div>
      </form>
    </Modal>
  )
}

function Offices() {
  const toast = useToast()
  const [offices, setOffices]   = useState([])
  const [loading, setLoading]   = useState(true)
  const [search, setSearch]     = useState('')
  const [showAdd, setShowAdd]   = useState(false)
  const [editing, setEditing]   = useState(null)
  const [deleting, setDeleting] = useState(null)
  const [blockedDelete, setBlockedDelete] = useState(null)
  const [page, setPage]         = useState(1)

  const debouncedSearch = useDebounce(search, 300)

  const fetchOffices = useCallback(async (q = '') => {
    setLoading(true)
    try {
      const { data } = await getOffices(q)
      setOffices(data)
    } catch {
      toast.show('Failed to load offices.', 'error')
    } finally {
      setLoading(false)
    }
  }, [toast])

  useEffect(() => { fetchOffices(debouncedSearch) }, [debouncedSearch, fetchOffices])
  useEffect(() => { setPage(1) }, [debouncedSearch])

  const handleCreate = async (payload, idempotencyKey) => {
    const { data } = await createOffice(payload, idempotencyKey)
    setOffices((prev) => [...prev, data])
    toast.show('Office created.', 'success')
  }

  const handleUpdate = async (payload) => {
    const { data } = await updateOffice(editing.id, payload)
    setOffices((prev) => prev.map((o) => (o.id === data.id ? data : o)))
    toast.show('Office updated.', 'success')
  }

  const handleDelete = async () => {
    const target = deleting
    setDeleting(null)
    try {
      await deleteOffice(target.id)
      setOffices((prev) => prev.filter((o) => o.id !== target.id))
      toast.show('Office deleted.', 'warning')
    } catch (err) {
      if (err.response?.status === 409) {
        setBlockedDelete(err.response.data?.message || `"${target.officeName}" has assets assigned to it and can't be deleted.`)
      } else {
        toast.show(err.response?.data?.message || 'Failed to delete office.', 'error')
      }
    }
  }

  const filtered = offices
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  return (
    <MainLayout>
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5">
        <div className="relative w-full sm:max-w-xs">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
          </svg>
          <input type="text" placeholder="Search offices…" value={search} onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
        </div>
        <Button size="md" className="self-start sm:self-auto" onClick={() => setShowAdd(true)}>
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
          </svg>
          Add Office
        </Button>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">All Offices</p>
          {!loading && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {filtered.length} office{filtered.length !== 1 ? 's' : ''}
            </span>
          )}
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
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
            </svg>
            <p className="text-sm text-zinc-400 font-medium">{offices.length === 0 ? 'No offices yet' : 'No offices match your search'}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Office Name', 'Head User', 'Actions'].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((office) => (
                  <tr key={office.id} className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                    <td className="px-5 py-3.5 font-medium text-slate-900 dark:text-white whitespace-nowrap">{office.officeName}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">
                      {office.headUser ? (office.headUser.fullName || office.headUser.username) : '—'}
                    </td>
                    <td className="px-5 py-3.5">
                      <div className="flex items-center justify-end gap-1">
                        <button onClick={() => setEditing(office)} title="Edit"
                          className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                            <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                          </svg>
                        </button>
                        <button onClick={() => setDeleting(office)} title="Delete"
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

      {showAdd  && <OfficeModal onClose={() => setShowAdd(false)} onSave={handleCreate} />}
      {editing  && <OfficeModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} />}
      {deleting && (
        <ConfirmDialog
          title="Delete this office?"
          message={`"${deleting.officeName}" will be permanently removed.`}
          confirmLabel="Delete Office"
          onConfirm={handleDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
      {blockedDelete && (
        <AlertDialog
          title="Can't delete this office"
          message={blockedDelete}
          onClose={() => setBlockedDelete(null)}
        />
      )}
    </MainLayout>
  )
}

export default Offices
