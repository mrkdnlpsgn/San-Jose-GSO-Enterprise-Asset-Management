import { useState, useEffect, useCallback } from 'react'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import AlertDialog from '../../components/common/AlertDialog'
import Modal from '../../components/common/Modal'
import { getOffices, createOffice, updateOffice, deleteOffice } from '../../services/officeService'
import { newIdempotencyKey } from '../../utils/idempotency'
import { useFormDraft, useDraftList } from '../../hooks/useFormDraft'
import DraftNotice from '../../components/common/DraftNotice'
import DraftRows from '../../components/common/DraftRows'
import PropertyNumberPanel from '../../components/common/PropertyNumberPanel'
import { SearchBox, ListCard, RefreshButton, LazyFooter, useLazyRows, ListSkeleton, ListEmpty, DataTable, PrimaryCell, MutedCell, Icon, ICON } from '../../components/common/ListKit'


const INPUT_CLASS ='w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

// onDelete (editing only) puts a Delete button in the form, since a row opens this form directly.
function OfficeModal({ onClose, onSave, onDelete, initial = null }) {
  const isEditing = !!initial
  const [form, setForm]     = useState({ officeName: initial?.officeName || '', propertyCode: initial?.propertyCode || '' })
  const draft = useFormDraft(`office:${initial?.id ?? 'new'}`, form, setForm, {
    title: (f) => f.officeName.trim() || initial?.officeName || 'Untitled office',
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
    if (!form.officeName.trim()) { setErrors({ officeName: 'Office name is required.' }); return }
    const code = form.propertyCode.trim()
    if (code && !/^[A-Za-z0-9]{1,10}$/.test(code)) { setErrors({ propertyCode: 'Use letters and numbers only, up to 10.' }); return }
    setSaving(true)
    try {
      const payload = {
        officeName: form.officeName.trim(),
        // Head is no longer set from this form; keep whatever the office already has.
        headUserId: initial?.headUser?.id ?? null,
        propertyCode: code,
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
          <label htmlFor="pn-code" className="text-sm font-medium text-slate-700 dark:text-zinc-300">Property number code</label>
          <input id="pn-code" className={INPUT_CLASS + ' max-w-[10rem] font-mono'} placeholder="e.g. 1061" maxLength={10}
            value={form.propertyCode} onChange={set('propertyCode')} aria-describedby="pn-code-hint" aria-invalid={!!errors.propertyCode} />
          <p id="pn-code-hint" className="text-xs text-slate-600 dark:text-zinc-400">
            The office part of property numbers (YEAR-MONTH-CATEGORY-SERIAL-OFFICE). Letters and numbers only. Changing it doesn&apos;t change numbers already given.
          </p>
          {errors.propertyCode && <p className="text-xs text-red-700 dark:text-red-300">{errors.propertyCode}</p>}
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
    return { officeName: d.data.officeName, propertyCode: d.data.propertyCode }
  }
  const draftColumns = [
    { className: 'px-4 py-3 align-top', render: (o) => <PrimaryCell title={o.officeName || 'No name yet'} /> },
    { className: 'px-4 py-3 align-top whitespace-nowrap w-[8rem]', render: (o) => <MutedCell>{o.propertyCode}</MutedCell> },
  ]
  const [deleting, setDeleting] = useState(null)
  const [blockedDelete, setBlockedDelete] = useState(null)
  const lazy = useLazyRows()

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
  useEffect(() => { lazy.reset() }, [debouncedSearch])

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
  const paged = filtered.slice(0, lazy.shown)

  // A row opens the office's form (it only has a name), which also holds Delete.
  const columns = [
    { key: 'name', label: 'Office', cell: (o, open) => <PrimaryCell title={o.officeName} open={open} /> },
    { key: 'code', label: 'Code', className: 'whitespace-nowrap w-[8rem]', cell: (o) => o.propertyCode
        ? <span className="font-mono text-sm text-slate-800 dark:text-zinc-200">{o.propertyCode}</span>
        : <span className="text-sm italic text-amber-800 dark:text-amber-300">Not set</span> },
  ]

  return (
    <MainLayout>
      <PropertyNumberPanel refreshKey={offices} />
      <div className="flex items-stretch gap-2 mb-4">
        <SearchBox value={search} onChange={setSearch} label="Search offices" placeholder="Search offices by name" />
        <Button size="md" className="whitespace-nowrap flex-shrink-0" onClick={() => setShowAdd(true)}>
          <Icon className="h-4 w-4 sm:mr-1.5">{ICON.plus}</Icon>
          <span className="sr-only sm:not-sr-only">Add Office</span>
        </Button>
      </div>

      <ListCard title={search.trim() ? 'Matching offices' : 'All offices'} count={filtered.length} noun="office" loading={loading}
        actions={<RefreshButton onClick={() => fetchOffices(debouncedSearch)} />}
        footer={!loading && <LazyFooter lazy={lazy} total={filtered.length} />}>
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
