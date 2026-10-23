import { useState, useEffect, useCallback } from 'react'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import AlertDialog from '../../components/common/AlertDialog'
import Modal from '../../components/common/Modal'
import { getCategories, createCategory, updateCategory, deleteCategory } from '../../services/categoryService'
import { newIdempotencyKey } from '../../utils/idempotency'
import { useFormDraft, useDraftList } from '../../hooks/useFormDraft'
import DraftNotice from '../../components/common/DraftNotice'
import DraftRows from '../../components/common/DraftRows'
import { SearchBox, ListCard, RefreshButton, Pager, ListSkeleton, ListEmpty, DataTable, PrimaryCell, MutedCell, Icon, ICON } from '../../components/common/ListKit'

const PAGE_SIZE = 5

const lifeText = (years) => (years ? `${years} year${years === 1 ? '' : 's'}` : 'Not set')

const INPUT_CLASS ='w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

// onDelete (editing only) puts a Delete button in the form, since a row opens this form directly.
function CategoryModal({ onClose, onSave, onDelete, initial = null }) {
  const isEditing = !!initial
  const [form, setForm]     = useState({
    categoryName:    initial?.categoryName || '',
    description:     initial?.description || '',
    usefulLifeYears: initial?.usefulLifeYears != null ? String(initial.usefulLifeYears) : '',
  })
  const draft = useFormDraft(`category:${initial?.id ?? 'new'}`, form, setForm, {
    title: (f) => f.categoryName.trim() || initial?.categoryName || 'Untitled category',
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
    if (!form.categoryName.trim()) { setErrors({ categoryName: 'Category name is required.' }); return }
    const life = String(form.usefulLifeYears ?? '').trim()
    if (life && !(/^\d+$/.test(life) && +life >= 1 && +life <= 100)) {
      setErrors({ usefulLifeYears: 'Enter a whole number of years from 1 to 100, or leave it blank.' }); return
    }
    setSaving(true)
    try {
      await onSave({
        categoryName: form.categoryName.trim(),
        description: form.description.trim(),
        usefulLifeYears: life ? Number(life) : null,
      }, idempotencyKey)
      draft.clear()
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to save.' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title={isEditing ? 'Edit Category' : 'Add Category'} onClose={onClose}>
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        <DraftNotice draft={draft} />
        {errors._global && (
          <div className="text-sm text-red-700 dark:text-red-300 bg-red-500/10 border border-red-500/30 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Category Name<span className="text-red-400 ml-0.5">*</span></label>
          <input className={INPUT_CLASS} placeholder="e.g. Desktop Computer" value={form.categoryName} onChange={set('categoryName')} />
          {errors.categoryName && <p className="text-xs text-red-700 dark:text-red-300">{errors.categoryName}</p>}
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Description <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
          <textarea
            className={INPUT_CLASS + ' resize-none'}
            rows={3}
            placeholder="Brief description of this category…"
            value={form.description}
            onChange={set('description')}
          />
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="cat-life" className="text-sm font-medium text-slate-700 dark:text-zinc-300">Expected life <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
          <div className="flex items-center gap-2">
            <input id="cat-life" type="number" inputMode="numeric" min={1} max={100} step={1}
              className={INPUT_CLASS + ' max-w-[8rem]'} placeholder="e.g. 5" value={form.usefulLifeYears} onChange={set('usefulLifeYears')}
              aria-describedby="cat-life-hint" aria-invalid={!!errors.usefulLifeYears} />
            <span className="text-sm text-slate-700 dark:text-zinc-300">years</span>
          </div>
          <p id="cat-life-hint" className="text-xs text-slate-600 dark:text-zinc-400">
            How long assets in this category are expected to stay in service, counted from the date acquired. Each asset shows when its expected life ends, and the AI advice takes it into account.
          </p>
          {errors.usefulLifeYears && <p className="text-xs text-red-700 dark:text-red-300">{errors.usefulLifeYears}</p>}
        </div>
        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          {isEditing && onDelete && (
            <Button type="button" variant="danger" size="md" className="mr-auto" onClick={onDelete}>Delete Category</Button>
          )}
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : isEditing ? 'Save Changes' : 'Add Category'}</Button>
        </div>
      </form>
    </Modal>
  )
}

function Categories() {
  const toast = useToast()
  const [categories, setCategories] = useState([])
  const [loading, setLoading]       = useState(true)
  const [search, setSearch]         = useState('')
  const [showAdd, setShowAdd]       = useState(false)
  const [editing, setEditing]       = useState(null)
  const { drafts, discard: discardDraft } = useDraftList('category')
  // Reopen the form a draft came from; it restores the draft itself.
  const continueDraft = async (d) => {
    if (d.id === 'new') { setShowAdd(true); return }
    const record = categories.find((r) => String(r.id) === d.id)
    if (!record) { discardDraft(d.key); toast.show('That record no longer exists, so its draft was removed.', 'error'); return }
    setEditing(record)
  }

  // Draft rows use the table's columns.
  const draftRecord = (d) => d.data
  const draftColumns = [
    { className: 'px-4 py-3 align-top', render: (c) => <PrimaryCell title={c.categoryName || 'No name yet'} /> },
    { className: 'px-4 py-3 align-top hidden sm:table-cell w-[50%]', render: (c) => <MutedCell>{c.description}</MutedCell> },
    { className: 'px-4 py-3 align-top whitespace-nowrap', render: (c) => <MutedCell>{lifeText(c.usefulLifeYears)}</MutedCell> },
  ]
  const [deleting, setDeleting]     = useState(null)
  const [blockedDelete, setBlockedDelete] = useState(null)
  const [page, setPage]             = useState(1)

  const debouncedSearch = useDebounce(search, 300)

  const fetchCategories = useCallback(async (q = '') => {
    setLoading(true)
    try {
      const { data } = await getCategories(q)
      setCategories(data)
    } catch {
      toast.show('Failed to load categories.', 'error')
    } finally {
      setLoading(false)
    }
  }, [toast])

  useEffect(() => { fetchCategories(debouncedSearch) }, [debouncedSearch, fetchCategories])
  useEffect(() => { setPage(1) }, [debouncedSearch])

  const handleCreate = async (payload, idempotencyKey) => {
    const { data } = await createCategory(payload, idempotencyKey)
    setCategories((prev) => [...prev, data])
    toast.show('Category created.', 'success')
  }

  const handleUpdate = async (payload) => {
    const { data } = await updateCategory(editing.id, payload)
    setCategories((prev) => prev.map((c) => (c.id === data.id ? data : c)))
    toast.show('Category updated.', 'success')
  }

  const handleDelete = async () => {
    const target = deleting
    setDeleting(null)
    try {
      await deleteCategory(target.id)
      setCategories((prev) => prev.filter((c) => c.id !== target.id))
      toast.show('Category deleted.', 'warning')
    } catch (err) {
      if (err.response?.status === 409) {
        setBlockedDelete(err.response.data?.message || `"${target.categoryName}" has assets assigned to it and can't be deleted.`)
      } else {
        toast.show(err.response?.data?.message || 'Failed to delete category.', 'error')
      }
    }
  }

  const filtered = categories
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  // A row opens the category's form (name and description), which also holds Delete.
  const columns = [
    { key: 'name', label: 'Category', cell: (c, open) => <PrimaryCell title={c.categoryName} open={open}
        extra={c.description && <p className="sm:hidden text-xs text-slate-600 dark:text-zinc-400 mt-0.5 truncate">{c.description}</p>} /> },
    { key: 'desc', label: 'Description', className: 'hidden sm:table-cell w-[50%]', cell: (c) => <MutedCell>{c.description}</MutedCell> },
    { key: 'life', label: 'Expected life', className: 'whitespace-nowrap', cell: (c) => <MutedCell>{lifeText(c.usefulLifeYears)}</MutedCell> },
  ]

  return (
    <MainLayout>
      <div className="flex items-stretch gap-2 mb-4">
        <SearchBox value={search} onChange={setSearch} label="Search categories" placeholder="Search categories by name" />
        <Button size="md" className="whitespace-nowrap flex-shrink-0" onClick={() => setShowAdd(true)}>
          <Icon className="h-4 w-4 sm:mr-1.5">{ICON.plus}</Icon>
          <span className="sr-only sm:not-sr-only">Add Category</span>
        </Button>
      </div>

      <ListCard title={search.trim() ? 'Matching categories' : 'All categories'} count={filtered.length} noun="category" loading={loading}
        actions={<RefreshButton onClick={() => fetchCategories(debouncedSearch)} />}
        footer={!loading && <Pager page={page} pageSize={PAGE_SIZE} total={filtered.length} onPage={setPage} />}>
        {loading ? <ListSkeleton rows={5} /> : filtered.length === 0 && drafts.length === 0 ? (
          <ListEmpty>{search.trim() ? 'No categories match your search.' : 'No categories yet.'}</ListEmpty>
        ) : (
          <DataTable columns={columns} rows={paged} rowKey={(c) => c.id} onOpen={setEditing} wideEnd={drafts.length > 0}
            caption="Categories. Select a category to edit or delete it."
            leading={<DraftRows drafts={drafts} columns={draftColumns} toRecord={draftRecord} onContinue={continueDraft} onDiscard={discardDraft} />} />
        )}
      </ListCard>

      {showAdd  && <CategoryModal onClose={() => setShowAdd(false)} onSave={handleCreate} />}
      {editing  && <CategoryModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} onDelete={() => { setDeleting(editing); setEditing(null) }} />}
      {deleting && (
        <ConfirmDialog
          title="Delete this category?"
          message={`"${deleting.categoryName}" will be removed. A category that still has assets can't be deleted.`}
          confirmLabel="Delete Category"
          onConfirm={handleDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
      {blockedDelete && (
        <AlertDialog
          title="Can't delete this category"
          message={blockedDelete}
          onClose={() => setBlockedDelete(null)}
        />
      )}
    </MainLayout>
  )
}

export default Categories
