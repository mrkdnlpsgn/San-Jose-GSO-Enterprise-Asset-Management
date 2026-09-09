import { useState, useEffect, useCallback, useMemo } from 'react'
import { useToast } from '../../context/ToastContext'
import MainLayout from '../../components/layout/MainLayout'
import Button from '../../components/common/Button'
import Modal from '../../components/common/Modal'
import { getAssetHistory, createAssetHistory } from '../../services/assetHistoryService'
import { getAssets } from '../../services/assetService'
import { getUsers } from '../../services/userService'
import { getOffices } from '../../services/officeService'
import { useDebounce } from '../../hooks/useDebounce'
import { useAuth } from '../../hooks/useAuth'

const EVENT_TYPES = ['REGISTERED', 'ASSIGNED', 'TRANSFERRED', 'MAINTENANCE', 'DISPOSAL', 'ARCHIVED']

const EVENT_BADGE = {
  REGISTERED:  'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  ASSIGNED:    'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  TRANSFERRED: 'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
  MAINTENANCE: 'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  DISPOSAL:    'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
  ARCHIVED:    'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20',
}

function formatDate(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}

const INPUT_CLASS = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

function LogEventModal({ onClose, onSave, assets, users, offices }) {
  const { user } = useAuth()
  const [form, setForm]     = useState({ assetId: '', eventType: 'ASSIGNED', fromOfficeId: '', toOfficeId: '', performedById: user?.id ? String(user.id) : '', notes: '' })
  const [errors, setErrors] = useState({})
  const [saving, setSaving] = useState(false)

  const set = (key) => (e) => {
    setForm((p) => ({ ...p, [key]: e.target.value }))
    setErrors((p) => { const n = { ...p }; delete n[key]; return n })
  }

  const handleAssetChange = (e) => {
    const selectedId = e.target.value
    const selected = assets.find((a) => String(a.id) === selectedId)
    setForm((p) => ({
      ...p,
      assetId: selectedId,
      fromOfficeId: selected?.office?.id ? String(selected.office.id) : '',
    }))
    setErrors((p) => { const n = { ...p }; delete n.assetId; return n })
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const errs = {}
    if (!form.assetId) errs.assetId = 'Asset is required.'
    if (!form.eventType) errs.eventType = 'Event type is required.'
    if (Object.keys(errs).length) { setErrors(errs); return }
    setSaving(true)
    try {
      const payload = {
        assetId: Number(form.assetId),
        eventType: form.eventType,
        fromOfficeId: form.fromOfficeId ? Number(form.fromOfficeId) : null,
        toOfficeId: form.toOfficeId ? Number(form.toOfficeId) : null,
        performedById: form.performedById ? Number(form.performedById) : null,
        notes: form.notes.trim() || null,
      }
      await onSave(payload)
      onClose()
    } catch (err) {
      setErrors({ _global: err.response?.data?.message || 'Failed to log event.' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title="Log Asset Event" onClose={onClose}>
      <form onSubmit={handleSubmit} noValidate className="space-y-4">
        {errors._global && (
          <div className="text-sm text-red-400 bg-red-950/50 border border-red-800 rounded-lg px-4 py-2.5">{errors._global}</div>
        )}

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Asset<span className="text-red-400 ml-0.5">*</span></label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.assetId} onChange={handleAssetChange}>
              <option value="">— Select asset —</option>
              {assets.map((a) => (
                <option key={a.id} value={String(a.id)}>{a.propertyNumber} — {a.description}</option>
              ))}
            </select>
            <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
            </div>
          </div>
          {errors.assetId && <p className="text-xs text-red-400">{errors.assetId}</p>}
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Event Type<span className="text-red-400 ml-0.5">*</span></label>
          <div className="relative">
            <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.eventType} onChange={set('eventType')}>
              {EVENT_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
            <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">From Office</label>
            <div className={INPUT_CLASS + ' bg-slate-50 dark:bg-zinc-800/50 text-slate-500 dark:text-zinc-400 cursor-not-allowed select-none'}>
              {offices.find((o) => String(o.id) === form.fromOfficeId)?.officeName || '— Auto-filled from asset —'}
            </div>
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">To Office</label>
            <div className="relative">
              <select className={INPUT_CLASS + ' appearance-none pr-9'} value={form.toOfficeId} onChange={set('toOfficeId')}>
                <option value="">— None —</option>
                {offices.map((o) => <option key={o.id} value={String(o.id)}>{o.officeName}</option>)}
              </select>
              <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-slate-400">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
              </div>
            </div>
          </div>
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Performed By</label>
          <div className={INPUT_CLASS + ' bg-slate-50 dark:bg-zinc-800/50 text-slate-500 dark:text-zinc-400 cursor-not-allowed select-none'}>
            {user?.fullName || user?.username || '—'}
          </div>
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium text-slate-700 dark:text-zinc-300">Notes</label>
          <textarea className={INPUT_CLASS + ' resize-none'} rows={3} placeholder="Optional notes…" value={form.notes} onChange={set('notes')} />
        </div>

        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-zinc-800">
          <Button type="button" variant="secondary" size="md" onClick={onClose}>Cancel</Button>
          <Button type="submit" size="md" disabled={saving}>{saving ? 'Saving…' : 'Log Event'}</Button>
        </div>
      </form>
    </Modal>
  )
}

const PAGE_SIZE = 10

function AssetHistory() {
  const toast = useToast()
  const [history, setHistory]     = useState([])
  const [loading, setLoading]     = useState(true)
  const [assets, setAssets]       = useState([])
  const [users, setUsers]         = useState([])
  const [offices, setOffices]     = useState([])
  const [search, setSearch]       = useState('')
  const [filterType, setFilterType] = useState('')
  const [dateFilter, setDateFilter] = useState('all')
  const [showAdd, setShowAdd]     = useState(false)
  const [viewing, setViewing]     = useState(null)
  const [page, setPage]           = useState(1)

  const debouncedSearch = useDebounce(search, 300)

  const fetchHistory = useCallback(async (q = '') => {
    setLoading(true)
    try {
      const { data } = await getAssetHistory(q)
      setHistory(data)
    } catch {
      toast.show('Failed to load asset history.', 'error')
    } finally {
      setLoading(false)
    }
  }, [toast])

  const load = useCallback(() => {
    Promise.all([
      getAssets().catch(() => ({ data: [] })),
      getUsers().catch(() => ({ data: [] })),
      getOffices().catch(() => ({ data: [] })),
    ]).then(([assetRes, userRes, officeRes]) => {
      setAssets(assetRes.data); setUsers(userRes.data); setOffices(officeRes.data)
    })
    fetchHistory(search)
  }, [fetchHistory, search]) // eslint-disable-line

  useEffect(() => {
    Promise.all([
      getAssets().catch(() => ({ data: [] })),
      getUsers().catch(() => ({ data: [] })),
      getOffices().catch(() => ({ data: [] })),
    ]).then(([assetRes, userRes, officeRes]) => {
      setAssets(assetRes.data); setUsers(userRes.data); setOffices(officeRes.data)
    })
  }, [])

  useEffect(() => { fetchHistory(debouncedSearch) }, [debouncedSearch, fetchHistory])
  useEffect(() => { setPage(1) }, [debouncedSearch, filterType, dateFilter])

  const handleLogEvent = async (payload) => {
    const { data } = await createAssetHistory(payload)
    setHistory((prev) => [data, ...prev])
    toast.show('Event logged.', 'success')
  }

  const now = Date.now()
  const filtered = useMemo(() => {
    return history.filter((h) => {
      if (filterType && h.eventType !== filterType) return false
      if (dateFilter === 'today') {
        const d = new Date(h.eventDate || h.createdAt)
        const today = new Date(); today.setHours(0,0,0,0)
        if (d < today) return false
      } else if (dateFilter === '7d') {
        if (now - new Date(h.eventDate || h.createdAt).getTime() > 7 * 86400000) return false
      } else if (dateFilter === '30d') {
        if (now - new Date(h.eventDate || h.createdAt).getTime() > 30 * 86400000) return false
      }
      return true
    })
  }, [history, filterType, dateFilter, now])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paged = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  return (
    <MainLayout>
      <div className="flex flex-col gap-3 mb-5">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
          <div className="relative w-full sm:max-w-xs">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
            </svg>
            <input type="text" placeholder="Search asset, event type, person…" value={search} onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
          </div>
          <Button size="md" className="self-start sm:self-auto" onClick={() => setShowAdd(true)}>
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />
            </svg>
            Log Event
          </Button>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative">
            <select value={filterType} onChange={(e) => setFilterType(e.target.value)}
              className="appearance-none text-sm rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-700 dark:text-zinc-200 px-3 py-2 pr-8 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all">
              <option value="">All Event Types</option>
              {EVENT_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
            <div className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 dark:text-zinc-500">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
            </div>
          </div>
          {['all', 'today', '7d', '30d'].map((d) => (
            <button key={d} onClick={() => setDateFilter(d)}
              className={`text-xs px-2.5 py-1.5 rounded-lg border font-medium transition-all ${
                dateFilter === d
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-zinc-900 border-slate-900 dark:border-white'
                  : 'border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800'
              }`}>
              {d === 'all' ? 'All time' : d === 'today' ? 'Today' : d === '7d' ? 'Last 7 days' : 'Last 30 days'}
            </button>
          ))}
        </div>
      </div>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
        <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center gap-3">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Asset History</p>
          {!loading && (
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400 bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full">
              {filtered.length}{filtered.length !== history.length ? ` of ${history.length}` : ''} entr{filtered.length !== 1 ? 'ies' : 'y'}
            </span>
          )}
        </div>

        {loading ? (
          <div className="divide-y divide-slate-100 dark:divide-zinc-800">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="flex items-center gap-4 px-5 py-3.5">
                <div className="animate-pulse h-3 w-32 rounded bg-slate-200 dark:bg-zinc-800" />
                <div className="animate-pulse h-5 w-20 rounded-full bg-slate-200 dark:bg-zinc-800" />
                <div className="animate-pulse h-3 w-24 rounded bg-slate-200 dark:bg-zinc-800 ml-auto" />
              </div>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-2 text-zinc-600">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-10 w-10 mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            <p className="text-sm text-zinc-500">{history.length === 0 ? 'No history recorded yet.' : 'No entries match your filters.'}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
              <thead>
                <tr>
                  {['Asset', 'Event Type', 'From Office', 'To Office', 'Performed By', 'Date', 'Notes'].map((h) => (
                    <th key={h} className="px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
                {paged.map((h) => (
                  <tr key={h.id} onClick={() => setViewing(h)}
                    className="cursor-pointer hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                    <td className="px-5 py-3.5">
                      <p className="font-mono text-xs text-slate-500 dark:text-zinc-400">{h.asset?.propertyNumber}</p>
                      <p className="text-sm font-medium text-slate-900 dark:text-white truncate max-w-[160px]">{h.asset?.description}</p>
                    </td>
                    <td className="px-5 py-3.5 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${EVENT_BADGE[h.eventType] || 'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20'}`}>
                        {h.eventType}
                      </span>
                    </td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{h.fromOffice?.officeName || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{h.toOffice?.officeName || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{h.performedBy?.fullName || h.performedBy?.username || '—'}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{formatDate(h.eventDate || h.createdAt)}</td>
                    <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs max-w-[160px]">
                      <span className="block truncate" title={h.notes}>{h.notes || '—'}</span>
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
                className="px-2.5 py-1.5 text-xs rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">
                Prev
              </button>
              <span className="text-xs text-slate-400 px-2">{page} / {totalPages}</span>
              <button onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                className="px-2.5 py-1.5 text-xs rounded-md border border-slate-200 dark:border-zinc-700 text-slate-500 dark:text-zinc-400 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">
                Next
              </button>
            </div>
          </div>
        )}
      </div>

      {showAdd && (
        <LogEventModal
          onClose={() => setShowAdd(false)}
          onSave={handleLogEvent}
          assets={assets}
          users={users}
          offices={offices}
        />
      )}

      {viewing && (
        <Modal title="Event Details" subtitle={viewing.asset?.propertyNumber} onClose={() => setViewing(null)} size="md">
          <div className="space-y-0">
            <Field label="Asset" value={viewing.asset?.description} />
            <Field label="Event Type" value={
              <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${EVENT_BADGE[viewing.eventType] || 'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20'}`}>
                {viewing.eventType}
              </span>
            } />
            <Field label="From Office" value={viewing.fromOffice?.officeName} />
            <Field label="To Office" value={viewing.toOffice?.officeName} />
            <Field label="Performed By" value={viewing.performedBy?.fullName || viewing.performedBy?.username} />
            <Field label="Date" value={formatDate(viewing.eventDate || viewing.createdAt)} />
            <Field label="Notes" value={viewing.notes} />
          </div>
        </Modal>
      )}
    </MainLayout>
  )
}

function Field({ label, value }) {
  return (
    <div className="flex items-start gap-2 py-2.5 border-b border-slate-100 dark:border-zinc-800/60 last:border-0">
      <span className="text-xs text-slate-400 dark:text-zinc-500 w-28 flex-shrink-0 pt-0.5">{label}</span>
      <span className="text-sm text-slate-900 dark:text-zinc-200 font-medium break-words">{value ?? '—'}</span>
    </div>
  )
}

export default AssetHistory
