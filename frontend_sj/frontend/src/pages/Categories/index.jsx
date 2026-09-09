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

const PAGE_SIZE = 8

const INPUT_CLASS ='w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

function CategoryModal({ onClose, onSave, initial = null }) {
  const isEditing = !!initial
  const [form, setForm]     = useState({ categoryName: initial?.categoryName || '', description: initial?.description || '' })
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
    setSaving(true)
    try {
      await onSave({ categoryName: form.categoryName.trim(), description: form.description.trim() }, idempotencyKey)
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
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Category Name<span className="text-red-400 ml-0.5">*</span></label>
          <input className={INPUT_CLASS} placeholder="e.g. Desktop Computer" value={form.categoryName} onChange={set('categoryName')} />
          {errors.categoryName && <p className="text-xs text-red-400">{errors.categoryName}</p>}
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Description <span className="text-slate-400 font-normal">(optional)</span></label>
          <textarea
            className={INPUT_CLASS + ' resize-none'}
            rows={3}
            placeholder="Brief description of this category…"
            value={form.description}
            onChange={set('description')}
          />
        </div>
        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
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
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  return (
    <MainLayout>
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5">
        <div className="relative w-full sm:max-w-xs">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
          </svg>
          <input type="text" placeholder="Search categories…" value={search} onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
        </div>
        <Button size="md" className="self-start sm:self-auto" onClick={() => setShowAdd(true)}>
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
          </svg>
          Add Category
        </Button>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">All Categories</p>
          {!loading && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {filtered.length} categor{filtered.length !== 1 ? 'ies' : 'y'}
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
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
            </svg>
            <p className="text-sm text-zinc-400 font-medium">{categories.length === 0 ? 'No categories yet' : 'No categories match your search'}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Category Name', 'Description', 'Actions'].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((cat) => (
                  <tr key={cat.id} className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                    <td className="px-5 py-3.5 font-medium text-slate-900 dark:text-white whitespace-nowrap">{cat.categoryName}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs max-w-xs">
                      <span className="block truncate">{cat.description || '—'}</span>
                    </td>
                    <td className="px-5 py-3.5">
                      <div className="flex items-center justify-end gap-1">
                        <button onClick={() => setEditing(cat)} title="Edit"
                          className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150">
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                            <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                          </svg>
                        </button>
                        <button onClick={() => setDeleting(cat)} title="Delete"
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

      {showAdd  && <CategoryModal onClose={() => setShowAdd(false)} onSave={handleCreate} />}
      {editing  && <CategoryModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} />}
      {deleting && (
        <ConfirmDialog
          title="Delete this category?"
          message={`"${deleting.categoryName}" will be permanently removed.`}
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
