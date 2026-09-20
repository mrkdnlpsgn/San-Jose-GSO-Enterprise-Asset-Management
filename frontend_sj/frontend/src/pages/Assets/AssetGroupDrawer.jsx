import { useState, useEffect, useMemo } from 'react'
import api from '../../services/api'
import Modal from '../../components/common/Modal'
import { getAssetHistory } from '../../services/assetHistoryService'
import GroupDevicesTable from './GroupDevicesTable'
import { getLatestRecommendation, generateRecommendation } from '../../services/aiRecommendationService'

// Drawer for a group of same-model devices (assets that were added together and share
// a groupId). Every device is still its own complete asset; this is the roll-up view:
//   Details   — an overview of the group, and a "View Devices" button that opens every device in a searchable table
//   Lifecycle — every device's events together, filterable by device and by lifecycle type
//   AI Insight — each device's AI lifecycle recommendation, with generate / regenerate per device

const TAB_LABELS = { details: 'Details', history: 'Lifecycle', ai: 'AI Insight' }

const RECOMMENDATION_BADGE = {
  MAINTAIN:            'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  MONITOR:             'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  REPAIR:              'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  REVIEW_FOR_DISPOSAL: 'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
  BUDGET_PRIORITY:     'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
}

const CONDITION_BADGE = {
  SERVICEABLE:   'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  REPAIRABLE:    'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  UNSERVICEABLE: 'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
}
const LIFECYCLE_BADGE = {
  REGISTERED:        'bg-blue-500/10 text-blue-400 ring-1 ring-blue-500/20',
  ASSIGNED:          'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  TRANSFERRED:       'bg-orange-500/10 text-orange-400 ring-1 ring-orange-500/20',
  UNDER_MAINTENANCE: 'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  DISPOSED:          'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
  ARCHIVED:          'bg-zinc-500/10 text-zinc-400 ring-1 ring-zinc-500/20',
}

const SELECT_CLASS = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 px-2.5 py-2 text-xs bg-white dark:bg-zinc-800 text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500'

function fmt(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}
function php(v) {
  if (v == null) return '—'
  return '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 })
}

export default function AssetGroupDrawer({ members, exiting, onClose, renderDeviceRow }) {
  const [tab, setTab] = useState('details')
  const [showDevices, setShowDevices] = useState(false)
  const [events, setEvents] = useState(null) // null = not loaded yet
  const [loadError, setLoadError] = useState(false)
  const [deviceFilter, setDeviceFilter] = useState('')
  const [typeFilter, setTypeFilter] = useState('')
  // AI Insight tab: latest recommendation per device (undefined = not loaded, null = none yet)
  const [recs, setRecs] = useState({})
  const [aiDevice, setAiDevice] = useState('')
  const [generating, setGenerating] = useState({})
  const [aiError, setAiError] = useState('')

  const first = members[0]
  const idIndex = useMemo(() => new Map(members.map((m, i) => [m.id, i])), [members])
  const deviceName = (i) => `Device ${i + 1} · ${members[i]?.propertyNumber ?? ''}`

  // Lifecycle data comes from three bulk endpoints (filtered down to this group's devices)
  // rather than three requests per device, and only once the tab is opened.
  const memberKey = members.map((m) => m.id).join(',')
  useEffect(() => {
    if (tab !== 'history') return undefined
    let cancelled = false
    const all = { params: { size: 100000 } }
    Promise.all([
      getAssetHistory().then((r) => r.data).catch(() => { throw new Error('history') }),
      api.get('/maintenance', all).then((r) => r.data).catch(() => []),
      api.get('/disposal', all).then((r) => r.data).catch(() => []),
    ]).then(([history, maintenance, disposal]) => {
      if (cancelled) return
      const items = []
      history.forEach((h) => {
        const i = idIndex.get(h.asset?.id)
        if (i === undefined) return
        items.push({
          id: `h-${h.id}`, device: i, type: 'history', kind: String(h.eventType || '').toUpperCase(),
          title: h.eventType, date: h.eventDate, sortKey: h.eventDate,
          meta: `By: ${h.performedBy?.fullName || h.performedBy?.username || '—'}`, note: h.notes,
        })
      })
      maintenance.forEach((m) => {
        const i = idIndex.get(m.asset?.id)
        if (i === undefined) return
        items.push({
          id: `m-${m.id}`, device: i, type: 'maintenance', kind: 'MAINTENANCE',
          title: m.maintenanceType, status: m.status, date: m.maintenanceDate,
          sortKey: m.updatedAt || m.createdAt || m.maintenanceDate, note: m.findings, cost: m.cost,
        })
      })
      disposal.forEach((d) => {
        const i = idIndex.get(d.asset?.id)
        if (i === undefined) return
        items.push({
          id: `d-${d.id}`, device: i, type: 'disposal', kind: 'DISPOSAL',
          title: d.recommendedMethod, status: d.disposalStatus, date: d.inspectionDate,
          sortKey: d.updatedAt || d.createdAt || d.inspectionDate, note: d.reason,
        })
      })
      items.sort((a, b) => new Date(b.sortKey) - new Date(a.sortKey))
      setEvents(items)
      setLoadError(false)
    }).catch(() => { if (!cancelled) setLoadError(true) })
    return () => { cancelled = true }
  }, [tab, memberKey]) // eslint-disable-line

  // Latest recommendation for each device, loaded when the AI tab is opened.
  useEffect(() => {
    if (tab !== 'ai') return undefined
    let cancelled = false
    Promise.all(members.map((m) =>
      getLatestRecommendation(m.id).then((r) => [m.id, r.data]).catch(() => [m.id, null]),
    )).then((pairs) => { if (!cancelled) setRecs(Object.fromEntries(pairs)) })
    return () => { cancelled = true }
  }, [tab, memberKey]) // eslint-disable-line

  const generateFor = async (id) => {
    setGenerating((g) => ({ ...g, [id]: true }))
    setAiError('')
    try {
      const { data } = await generateRecommendation(id)
      setRecs((r) => ({ ...r, [id]: data }))
    } catch (err) {
      setAiError(err.response?.data?.message || 'Failed to generate a recommendation.')
    } finally {
      setGenerating((g) => ({ ...g, [id]: false }))
    }
  }

  // One after another — each call asks the AI model, so don't fire them all at once.
  const generateMissing = async () => {
    for (const m of members) {
      if (!recs[m.id]) await generateFor(m.id)
    }
  }

  const typeOptions = useMemo(
    () => [...new Set((events || []).map((e) => e.kind).filter(Boolean))].sort(),
    [events],
  )
  const visibleEvents = (events || []).filter((e) =>
    (deviceFilter === '' || String(e.device) === deviceFilter) && (typeFilter === '' || e.kind === typeFilter))

  const totalValue = members.reduce((n, m) => n + Number(m.unitValue || 0) * (m.quantity || 1), 0)
  const count = (pick) => members.reduce((acc, m) => { const k = pick(m); acc[k] = (acc[k] || 0) + 1; return acc }, {})
  const conditions = count((m) => m.condition)
  const lifecycles = count((m) => m.lifecycleStatus)

  return (
    <>
      <div className="fixed inset-0 z-30 backdrop-blur-sm pointer-events-none" style={{ top: '60px' }} />
      <div
        className={`fixed inset-0 z-30 bg-zinc-950/20 ${exiting ? 'animate-fade-out' : 'animate-fade-in'}`}
        style={{ top: '60px' }}
        onClick={onClose}
      />
      <aside
        className={`fixed right-0 bottom-0 z-40 w-full max-w-lg bg-white dark:bg-zinc-950 border-l border-slate-200 dark:border-zinc-800 flex flex-col shadow-2xl overflow-hidden ${exiting ? 'animate-slide-out-drawer' : 'animate-slide-in-drawer'}`}
        style={{ top: '60px' }}
      >
        {/* Header */}
        <div className="flex items-start gap-3 px-5 py-4 border-b border-slate-200 dark:border-zinc-800 flex-shrink-0">
          <div className="flex-1 min-w-0">
            <p className="text-xs font-semibold text-brand-400">{members.length} devices · same model</p>
            <h2 className="text-base font-semibold text-slate-900 dark:text-white leading-snug mt-0.5 truncate">{first.description}</h2>
            <div className="flex items-center gap-2 mt-1.5 flex-wrap">
              {Object.entries(conditions).map(([c, n]) => (
                <span key={c} className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold ${CONDITION_BADGE[c] || ''}`}>{n} {c}</span>
              ))}
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-md text-slate-400 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-slate-200 dark:border-zinc-800 px-5 gap-1 flex-shrink-0">
          {Object.keys(TAB_LABELS).map((t) => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-3 py-2.5 text-xs font-semibold whitespace-nowrap transition-all border-b-2 ${
                tab === t ? 'border-slate-900 dark:border-white text-slate-900 dark:text-white' : 'border-transparent text-slate-500 dark:text-zinc-400 hover:text-slate-700 dark:hover:text-zinc-200'
              }`}>{TAB_LABELS[t]}</button>
          ))}
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 py-4">
          {tab === 'details' && (
            <div className="space-y-4">
              <div className="rounded-lg border border-slate-200 dark:border-zinc-800 divide-y divide-slate-100 dark:divide-zinc-800/60">
                <Field label="Category"     value={first.category?.categoryName} />
                <Field label="Devices"      value={members.length} />
                <Field label="Total Value"  value={php(totalValue)} />
                <Field label="Lifecycle"    value={
                  <span className="flex flex-wrap gap-1">
                    {Object.entries(lifecycles).map(([l, n]) => (
                      <span key={l} className={`inline-flex px-2 py-0.5 rounded-full text-xs font-semibold ${LIFECYCLE_BADGE[l] || ''}`}>{n} {l.replace('_', ' ')}</span>
                    ))}
                  </span>
                } />
              </div>

              <button
                onClick={() => setShowDevices(true)}
                className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-brand-500/10 border border-brand-500/20 text-brand-400 text-sm font-medium hover:bg-brand-500/20 transition-all"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M3 5a1 1 0 011-1h12a1 1 0 011 1v2H3V5zm0 4h14v2H3V9zm0 4h14v2a1 1 0 01-1 1H4a1 1 0 01-1-1v-2z" clipRule="evenodd" />
                </svg>
                View Devices ({members.length})
              </button>
              <p className="text-2xs text-slate-400 dark:text-zinc-500 text-center -mt-1">
                Every device with its own Property No., PAR No., people, price and condition — searchable.
              </p>
            </div>
          )}

          {tab === 'history' && (
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-2">
                <label className="flex flex-col gap-1">
                  <span className="text-2xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider">Device</span>
                  <select className={SELECT_CLASS} value={deviceFilter} onChange={(e) => setDeviceFilter(e.target.value)}>
                    <option value="">All devices</option>
                    {members.map((m, i) => <option key={m.id} value={String(i)}>{deviceName(i)}</option>)}
                  </select>
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-2xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider">Lifecycle event</span>
                  <select className={SELECT_CLASS} value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)}>
                    <option value="">All events</option>
                    {typeOptions.map((t) => <option key={t} value={t}>{t.charAt(0) + t.slice(1).toLowerCase().replace(/_/g, ' ')}</option>)}
                  </select>
                </label>
              </div>

              {events === null && !loadError && <p className="text-sm text-zinc-500 py-8 text-center">Loading lifecycle events…</p>}
              {loadError && <p className="text-sm text-red-400 py-8 text-center">Couldn't load lifecycle events.</p>}
              {events !== null && (
                <>
                  <p className="text-2xs text-slate-400 dark:text-zinc-500">
                    {visibleEvents.length} event{visibleEvents.length !== 1 ? 's' : ''}
                    {(deviceFilter !== '' || typeFilter !== '') && ` of ${events.length}`}
                  </p>
                  <div className="space-y-2">
                    {visibleEvents.length === 0
                      ? <p className="text-sm text-zinc-500 py-8 text-center">No lifecycle events match.</p>
                      : visibleEvents.map((item) => (
                        <div key={item.id} className="px-3.5 py-3 rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-900">
                          <p className="text-2xs font-semibold text-brand-400 mb-1">{deviceName(item.device)}</p>
                          <div className="flex items-center justify-between gap-2">
                            <span className="text-xs font-semibold text-slate-700 dark:text-zinc-200">
                              {item.type === 'disposal' ? `Disposal – ${item.title}` :
                               item.type === 'maintenance' ? `Maintenance – ${item.title}` : item.title}
                            </span>
                            {item.type === 'disposal' && (
                              <span className={`inline-flex px-1.5 py-0.5 rounded-full text-xs font-semibold ${
                                item.status === 'COMPLETED' ? 'bg-emerald-500/10 text-emerald-400' :
                                item.status === 'APPROVED'  ? 'bg-blue-500/10 text-blue-400'       : 'bg-amber-500/10 text-amber-400'
                              }`}>{item.status}</span>
                            )}
                            {item.type === 'maintenance' && (
                              <span className={`inline-flex px-1.5 py-0.5 rounded-full text-xs font-semibold ${
                                item.status === 'COMPLETED' ? 'bg-emerald-500/10 text-emerald-400' :
                                item.status === 'ONGOING'   ? 'bg-amber-500/10 text-amber-400'    : 'bg-blue-500/10 text-blue-400'
                              }`}>{item.status}</span>
                            )}
                            {item.type === 'history' && <span className="text-xs text-slate-400">{fmt(item.date)}</span>}
                          </div>
                          {item.type === 'disposal' && <p className="text-xs text-slate-400 mt-0.5">Inspected: {fmt(item.date)}</p>}
                          {item.type === 'maintenance' && <p className="text-xs text-slate-400 mt-0.5">{fmt(item.date)}{item.cost != null ? ` · ${php(item.cost)}` : ''}</p>}
                          {item.type === 'history' && <p className="text-xs text-slate-500 dark:text-zinc-400 mt-1">{item.meta}</p>}
                          {item.note && <p className="text-xs text-slate-500 dark:text-zinc-400 mt-0.5 italic">{item.note}</p>}
                        </div>
                      ))}
                  </div>
                </>
              )}
            </div>
          )}

          {tab === 'ai' && (
            <div className="space-y-3">
              <div className="flex items-end gap-2">
                <label className="flex flex-col gap-1 flex-1">
                  <span className="text-2xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider">Device</span>
                  <select className={SELECT_CLASS} value={aiDevice} onChange={(e) => setAiDevice(e.target.value)}>
                    <option value="">All devices</option>
                    {members.map((m, i) => <option key={m.id} value={String(i)}>{deviceName(i)}</option>)}
                  </select>
                </label>
                <button onClick={generateMissing} disabled={Object.values(generating).some(Boolean)}
                  className="px-3 py-2 rounded-md bg-brand-500/10 border border-brand-500/20 text-brand-400 text-xs font-semibold hover:bg-brand-500/20 disabled:opacity-50 transition-all whitespace-nowrap">
                  Generate missing
                </button>
              </div>
              {aiError && <div className="text-xs text-red-400 bg-red-950/30 border border-red-900/40 rounded-lg px-3.5 py-2.5">{aiError}</div>}

              {members.map((m, i) => {
                if (aiDevice !== '' && aiDevice !== String(i)) return null
                const rec = recs[m.id]
                return (
                  <div key={m.id} className="rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-900 px-3.5 py-3">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-2xs font-semibold text-brand-400">{deviceName(i)}</p>
                      <button onClick={() => generateFor(m.id)} disabled={!!generating[m.id]}
                        className="text-xs font-semibold text-slate-500 dark:text-zinc-400 hover:text-slate-800 dark:hover:text-zinc-100 disabled:opacity-50 transition-colors">
                        {generating[m.id] ? 'Generating…' : rec ? 'Regenerate' : 'Generate'}
                      </button>
                    </div>
                    {rec === undefined ? (
                      <p className="text-xs text-zinc-500 mt-2">Loading…</p>
                    ) : rec === null ? (
                      <p className="text-xs text-slate-400 dark:text-zinc-500 mt-2">No AI recommendation generated yet.</p>
                    ) : (
                      <div className="mt-2 space-y-2">
                        <div className="flex items-center justify-between gap-2">
                          <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold ${RECOMMENDATION_BADGE[rec.recommendation] || ''}`}>
                            {rec.recommendation?.replace(/_/g, ' ')}
                          </span>
                          <span className="text-2xs text-slate-400 dark:text-zinc-500">{fmt(rec.generatedAt)}</span>
                        </div>
                        <p className="text-xs text-slate-600 dark:text-zinc-300 leading-relaxed">{rec.rationale}</p>
                        <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-2xs text-slate-400 dark:text-zinc-500">
                          <span>Asset age: {rec.assetAgeYears} yrs</span>
                          <span>Repair cost: {php(rec.totalRepairCost)}</span>
                          <span>Repair frequency: {rec.repairFrequency}</span>
                          <span>Condition score: {rec.conditionScore}</span>
                        </div>
                      </div>
                    )}
                  </div>
                )
              })}
              <p className="text-2xs text-slate-400 dark:text-zinc-600 text-center">Advisory only — not a final decision.</p>
            </div>
          )}
        </div>
      </aside>

      {showDevices && (
        <Modal
          title="Devices"
          subtitle={`${first.description} — ${members.length} devices`}
          size="2xl"
          onClose={() => setShowDevices(false)}
        >
          <GroupDevicesTable members={members} renderRow={renderDeviceRow} />
        </Modal>
      )}
    </>
  )
}

function Field({ label, value }) {
  return (
    <div className="flex items-start gap-2 px-3.5 py-2">
      <span className="text-xs text-slate-400 dark:text-zinc-500 w-24 flex-shrink-0 pt-0.5">{label}</span>
      <span className="text-sm text-slate-900 dark:text-zinc-200 font-medium break-words">{value ?? '—'}</span>
    </div>
  )
}

// Loads a group's devices from the server, then shows the drawer — for pages (Maintenance,
// Disposal, Reports) that only know a group's id, not all its devices.
export function AssetGroupDrawerById({ groupId, exiting, onClose, renderDeviceRow }) {
  const [members, setMembers] = useState(null)
  useEffect(() => {
    let cancelled = false
    api.get(`/assets/group/${groupId}`)
      .then((r) => { if (!cancelled) setMembers(r.data) })
      .catch(() => { if (!cancelled) setMembers([]) })
    return () => { cancelled = true }
  }, [groupId])
  if (!members || members.length === 0) return null
  return <AssetGroupDrawer members={members} exiting={exiting} onClose={onClose} renderDeviceRow={renderDeviceRow} />
}
