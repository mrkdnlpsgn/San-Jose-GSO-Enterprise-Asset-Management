import { useState, useEffect, useCallback } from 'react'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import Modal from '../../components/common/Modal'
import Badge from '../../components/common/Badge'
import { getPersonnel, updatePersonnel } from '../../services/personnelService'
import { getOffices } from '../../services/officeService'

const PAGE_SIZE = 8

const INPUT_CLASS ='w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

// Personnel are the accounts — each is created on the Accounts page. This is the only
// place an admin assigns an account's office; name and role come from the account.
function PersonnelModal({ onClose, onSave, initial, offices = [] }) {
  const [form, setForm]     = useState({
    position:    initial.position || '',
    officeId:    initial.office?.id ? String(initial.office.id) : '',
    contactInfo: initial.contactInfo || '',
  })
  const [errors, setErrors] = useState({})
  const [saving, setSaving] = useState(false)

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!form.officeId) { setErrors({ officeId: 'Office is required.' }); return }
    setSaving(true)
    try {
      await onSave({
        officeId:    Number(form.officeId),
        position:    form.position.trim() || null,
        contactInfo: form.contactInfo.trim() || null,
      })
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to save.' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title="Assign Office" subtitle={`${initial.fullName} · @${initial.username}`} onClose={onClose}>
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Office<span className="text-red-400 ml-0.5">*</span></label>
          <select className={INPUT_CLASS + ' appearance-none'} value={form.officeId} onChange={set('officeId')} autoFocus>
            <option value="">— Select office —</option>
            {offices.map((o) => <option key={o.id} value={String(o.id)}>{o.officeName}</option>)}
          </select>
          {errors.officeId && <p className="text-xs text-red-400">{errors.officeId}</p>}
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Position <span className="text-slate-400 font-normal">(optional)</span></label>
          <input className={INPUT_CLASS} placeholder="e.g. Administrative Aide IV" value={form.position} onChange={set('position')} />
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Contact Info <span className="text-slate-400 font-normal">(optional)</span></label>
          <input className={INPUT_CLASS} placeholder="Phone or email" value={form.contactInfo} onChange={set('contactInfo')} />
        </div>
        <p className="text-xs text-slate-400 dark:text-zinc-500">Name and role are managed on the Accounts page.</p>
        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : 'Save'}</Button>
        </div>
      </form>
    </Modal>
  )
}

function Personnel() {
  const toast = useToast()
  const [personnel, setPersonnel]   = useState([])
  const [offices, setOffices]       = useState([])
  const [loading, setLoading]       = useState(true)
  const [search, setSearch]         = useState('')
  const [editing, setEditing]       = useState(null)
  const [page, setPage]             = useState(1)

  const debouncedSearch = useDebounce(search, 300)

  const fetchPersonnel = useCallback(async (q = '') => {
    setLoading(true)
    try {
      const { data } = await getPersonnel(q)
      setPersonnel(data)
    } catch {
      toast.show('Failed to load personnel.', 'error')
    } finally {
      setLoading(false)
    }
  }, [toast])

  useEffect(() => { fetchPersonnel(debouncedSearch) }, [debouncedSearch, fetchPersonnel])
  useEffect(() => { setPage(1) }, [debouncedSearch])
  useEffect(() => { getOffices().then(({ data }) => setOffices(data)).catch(() => {}) }, [])

  const handleUpdate = async (payload) => {
    const { data } = await updatePersonnel(editing.id, payload)
    setPersonnel((prev) => prev.map((p) => (p.id === data.id ? data : p)))
    toast.show(`${data.fullName} assigned to ${data.office?.officeName}.`, 'success')
  }

  const filtered = personnel
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  return (
    <MainLayout>
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5">
        <div className="relative w-full sm:max-w-xs">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
          </svg>
          <input type="text" placeholder="Search name, username, office…" value={search} onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
        </div>
        {!loading && personnel.some((p) => !p.office && p.userActive !== false) && (
          <p className="text-xs text-amber-500 dark:text-amber-400 self-start sm:self-auto">
            {personnel.filter((p) => !p.office && p.userActive !== false).length} active account(s) still need an office.
          </p>
        )}
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">All Personnel</p>
          {!loading && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {filtered.length} {filtered.length === 1 ? 'person' : 'people'}
            </span>
          )}
        </div>

        {loading ? (
          <div className="divide-y divide-slate-100 dark:divide-zinc-800">
            {Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="flex items-center gap-3 px-5 py-3.5">
                <div className="animate-pulse h-3 w-40 rounded bg-slate-200 dark:bg-zinc-800" />
                <div className="animate-pulse h-3 w-64 rounded bg-slate-200 dark:bg-zinc-800 ml-auto" />
              </div>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-zinc-600">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M17 20h5v-2a4 4 0 00-3-3.87M9 20H4v-2a4 4 0 013-3.87m6-1.13a4 4 0 10-4-4 4 4 0 004 4zm6 0a4 4 0 10-3.995-4.2" />
            </svg>
            <p className="text-sm text-zinc-400 font-medium">{debouncedSearch ? 'No personnel match your search' : 'No accounts yet — create one on the Accounts page'}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Full Name', 'Account', 'Office', 'Position', 'Contact Info', ''].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((p) => (
                  <tr key={p.id} className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                    <td className="px-5 py-3.5 font-medium text-slate-900 dark:text-white whitespace-nowrap">{p.fullName}</td>
                    <td className="px-5 py-3.5 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-xs text-slate-500 dark:text-zinc-400">@{p.username}</span>
                        <Badge label={p.userRole === 'ADMIN' ? 'Administrator' : 'Staff'} color={p.userRole === 'ADMIN' ? 'green' : 'gray'} />
                        {p.userActive === false && (
                          <span className="text-xs text-red-400 bg-red-400/10 px-1.5 py-0.5 rounded-full">Inactive</span>
                        )}
                      </div>
                    </td>
                    <td className="px-5 py-3.5 text-xs whitespace-nowrap">
                      {p.office?.officeName
                        ? <span className="text-slate-600 dark:text-zinc-300">{p.office.officeName}</span>
                        : <span className="text-amber-500 dark:text-amber-400 italic">Not assigned</span>}
                    </td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{p.position || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{p.contactInfo || '—'}</td>
                    <td className="px-5 py-3.5">
                      <div className="flex items-center justify-end gap-1">
                        <button onClick={() => setEditing(p)}
                          className="px-2.5 py-1.5 rounded-md text-xs font-semibold text-brand-500 dark:text-brand-400 hover:bg-brand-500/10 transition-all duration-150">
                          {p.office ? 'Change office' : 'Assign office'}
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

      {editing  && <PersonnelModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} offices={offices} />}
    </MainLayout>
  )
}

export default Personnel
