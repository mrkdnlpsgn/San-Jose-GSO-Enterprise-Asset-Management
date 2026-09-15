import { useState, useEffect, useCallback } from 'react'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import AlertDialog from '../../components/common/AlertDialog'
import Modal from '../../components/common/Modal'
import { getPersonnel, createPersonnel, updatePersonnel, deletePersonnel } from '../../services/personnelService'
import { getOffices } from '../../services/officeService'
import { newIdempotencyKey } from '../../utils/idempotency'

const PAGE_SIZE = 8

const INPUT_CLASS ='w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

function PersonnelModal({ onClose, onSave, initial = null, offices = [] }) {
  const isEditing = !!initial
  const [form, setForm]     = useState({
    fullName:    initial?.fullName || '',
    position:    initial?.position || '',
    officeId:    initial?.office?.id ? String(initial.office.id) : '',
    contactInfo: initial?.contactInfo || '',
  })
  const [errors, setErrors] = useState({})
  const [saving, setSaving] = useState(false)
  const [idempotencyKey] = useState(() => newIdempotencyKey())

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!form.fullName.trim()) { setErrors({ fullName: 'Full name is required.' }); return }
    setSaving(true)
    try {
      await onSave({
        fullName:    form.fullName.trim(),
        position:    form.position.trim() || null,
        officeId:    form.officeId ? Number(form.officeId) : null,
        contactInfo: form.contactInfo.trim() || null,
      }, idempotencyKey)
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to save.' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title={isEditing ? 'Edit Personnel' : 'Add Personnel'} onClose={onClose}>
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Full Name<span className="text-red-400 ml-0.5">*</span></label>
          <input className={INPUT_CLASS} placeholder="e.g. Juan Dela Cruz" value={form.fullName} onChange={set('fullName')} />
          {errors.fullName && <p className="text-xs text-red-400">{errors.fullName}</p>}
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Position <span className="text-slate-400 font-normal">(optional)</span></label>
          <input className={INPUT_CLASS} placeholder="e.g. Administrative Aide IV" value={form.position} onChange={set('position')} />
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Office <span className="text-slate-400 font-normal">(optional)</span></label>
          <select className={INPUT_CLASS + ' appearance-none'} value={form.officeId} onChange={set('officeId')}>
            <option value="">— None —</option>
            {offices.map((o) => <option key={o.id} value={String(o.id)}>{o.officeName}</option>)}
          </select>
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Contact Info <span className="text-slate-400 font-normal">(optional)</span></label>
          <input className={INPUT_CLASS} placeholder="Phone or email" value={form.contactInfo} onChange={set('contactInfo')} />
        </div>
        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : isEditing ? 'Save Changes' : 'Add Personnel'}</Button>
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
  const [showAdd, setShowAdd]       = useState(false)
  const [editing, setEditing]       = useState(null)
  const [deleting, setDeleting]     = useState(null)
  const [blockedDelete, setBlockedDelete] = useState(null)
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

  const handleCreate = async (payload, idempotencyKey) => {
    const { data } = await createPersonnel(payload, idempotencyKey)
    setPersonnel((prev) => [...prev, data])
    toast.show('Personnel created.', 'success')
  }

  const handleUpdate = async (payload) => {
    const { data } = await updatePersonnel(editing.id, payload)
    setPersonnel((prev) => prev.map((p) => (p.id === data.id ? data : p)))
    toast.show('Personnel updated.', 'success')
  }

  const handleDelete = async () => {
    const target = deleting
    setDeleting(null)
    try {
      await deletePersonnel(target.id)
      setPersonnel((prev) => prev.filter((p) => p.id !== target.id))
      toast.show('Personnel deleted.', 'warning')
    } catch (err) {
      if (err.response?.status === 409) {
        setBlockedDelete(err.response.data?.message || `"${target.fullName}" has assets assigned to them and can't be deleted.`)
      } else {
        toast.show(err.response?.data?.message || 'Failed to delete personnel.', 'error')
      }
    }
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
          <input type="text" placeholder="Search personnel…" value={search} onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
        </div>
        <Button size="md" className="self-start sm:self-auto" onClick={() => setShowAdd(true)}>
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
          </svg>
          Add Personnel
        </Button>
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
            <p className="text-sm text-zinc-400 font-medium">{personnel.length === 0 ? 'No personnel yet' : 'No personnel match your search'}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Full Name', 'Position', 'Office', 'Contact Info', 'Actions'].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((p) => (
                  <tr key={p.id} className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                    <td className="px-5 py-3.5 font-medium text-slate-900 dark:text-white whitespace-nowrap">{p.fullName}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{p.position || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{p.office?.officeName || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{p.contactInfo || '—'}</td>
                    <td className="px-5 py-3.5">
                      <div className="flex items-center justify-end gap-1">
                        <button onClick={() => setEditing(p)} title="Edit"
                          className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                            <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                          </svg>
                        </button>
                        <button onClick={() => setDeleting(p)} title="Delete"
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

      {showAdd  && <PersonnelModal onClose={() => setShowAdd(false)} onSave={handleCreate} offices={offices} />}
      {editing  && <PersonnelModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} offices={offices} />}
      {deleting && (
        <ConfirmDialog
          title="Delete this personnel record?"
          message={`"${deleting.fullName}" will be permanently removed.`}
          confirmLabel="Delete Personnel"
          onConfirm={handleDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
      {blockedDelete && (
        <AlertDialog
          title="Can't delete this personnel record"
          message={blockedDelete}
          onClose={() => setBlockedDelete(null)}
        />
      )}
    </MainLayout>
  )
}

export default Personnel
