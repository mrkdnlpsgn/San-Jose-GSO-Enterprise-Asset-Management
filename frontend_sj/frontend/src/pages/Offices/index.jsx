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
import { useFormDraft, useDraftList } from '../../hooks/useFormDraft'
import DraftNotice from '../../components/common/DraftNotice'
import DraftRows from '../../components/common/DraftRows'
import { SearchBox, ListCard, RefreshButton, Pager, ListSkeleton, ListEmpty, DataTable, PrimaryCell, MutedCell, Icon, ICON } from '../../components/common/ListKit'

const PAGE_SIZE = 25

const INPUT_CLASS ='w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

// onDelete (editing only) puts a Delete button in the form, since a row opens this form directly.
function OfficeModal({ onClose, onSave, onDelete, initial = null }) {
  const isEditing = !!initial
  const [form, setForm]     = useState({ officeName: initial?.officeName || '', headUserId: initial?.headUser?.id ? String(initial.headUser.id) : '' })
  const draft = useFormDraft(`office:${initial?.id ?? 'new'}`, form, setForm, {
    title: (f) => f.officeName.trim() || initial?.officeName || 'Untitled office',
  })
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
      draft.clear()
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
        <DraftNotice draft={draft} />
        {errors._global && (
          <div className="text-sm text-red-700 dark:text-red-300 bg-red-500/10 border border-red-500/30 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Office Name<span className="text-red-400 ml-0.5">*</span></label>
          <input className={INPUT_CLASS} placeholder="e.g. Office of the Mayor" value={form.officeName} onChange={set('officeName')} />
          {errors.officeName && <p className="text-xs text-red-700 dark:text-red-300">{errors.officeName}</p>}
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Head User <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.headUserId} onChange={set('headUserId')}>
              <option value="">None</option>
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
          {isEditing && onDelete && (
            <Button type="button" variant="danger" size="md" className="mr-auto" onClick={onDelete}>Delete Office</Button>
          )}
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
  const { drafts, discard: discardDraft } = useDraftList('office')
  // Reopen the form a draft came from; it restores the draft itself.
  const continueDraft = async (d) => {
    if (d.id === 'new') { setShowAdd(true); return }
    const record = offices.find((r) => String(r.id) === d.id)
    if (!record) { discardDraft(d.key); toast.show('That record no longer exists, so its draft was removed.', 'error'); return }
    setEditing(record)
  }

  // Draft rows use the table's columns: draft fields laid over the saved office (if editing).
  const draftRecord = (d) => {
    const base = d.id === 'new' ? {} : offices.find((o) => String(o.id) === d.id) || {}
    const sameHead = String(base.headUser?.id ?? '') === String(d.data.headUserId ?? '')
    return { officeName: d.data.officeName, head: sameHead ? (base.headUser?.fullName || base.headUser?.username) : (d.data.headUserId ? 'Changed. Open to review' : '') }
  }
  const draftColumns = [
    { className: 'px-4 py-3 align-top', render: (o) => <PrimaryCell title={o.officeName || 'No name yet'} /> },
    { className: 'px-4 py-3 align-top hidden sm:table-cell w-[40%]', render: (o) => <MutedCell>{o.head}</MutedCell> },
  ]
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
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  // A row opens the office's form (it only has a name and a head), which also holds Delete.
  const columns = [
    { key: 'name', label: 'Office', cell: (o, open) => <PrimaryCell title={o.officeName} open={open}
        extra={<p className="sm:hidden text-xs text-slate-600 dark:text-zinc-400 mt-0.5 truncate">{o.headUser ? `Head: ${o.headUser.fullName || o.headUser.username}` : 'No head assigned'}</p>} /> },
    { key: 'head', label: 'Head', className: 'hidden sm:table-cell w-[40%]', cell: (o) => <MutedCell>{o.headUser ? (o.headUser.fullName || o.headUser.username) : ''}</MutedCell> },
  ]

  return (
    <MainLayout>
      <div className="flex items-stretch gap-2 mb-4">
        <SearchBox value={search} onChange={setSearch} label="Search offices" placeholder="Search offices by name" />
        <Button size="md" className="whitespace-nowrap flex-shrink-0" onClick={() => setShowAdd(true)}>
          <Icon className="h-4 w-4 sm:mr-1.5">{ICON.plus}</Icon>
          <span className="sr-only sm:not-sr-only">Add Office</span>
        </Button>
      </div>

      <ListCard title={search.trim() ? 'Matching offices' : 'All offices'} count={filtered.length} noun="office" loading={loading}
        actions={<RefreshButton onClick={() => fetchOffices(debouncedSearch)} />}
        footer={!loading && <Pager page={page} pageSize={PAGE_SIZE} total={filtered.length} onPage={setPage} />}>
        {loading ? <ListSkeleton rows={5} /> : filtered.length === 0 && drafts.length === 0 ? (
          <ListEmpty>{search.trim() ? 'No offices match your search.' : 'No offices yet.'}</ListEmpty>
        ) : (
          <DataTable columns={columns} rows={paged} rowKey={(o) => o.id} onOpen={setEditing} wideEnd={drafts.length > 0}
            caption="Offices. Select an office to edit or delete it."
            leading={<DraftRows drafts={drafts} columns={draftColumns} toRecord={draftRecord} onContinue={continueDraft} onDiscard={discardDraft} />} />
        )}
      </ListCard>

      {showAdd  && <OfficeModal onClose={() => setShowAdd(false)} onSave={handleCreate} />}
      {editing  && <OfficeModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} onDelete={() => { setDeleting(editing); setEditing(null) }} />}
      {deleting && (
        <ConfirmDialog
          title="Delete this office?"
          message={`"${deleting.officeName}" will be removed. An office that still has assets can't be deleted.`}
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
