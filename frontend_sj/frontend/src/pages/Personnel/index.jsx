import { useState, useEffect, useCallback, useMemo } from 'react'
import { useToast } from '../../context/ToastContext'
import { useDebounce } from '../../hooks/useDebounce'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import Modal from '../../components/common/Modal'
import { getPersonnel, updatePersonnel, personOffices } from '../../services/personnelService'
import { getOffices } from '../../services/officeService'
import { useFormDraft, useDraftList } from '../../hooks/useFormDraft'
import DraftNotice from '../../components/common/DraftNotice'
import DraftRows from '../../components/common/DraftRows'
import { SearchBox, FilterBar, FilterToggle, ListCard, RefreshButton, Pager, ListSkeleton, ListEmpty, DataTable, PrimaryCell, MutedCell, StatusBadge } from '../../components/common/ListKit'

const PAGE_SIZE = 25

const INPUT_CLASS ='w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

const officeNames = (p) => personOffices(p).map((o) => o.officeName).join(', ')

// Personnel are the accounts — each is created on the Accounts page. This is the only
// place an admin assigns an account's offices (one or more); name and role come from the account.
function PersonnelModal({ onClose, onSave, initial, offices = [] }) {
  const [form, setForm]     = useState({
    position:    initial.position || '',
    officeIds:   personOffices(initial).map((o) => String(o.id)),
    contactInfo: initial.contactInfo || '',
  })
  // drafts saved before multiple offices were allowed carry a single officeId
  const selected = form.officeIds || (form.officeId ? [String(form.officeId)] : [])
  const [officeFilter, setOfficeFilter] = useState('')
  const toggleOffice = (id) => {
    setForm((p) => {
      const cur = p.officeIds || (p.officeId ? [String(p.officeId)] : [])
      return { ...p, officeIds: cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id] }
    })
    setErrors((p) => { const n = { ...p }; delete n.officeId; return n })
  }
  const shownOffices = offices.filter((o) => !officeFilter.trim() || o.officeName.toLowerCase().includes(officeFilter.trim().toLowerCase()))
  const draft = useFormDraft(`personnel:${initial?.id}`, form, setForm, { title: initial.fullName })
  const [errors, setErrors] = useState({})
  const [saving, setSaving] = useState(false)

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!selected.length) { setErrors({ officeId: 'Choose at least one office.' }); return }
    setSaving(true)
    try {
      // the primary office (shown first) stays the same unless it was unchecked
      const primary = selected.includes(String(initial.office?.id)) ? String(initial.office.id) : selected[0]
      await onSave({
        officeId:    Number(primary),
        officeIds:   [primary, ...selected.filter((x) => x !== primary)].map(Number),
        position:    form.position.trim() || null,
        contactInfo: form.contactInfo.trim() || null,
      })
      draft.clear()
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to save.' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title="Assign Offices" subtitle={`${initial.fullName} · @${initial.username}`} onClose={onClose}>
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        <DraftNotice draft={draft} />
        {errors._global && (
          <div className="text-sm text-red-700 dark:text-red-300 bg-red-500/10 border border-red-500/30 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}
        <div className="flex flex-col gap-1.5">
          <div className="flex items-baseline justify-between gap-2">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Offices<span className="text-red-400 ml-0.5">*</span></label>
            <span className="text-xs text-slate-600 dark:text-zinc-400">{selected.length} selected</span>
          </div>
          {offices.length > 8 && (
            <input className={INPUT_CLASS} placeholder="Filter offices…" value={officeFilter} onChange={(e) => setOfficeFilter(e.target.value)} autoFocus />
          )}
          <div className="max-h-56 overflow-y-auto rounded-md border border-slate-200 dark:border-zinc-700 divide-y divide-slate-100 dark:divide-zinc-800">
            {shownOffices.length === 0 && <p className="px-3.5 py-2.5 text-xs text-slate-600 dark:text-zinc-400">No offices match.</p>}
            {shownOffices.map((o) => {
              const id = String(o.id)
              return (
                <label key={o.id} className="flex items-center gap-2.5 px-3.5 py-2 text-sm cursor-pointer hover:bg-slate-50 dark:hover:bg-zinc-800/60 text-slate-700 dark:text-zinc-200">
                  <input type="checkbox" className="h-4 w-4 rounded border-slate-300 dark:border-zinc-600 text-brand-600 focus:ring-brand-500"
                    checked={selected.includes(id)} onChange={() => toggleOffice(id)} />
                  <span className="flex-1">{o.officeName}</span>
                  {selected[0] === id && selected.length > 1 && String(initial.office?.id) === id && (
                    <span className="text-xs font-semibold uppercase tracking-wider text-slate-600 dark:text-zinc-400">Primary</span>
                  )}
                </label>
              )
            })}
          </div>
          {errors.officeId && <p className="text-xs text-red-700 dark:text-red-300">{errors.officeId}</p>}
          <p className="text-xs text-slate-600 dark:text-zinc-400">Staff see and manage the assets they're accountable for in every office checked.</p>
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Position <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
          <input className={INPUT_CLASS} placeholder="e.g. Administrative Aide IV" value={form.position} onChange={set('position')} />
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Contact Info <span className="text-slate-600 dark:text-zinc-400 font-normal">(optional)</span></label>
          <input className={INPUT_CLASS} placeholder="Phone or email" value={form.contactInfo} onChange={set('contactInfo')} />
        </div>
        <p className="text-xs text-slate-600 dark:text-zinc-400">Name and role are managed on the Accounts page.</p>
        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : 'Save'}</Button>
        </div>
      </form>
    </Modal>
  )
}

const roleBadge = (p) => (<>
  {p.userRole && <StatusBadge tone={p.userRole === 'ADMIN' ? 'green' : 'slate'}>{p.userRole === 'ADMIN' ? 'Administrator' : 'GSO Staff'}</StatusBadge>}
  {p.userActive === false && <StatusBadge tone="red">Inactive</StatusBadge>}
</>)
const officeText = (p) => p.officeName ?? officeNames(p)
const NOT_ASSIGNED = <span className="italic text-amber-800 dark:text-amber-300">Not assigned</span>

// A row opens the person's "Assign Offices" form — the one thing this page changes.
const COLUMNS = [
  { key: 'name', label: 'Person', cell: (p, open) => (
    <PrimaryCell code={`@${p.username}`} title={p.fullName} open={open}
      extra={<p className="sm:hidden text-xs mt-0.5 truncate">{officeText(p) ? <span className="text-slate-600 dark:text-zinc-400">{officeText(p)}</span> : NOT_ASSIGNED}</p>} />
  ) },
  { key: 'role', label: 'Role', className: 'hidden md:table-cell w-[11rem]', cell: (p) => <div className="flex flex-wrap gap-1">{roleBadge(p)}</div> },
  { key: 'office', label: 'Office', className: 'hidden sm:table-cell w-[34%]', cell: (p) => (
    officeText(p) ? <MutedCell>{officeText(p)}</MutedCell> : <p className="text-sm">{NOT_ASSIGNED}</p>
  ) },
  { key: 'contact', label: 'Contact', className: 'hidden lg:table-cell w-[16%]', cell: (p) => <MutedCell>{p.contactInfo}</MutedCell> },
]

function Personnel() {
  const toast = useToast()
  const [personnel, setPersonnel]   = useState([])
  const [offices, setOffices]       = useState([])
  const [loading, setLoading]       = useState(true)
  const [search, setSearch]         = useState('')
  const [editing, setEditing]       = useState(null)
  const { drafts, discard: discardDraft } = useDraftList('personnel')
  // Reopen the form a draft came from; it restores the draft itself.
  const continueDraft = async (d) => {
    const record = personnel.find((r) => String(r.id) === d.id)
    if (!record) { discardDraft(d.key); toast.show('That record no longer exists, so its draft was removed.', 'error'); return }
    setEditing(record)
  }

  // Draft rows use the table's columns: draft fields laid over the saved person.
  const draftRecord = (d) => {
    const base = personnel.find((x) => String(x.id) === d.id) || {}
    const ids = d.data.officeIds || (d.data.officeId ? [String(d.data.officeId)] : [])
    return { ...base, contactInfo: d.data.contactInfo, officeName: offices.filter((o) => ids.includes(String(o.id))).map((o) => o.officeName).join(', ') }
  }
  const draftColumns = COLUMNS.map((c) => ({ className: `px-4 py-3 align-top ${c.className || ''}`, render: (p) => c.cell(p) }))
  const [page, setPage]             = useState(1)
  const [needsOffice, setNeedsOffice] = useState(false)

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
  useEffect(() => { setPage(1) }, [debouncedSearch, needsOffice])
  useEffect(() => { getOffices().then(({ data }) => setOffices(data)).catch(() => {}) }, [])

  const handleUpdate = async (payload) => {
    const { data } = await updatePersonnel(editing.id, payload)
    setPersonnel((prev) => prev.map((p) => (p.id === data.id ? data : p)))
    toast.show(`${data.fullName} assigned to ${officeNames(data)}.`, 'success')
  }

  const unassigned = (p) => !p.office && p.userActive !== false
  const unassignedCount = personnel.filter(unassigned).length
  const filtered = useMemo(() => (needsOffice ? personnel.filter(unassigned) : personnel), [personnel, needsOffice])
  const activeFilters = [search.trim(), needsOffice].filter(Boolean).length
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  return (
    <MainLayout>
      <div className="flex flex-col gap-2.5 mb-4">
        <div className="flex items-center gap-2">
          <SearchBox value={search} onChange={setSearch} label="Search personnel" placeholder="Search by name, username or office" />
        </div>
        {(unassignedCount > 0 || activeFilters > 0) && (
          <FilterBar activeCount={activeFilters} onClear={() => { setSearch(''); setNeedsOffice(false) }}>
            {unassignedCount > 0 && (
              <FilterToggle on={needsOffice} onChange={setNeedsOffice}>Needs an office ({unassignedCount})</FilterToggle>
            )}
          </FilterBar>
        )}
      </div>

      <ListCard title={activeFilters > 0 ? 'Matching personnel' : 'All personnel'} filtered={filtered.length !== personnel.length}
        count={filtered.length} total={personnel.length} noun="person" loading={loading}
        actions={<RefreshButton onClick={() => fetchPersonnel(debouncedSearch)} />}
        footer={!loading && <Pager page={page} pageSize={PAGE_SIZE} total={filtered.length} onPage={setPage} />}>
        {loading ? <ListSkeleton rows={5} /> : filtered.length === 0 && drafts.length === 0 ? (
          <ListEmpty>{activeFilters > 0 ? 'No personnel match your search.' : 'No accounts yet — create one on the Accounts page.'}</ListEmpty>
        ) : (
          <DataTable columns={COLUMNS} rows={paged} rowKey={(p) => p.id} onOpen={setEditing} wideEnd={drafts.length > 0}
            caption="Personnel. Select a person to assign their offices."
            leading={<DraftRows drafts={drafts} columns={draftColumns} toRecord={draftRecord} onContinue={continueDraft} onDiscard={discardDraft} />} />
        )}
      </ListCard>

      {editing  && <PersonnelModal initial={editing} onClose={() => setEditing(null)} onSave={handleUpdate} offices={offices} />}
    </MainLayout>
  )
}

export default Personnel
