import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { useDispatch } from 'react-redux'
import { Link, useNavigate } from 'react-router-dom'
import { setAssets } from '../../store/slices/assetSlice'
import MainLayout from '../../components/layout/MainLayout'
import { getAssets } from '../../services/assetService'
import { getAssetHistory } from '../../services/assetHistoryService'
import { getUsers } from '../../services/userService'
import { getRecommendationSummary } from '../../services/aiRecommendationService'
import { useEventStream } from '../../hooks/useEventStream'

// ── Count-up hook ─────────────────────────────────────────────────────────────
function useCountUp(target, active) {
  const [value, setValue] = useState(0)
  const rafRef = useRef(null)
  useEffect(() => {
    cancelAnimationFrame(rafRef.current)
    if (!active) { setValue(target); return }
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    if (reduced || target === 0) { setValue(target); return }
    setValue(0)
    const start = performance.now()
    const DURATION = 750
    const tick = (now) => {
      const p = Math.min((now - start) / DURATION, 1)
      const eased = p === 1 ? 1 : 1 - Math.pow(2, -10 * p)
      setValue(Math.round(eased * target))
      if (p < 1) rafRef.current = requestAnimationFrame(tick)
    }
    rafRef.current = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(rafRef.current)
  }, [target, active])
  return value
}

// ── Animated 0→1 progress (for the lifecycle ring's sweep-in) ─────────────────
function useAnimatedProgress(duration, active) {
  const [progress, setProgress] = useState(0)
  const rafRef = useRef(null)
  useEffect(() => {
    cancelAnimationFrame(rafRef.current)
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    if (!active || reduced) { setProgress(1); return }
    setProgress(0)
    const start = performance.now()
    const tick = (now) => {
      const p = Math.min((now - start) / duration, 1)
      const eased = 1 - Math.pow(1 - p, 3)
      setProgress(eased)
      if (p < 1) rafRef.current = requestAnimationFrame(tick)
    }
    rafRef.current = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(rafRef.current)
  }, [active, duration])
  return progress
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function localDateStr(d) {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function timeAgo(dt) {
  if (!dt) return '—'
  const diff = Date.now() - new Date(dt).getTime()
  const m = Math.floor(diff / 60000)
  if (m < 1)  return 'Just now'
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.floor(h / 24)
  if (d < 7)  return `${d}d ago`
  return new Date(dt).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })
}

function fmtMoney(v) {
  if (!v) return '₱0.00'
  const n = Number(v)
  if (n >= 1_000_000) return '₱' + (n / 1_000_000).toFixed(1) + 'M'
  if (n >= 1_000)     return '₱' + (n / 1_000).toFixed(0) + 'K'
  return '₱' + n.toLocaleString('en-PH', { minimumFractionDigits: 2 })
}

const EVENT_CFG = {
  REGISTERED:   { label: 'Registered',   color: 'text-blue-400',    bg: 'bg-blue-400/10' },
  ASSIGNED:     { label: 'Assigned',     color: 'text-emerald-400', bg: 'bg-emerald-400/10' },
  TRANSFERRED:  { label: 'Transferred',  color: 'text-orange-400',  bg: 'bg-orange-400/10' },
  MAINTENANCE:  { label: 'Maintenance',  color: 'text-amber-400',   bg: 'bg-amber-400/10' },
  DISPOSAL:     { label: 'Disposal',     color: 'text-red-400',     bg: 'bg-red-400/10' },
  ARCHIVED:     { label: 'Archived',     color: 'text-zinc-400',    bg: 'bg-zinc-400/10' },
}

const CONDITION_ORDER = ['SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE']
const CONDITION_CFG = {
  SERVICEABLE:   { bar: 'bg-emerald-500', text: 'text-emerald-400', dot: 'bg-emerald-400', label: 'Serviceable' },
  REPAIRABLE:    { bar: 'bg-amber-500',   text: 'text-amber-400',   dot: 'bg-amber-400',   label: 'Repairable' },
  UNSERVICEABLE: { bar: 'bg-red-500',     text: 'text-red-400',     dot: 'bg-red-400',     label: 'Unserviceable' },
}

const RECOMMENDATION_ORDER = ['BUDGET_PRIORITY', 'REVIEW_FOR_DISPOSAL', 'REPAIR', 'MONITOR', 'MAINTAIN']
const RECOMMENDATION_CFG = {
  BUDGET_PRIORITY:     { dot: 'bg-red-400',     label: 'Budget Priority' },
  REVIEW_FOR_DISPOSAL: { dot: 'bg-orange-400',  label: 'Review for Disposal' },
  REPAIR:              { dot: 'bg-amber-400',   label: 'Repair' },
  MONITOR:             { dot: 'bg-blue-400',    label: 'Monitor' },
  MAINTAIN:            { dot: 'bg-emerald-400', label: 'Maintain' },
}

const LIFECYCLE_ORDER = ['REGISTERED', 'ASSIGNED', 'TRANSFERRED', 'UNDER_MAINTENANCE', 'DISPOSED', 'ARCHIVED']
const LIFECYCLE_CFG = {
  REGISTERED:       { bar: 'bg-blue-500',    dot: 'bg-blue-400',    label: 'Registered',        hex: '#3b82f6' },
  ASSIGNED:         { bar: 'bg-emerald-500', dot: 'bg-emerald-400', label: 'Assigned',          hex: '#10b981' },
  TRANSFERRED:      { bar: 'bg-orange-500',  dot: 'bg-orange-400',  label: 'Transferred',       hex: '#f97316' },
  UNDER_MAINTENANCE:{ bar: 'bg-amber-500',   dot: 'bg-amber-400',   label: 'Under Maintenance', hex: '#f59e0b' },
  DISPOSED:         { bar: 'bg-red-500',     dot: 'bg-red-400',     label: 'Disposed',          hex: '#ef4444' },
  ARCHIVED:         { bar: 'bg-zinc-500',    dot: 'bg-zinc-400',    label: 'Archived',          hex: '#71717a' },
}

const ACTIVITY_RANGES = {
  day:   { unit: 'hour',  count: 24, title: 'Activity — Today',         periodLabel: 'today' },
  week:  { unit: 'day',   count: 7,  title: 'Activity — Last 7 Days',   periodLabel: 'this week' },
  month: { unit: 'day',   count: 30, title: 'Activity — Last 30 Days',  periodLabel: 'this month' },
  year:  { unit: 'month', count: 12, title: 'Activity — Last 12 Months', periodLabel: 'this year' },
}

function computeActivityTrend(history, range = 'week') {
  const now = new Date()
  const cfg = ACTIVITY_RANGES[range] || ACTIVITY_RANGES.week

  if (cfg.unit === 'hour') {
    const buckets = Array.from({ length: cfg.count }, (_, i) => {
      const d = new Date(now)
      d.setMinutes(0, 0, 0)
      d.setHours(d.getHours() - (cfg.count - 1 - i))
      const hour = d.getHours()
      const label = hour === 0 ? '12a' : hour === 12 ? '12p' : hour > 12 ? `${hour - 12}p` : `${hour}a`
      return { key: `${localDateStr(d)}T${String(hour).padStart(2, '0')}`, label, count: 0, isCurrent: i === cfg.count - 1 }
    })
    history.forEach((h) => {
      if (!h.eventDate) return
      const d = new Date(h.eventDate)
      const key = `${localDateStr(d)}T${String(d.getHours()).padStart(2, '0')}`
      const b = buckets.find((x) => x.key === key)
      if (b) b.count++
    })
    return buckets
  }

  if (cfg.unit === 'month') {
    const buckets = Array.from({ length: cfg.count }, (_, i) => {
      const d = new Date(now.getFullYear(), now.getMonth() - (cfg.count - 1 - i), 1)
      return { key: `${d.getFullYear()}-${d.getMonth()}`, label: d.toLocaleDateString('en-PH', { month: 'short' }), count: 0, isCurrent: i === cfg.count - 1 }
    })
    history.forEach((h) => {
      if (!h.eventDate) return
      const d = new Date(h.eventDate)
      const key = `${d.getFullYear()}-${d.getMonth()}`
      const b = buckets.find((x) => x.key === key)
      if (b) b.count++
    })
    return buckets
  }

  // day-unit buckets (week / month ranges)
  const buckets = Array.from({ length: cfg.count }, (_, i) => {
    const d = new Date(now)
    d.setDate(d.getDate() - (cfg.count - 1 - i))
    const label = cfg.count > 7 ? String(d.getDate()) : d.toLocaleDateString('en-PH', { weekday: 'short' })
    return { key: localDateStr(d), label, count: 0, isCurrent: i === cfg.count - 1 }
  })
  history.forEach((h) => {
    if (!h.eventDate) return
    const key = h.eventDate.slice(0, 10)
    const b = buckets.find((x) => x.key === key)
    if (b) b.count++
  })
  return buckets
}

function computeOfficeDist(assets) {
  const map = {}
  assets.forEach((a) => {
    const key = a.office?.officeName || 'Unassigned'
    if (!map[key]) map[key] = { office: key, officeId: a.office?.id ?? null, count: 0 }
    map[key].count++
  })
  return Object.values(map).sort((a, b) => b.count - a.count).slice(0, 6)
}

function computeTopAccountable(assets) {
  const map = {}
  assets.forEach((a) => {
    const name = a.accountablePerson
    if (!name) return
    map[name] = (map[name] || 0) + 1
  })
  return Object.entries(map).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([name, count]) => ({ name, count }))
}

// ── Skeleton ──────────────────────────────────────────────────────────────────
function Sk({ className, style }) {
  return <div className={`animate-pulse rounded bg-slate-200 dark:bg-zinc-800 ${className}`} style={style} />
}

// ── Sub-components ────────────────────────────────────────────────────────────

function StatStrip({ stats, loading }) {
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 overflow-hidden">
      <div className="grid grid-cols-2 xl:grid-cols-4 divide-x divide-y xl:divide-y-0 divide-slate-200 dark:divide-zinc-800">
        {stats.map(({ label, value, sub, delta, href, icon }) => (
          <Link
            key={label}
            to={href}
            className="group flex items-start gap-3 px-5 py-4 hover:bg-slate-50 dark:hover:bg-zinc-800/50 transition-colors duration-150"
          >
            <div className="w-8 h-8 rounded-lg bg-slate-100 dark:bg-zinc-800 flex items-center justify-center flex-shrink-0 mt-0.5 text-slate-400 dark:text-zinc-500 group-hover:text-brand-500 dark:group-hover:text-brand-400 group-hover:bg-brand-500/10 transition-all duration-150">
              {icon}
            </div>
            <div className="min-w-0">
              <p className="text-2xs font-semibold text-slate-400 dark:text-zinc-500 uppercase tracking-wider leading-none">{label}</p>
              {loading ? (
                <Sk className="h-7 w-16 mt-2 mb-1" />
              ) : (
                <p className="text-2xl font-bold text-slate-900 dark:text-white mt-1.5 leading-none tabular-nums truncate">{value}</p>
              )}
              <div className="flex items-center gap-1.5 mt-1">
                <p className="text-xs text-slate-400 dark:text-zinc-600 leading-tight">{sub}</p>
                {!loading && delta != null && delta > 0 && (
                  <span className="text-2xs font-semibold text-emerald-400 bg-emerald-400/10 px-1.5 py-0.5 rounded leading-none">
                    +{delta} this month
                  </span>
                )}
              </div>
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}

function QuickActions() {
  const actions = [
    {
      label: 'Add Asset', desc: 'Register new equipment', to: '/assets',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" /></svg>,
    },
    {
      label: 'Asset History', desc: 'View activity logs', to: '/asset-history',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clipRule="evenodd" /></svg>,
    },
    {
      label: 'Scan QR', desc: 'Identify by QR code', to: '/qr-scanner',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M3 4a1 1 0 011-1h3a1 1 0 011 1v3a1 1 0 01-1 1H4a1 1 0 01-1-1V4zm2 2V5h1v1H5zM3 13a1 1 0 011-1h3a1 1 0 011 1v3a1 1 0 01-1 1H4a1 1 0 01-1-1v-3zm2 2v-1h1v1H5zM13 3a1 1 0 00-1 1v3a1 1 0 001 1h3a1 1 0 001-1V4a1 1 0 00-1-1h-3zm1 2v1h1V5h-1zM11 7a1 1 0 112 0v1h1a1 1 0 110 2h-2a1 1 0 01-1-1V7zM7 11a1 1 0 100 2h1v1a1 1 0 102 0v-2a1 1 0 00-1-1H7zM13 11a1 1 0 100 2h.01a1 1 0 100-2H13zM15 13a1 1 0 100 2h.01a1 1 0 100-2H15zM13 15a1 1 0 100 2h.01a1 1 0 100-2H13z" clipRule="evenodd" /></svg>,
    },
    {
      label: 'Reports', desc: 'Export audit reports', to: '/reports',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path d="M2 11a1 1 0 011-1h2a1 1 0 011 1v5a1 1 0 01-1 1H3a1 1 0 01-1-1v-5zM8 7a1 1 0 011-1h2a1 1 0 011 1v9a1 1 0 01-1 1H9a1 1 0 01-1-1V7zM14 4a1 1 0 011-1h2a1 1 0 011 1v12a1 1 0 01-1 1h-2a1 1 0 01-1-1V4z" /></svg>,
    },
  ]
  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
      {actions.map(({ label, desc, to, icon }) => (
        <Link key={label} to={to} className="group flex items-center gap-3 px-3.5 py-3 bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-800 rounded-xl hover:border-brand-500/40 hover:bg-slate-50 dark:hover:bg-zinc-800/60 transition-all duration-150">
          <span className="w-7 h-7 flex-shrink-0 flex items-center justify-center rounded-lg bg-slate-100 dark:bg-zinc-800 text-slate-400 dark:text-zinc-500 group-hover:bg-brand-500/15 group-hover:text-brand-500 dark:group-hover:text-brand-400 transition-all duration-150">{icon}</span>
          <div className="min-w-0">
            <p className="text-sm font-medium text-slate-700 dark:text-zinc-200 leading-tight truncate">{label}</p>
            <p className="text-xs text-slate-400 dark:text-zinc-600 leading-tight mt-0.5 hidden sm:block truncate">{desc}</p>
          </div>
        </Link>
      ))}
    </div>
  )
}

function ConditionDistribution({ condDist, total, loading, onSelect }) {
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Asset Condition</p>
        {!loading && <span className="text-xs text-slate-400 dark:text-zinc-600 tabular-nums">{total} assets</span>}
      </div>
      <div className="p-4">
        {loading ? (
          <div className="space-y-3">
            <Sk className="h-2.5 w-full rounded-full" />
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="flex items-center gap-2">
                <Sk className="w-2 h-2 rounded-full flex-shrink-0" />
                <Sk className="h-3 flex-1" />
                <Sk className="h-3 w-6" />
              </div>
            ))}
          </div>
        ) : total === 0 ? (
          <p className="text-xs text-slate-400 dark:text-zinc-600 text-center py-6">No assets registered yet.</p>
        ) : (
          <>
            <div className="flex h-2.5 rounded-full overflow-hidden mb-4 gap-px bg-zinc-100 dark:bg-zinc-800">
              {CONDITION_ORDER.map((cond) => {
                const count = condDist[cond] || 0
                if (count === 0) return null
                return (
                  <div
                    key={cond}
                    className={`h-full ${CONDITION_CFG[cond].bar} transition-all duration-700`}
                    style={{ width: `${(count / total) * 100}%` }}
                    title={`${CONDITION_CFG[cond].label}: ${count}`}
                  />
                )
              })}
            </div>
            <div className="space-y-2.5">
              {CONDITION_ORDER.map((cond) => {
                const count = condDist[cond] || 0
                if (count === 0) return null
                const pct = Math.round((count / total) * 100)
                const cfg = CONDITION_CFG[cond]
                return (
                  <button
                    key={cond}
                    type="button"
                    onClick={() => onSelect?.(cond)}
                    title={`View ${cfg.label.toLowerCase()} assets`}
                    className="w-full flex items-center gap-2 -mx-1.5 px-1.5 py-1 rounded-md group hover:bg-slate-50 dark:hover:bg-zinc-800/60 transition-colors duration-150"
                  >
                    <span className={`w-2 h-2 rounded-full flex-shrink-0 ${cfg.dot}`} />
                    <span className="text-xs text-slate-500 dark:text-zinc-400 flex-1 truncate text-left group-hover:text-slate-700 dark:group-hover:text-zinc-200 transition-colors duration-150">{cfg.label}</span>
                    <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums">{count}</span>
                    <span className="text-[10px] text-slate-400 dark:text-zinc-600 tabular-nums w-7 text-right">{pct}%</span>
                  </button>
                )
              })}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function LifecycleDistribution({ lifecycleDist, total, loading, onSelect }) {
  const active = !loading && total > 0
  const progress = useAnimatedProgress(1100, active)
  const animatedTotal = useCountUp(total, !loading)

  const R = 64
  const STROKE = 18
  const C = 2 * Math.PI * R
  const GAP = 6

  let cumulative = 0
  const segments = active
    ? LIFECYCLE_ORDER.filter((s) => (lifecycleDist[s] || 0) > 0).map((s) => {
        const count = lifecycleDist[s] || 0
        const fullLen = (count / total) * C
        const start = cumulative
        cumulative += fullLen
        const drawn = Math.max(fullLen * progress - GAP, 0)
        return { key: s, color: LIFECYCLE_CFG[s].hex, dasharray: `${drawn} ${C - drawn}`, dashoffset: -start }
      })
    : []

  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Lifecycle Status</p>
        {!loading && <span className="text-xs text-slate-400 dark:text-zinc-600 tabular-nums">{total} total</span>}
      </div>
      <div className="p-4">
        {loading ? (
          <div className="flex flex-col items-center gap-4">
            <Sk className="w-36 h-36 rounded-full" />
            <div className="w-full space-y-2.5">
              {Array.from({ length: 4 }).map((_, i) => (
                <div key={i} className="flex items-center gap-2">
                  <Sk className="w-2 h-2 rounded-full flex-shrink-0" />
                  <Sk className="h-3 flex-1" />
                  <Sk className="h-3 w-6" />
                </div>
              ))}
            </div>
          </div>
        ) : total === 0 ? (
          <p className="text-xs text-slate-400 dark:text-zinc-600 text-center py-6">No assets yet.</p>
        ) : (
          <>
            <div className="relative w-36 h-36 mx-auto mb-4">
              <svg viewBox="0 0 160 160" className="w-full h-full -rotate-90">
                <circle cx="80" cy="80" r={R} fill="none" strokeWidth={STROKE} className="stroke-slate-100 dark:stroke-zinc-800" />
                {segments.map((seg) => (
                  <circle
                    key={seg.key}
                    cx="80" cy="80" r={R} fill="none"
                    strokeWidth={STROKE}
                    strokeLinecap="round"
                    style={{ stroke: seg.color, strokeDasharray: seg.dasharray, strokeDashoffset: seg.dashoffset }}
                  />
                ))}
              </svg>
              <div className="absolute inset-0 flex flex-col items-center justify-center">
                <span className="text-2xl font-extrabold text-slate-900 dark:text-white tabular-nums">{animatedTotal}</span>
                <span className="text-[10px] font-semibold text-slate-400 dark:text-zinc-600 tracking-wide">ASSETS</span>
              </div>
            </div>
            <div className="space-y-2.5">
              {LIFECYCLE_ORDER.map((s) => {
                const count = lifecycleDist[s] || 0
                if (count === 0) return null
                const pct = Math.round((count / total) * 100)
                const cfg = LIFECYCLE_CFG[s]
                return (
                  <button
                    key={s}
                    type="button"
                    onClick={() => onSelect?.(s)}
                    title={`View ${cfg.label.toLowerCase()} assets`}
                    className="w-full flex items-center gap-2 -mx-1.5 px-1.5 py-1 rounded-md group hover:bg-slate-50 dark:hover:bg-zinc-800/60 transition-colors duration-150"
                  >
                    <span className={`w-2 h-2 rounded-full flex-shrink-0 ${cfg.dot}`} />
                    <span className="text-xs text-slate-500 dark:text-zinc-400 flex-1 truncate text-left group-hover:text-slate-700 dark:group-hover:text-zinc-200 transition-colors duration-150">{cfg.label}</span>
                    <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums">{count}</span>
                    <span className="text-[10px] text-slate-400 dark:text-zinc-600 tabular-nums w-7 text-right">{pct}%</span>
                  </button>
                )
              })}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function OfficeDistribution({ offices, total, loading, onSelect }) {
  const max = offices[0]?.count || 1
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Assets by Office</p>
        {!loading && <span className="text-xs text-slate-400 dark:text-zinc-600 tabular-nums">{total} total</span>}
      </div>
      <div className="p-4 space-y-3">
        {loading ? (
          Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="space-y-1.5">
              <div className="flex justify-between"><Sk className="h-3 w-32" /><Sk className="h-3 w-6" /></div>
              <Sk className="h-1.5 w-full rounded-full" />
            </div>
          ))
        ) : offices.length === 0 ? (
          <p className="text-xs text-slate-400 dark:text-zinc-600 text-center py-6">No office data available.</p>
        ) : (
          offices.map(({ office, officeId, count }) => {
            const pct = Math.round((count / total) * 100)
            const clickable = officeId != null
            return (
              <button
                key={office}
                type="button"
                disabled={!clickable}
                onClick={() => onSelect?.(officeId)}
                title={clickable ? `View assets in ${office}` : undefined}
                className={`w-full text-left group ${clickable ? 'cursor-pointer' : 'cursor-default'}`}
              >
                <div className="flex items-center justify-between mb-1.5">
                  <span className={`text-xs text-slate-500 dark:text-zinc-400 truncate max-w-[150px] leading-tight transition-colors duration-150 ${clickable ? 'group-hover:text-slate-700 dark:group-hover:text-zinc-200' : ''}`} title={office}>{office}</span>
                  <div className="flex items-center gap-1.5 flex-shrink-0 ml-2">
                    <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums">{count}</span>
                    <span className="text-[10px] text-slate-400 dark:text-zinc-600 tabular-nums w-7 text-right">{pct}%</span>
                  </div>
                </div>
                <div className="h-1.5 rounded-full bg-slate-100 dark:bg-zinc-800 overflow-hidden">
                  <div className={`h-full w-full rounded-full bg-blue-500 origin-left transition-transform duration-[250ms] ease-out ${clickable ? 'group-hover:bg-blue-400' : ''}`} style={{ transform: `scaleX(${count / max})` }} />
                </div>
              </button>
            )
          })
        )}
      </div>
    </div>
  )
}

function TopAccountable({ people, loading, onSelect }) {
  const max = people[0]?.count || 1
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Top Accountable Persons</p>
      </div>
      <div className="p-4 space-y-3">
        {loading ? (
          Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="flex items-center gap-3">
              <Sk className="w-5 h-5 rounded-full flex-shrink-0" />
              <div className="flex-1 space-y-1.5"><Sk className="h-3 w-3/4" /><Sk className="h-1.5 w-full rounded-full" /></div>
              <Sk className="h-3 w-5" />
            </div>
          ))
        ) : people.length === 0 ? (
          <p className="text-xs text-slate-400 dark:text-zinc-600 text-center py-6">No accountable persons assigned.</p>
        ) : (
          people.map(({ name, count }, i) => (
            <button
              key={name}
              type="button"
              onClick={() => onSelect?.(name)}
              title={`View assets accountable to ${name}`}
              className="w-full flex items-center gap-3 group"
            >
              <span className="w-5 h-5 rounded-full bg-brand-500/15 text-brand-400 text-[10px] font-bold flex items-center justify-center flex-shrink-0">
                {i + 1}
              </span>
              <div className="flex-1 min-w-0">
                <p className="text-xs font-medium text-slate-600 dark:text-zinc-300 truncate leading-tight mb-1.5 text-left group-hover:text-slate-900 dark:group-hover:text-white transition-colors duration-150" title={name}>{name}</p>
                <div className="h-1.5 rounded-full bg-slate-100 dark:bg-zinc-800 overflow-hidden">
                  <div className="h-full w-full rounded-full bg-brand-500 origin-left transition-transform duration-[250ms] ease-out group-hover:bg-brand-400" style={{ transform: `scaleX(${count / max})` }} />
                </div>
              </div>
              <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums flex-shrink-0">{count}</span>
            </button>
          ))
        )}
      </div>
    </div>
  )
}

function AiRecommendationsSummary({ summary, total, loading }) {
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">AI Lifecycle Insights</p>
        {!loading && total > 0 && <span className="text-xs text-slate-400 dark:text-zinc-600 tabular-nums">{total} generated</span>}
      </div>
      <div className="p-4 space-y-2.5">
        {loading ? (
          Array.from({ length: 3 }).map((_, i) => (
            <div key={i} className="flex items-center gap-2">
              <Sk className="w-2 h-2 rounded-full flex-shrink-0" />
              <Sk className="h-3 flex-1" />
              <Sk className="h-3 w-6" />
            </div>
          ))
        ) : total === 0 ? (
          <p className="text-xs text-slate-400 dark:text-zinc-600 text-center py-6">
            No AI recommendations yet. Open an asset and generate one from its AI Insight tab.
          </p>
        ) : (
          RECOMMENDATION_ORDER.map((r) => {
            const count = summary[r] || 0
            if (count === 0) return null
            const pct = Math.round((count / total) * 100)
            const cfg = RECOMMENDATION_CFG[r]
            return (
              <div key={r} className="flex items-center gap-2">
                <span className={`w-2 h-2 rounded-full flex-shrink-0 ${cfg.dot}`} />
                <span className="text-xs text-slate-500 dark:text-zinc-400 flex-1 truncate">{cfg.label}</span>
                <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums">{count}</span>
                <span className="text-[10px] text-slate-400 dark:text-zinc-600 tabular-nums w-7 text-right">{pct}%</span>
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}

const ACTIVITY_RANGE_OPTIONS = [
  { key: 'day',   label: 'Day' },
  { key: 'week',  label: 'Week' },
  { key: 'month', label: 'Month' },
  { key: 'year',  label: 'Year' },
]

function ActivityRangeToggle({ range, onChange }) {
  return (
    <div className="inline-flex items-center rounded-lg border border-slate-200 dark:border-zinc-700 bg-slate-50 dark:bg-zinc-800/60 p-0.5">
      {ACTIVITY_RANGE_OPTIONS.map((opt) => (
        <button
          key={opt.key}
          onClick={() => onChange(opt.key)}
          className={`px-2.5 py-1 rounded-md text-2xs font-medium transition-all duration-150 ${
            range === opt.key
              ? 'bg-white dark:bg-zinc-900 text-slate-900 dark:text-zinc-100 shadow-sm'
              : 'text-slate-400 dark:text-zinc-500 hover:text-slate-600 dark:hover:text-zinc-300'
          }`}
        >
          {opt.label}
        </button>
      ))}
    </div>
  )
}

function ActivityTrend({ trend, loading, range, onRangeChange }) {
  const cfg = ACTIVITY_RANGES[range] || ACTIVITY_RANGES.week
  const max = Math.max(...trend.map((d) => d.count), 1)
  const total = trend.reduce((s, d) => s + d.count, 0)
  const skH = [38, 56, 24, 68, 44, 52, 32]
  // Thin out labels once bars get dense (24 hourly / 30 daily bars) so text doesn't collide.
  const labelStride = trend.length > 14 ? Math.ceil(trend.length / 8) : 1
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">{cfg.title}</p>
          {!loading && (
            <span className="text-xs text-slate-400 dark:text-zinc-600 tabular-nums">{total} event{total !== 1 ? 's' : ''} {cfg.periodLabel}</span>
          )}
        </div>
        <ActivityRangeToggle range={range} onChange={onRangeChange} />
      </div>
      <div className="px-5 py-4">
        {loading ? (
          <div className="flex items-end gap-2" style={{ height: '80px' }}>
            {skH.map((h, i) => (
              <div key={i} className="flex-1 flex flex-col items-center justify-end">
                <Sk className="w-full rounded-sm" style={{ height: `${h}px` }} />
              </div>
            ))}
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            <div className="flex items-end gap-1 gap-x-1" style={{ height: '80px' }}>
              {trend.map((bucket) => {
                const barH = bucket.count === 0 ? 3 : Math.max((bucket.count / max) * 68, 6)
                return (
                  <div key={bucket.key} className="flex flex-col items-center justify-end flex-1 h-full min-w-0">
                    {bucket.count > 0 && trend.length <= 14 && (
                      <span className="text-2xs text-slate-400 dark:text-zinc-500 tabular-nums mb-1 leading-none">{bucket.count}</span>
                    )}
                    <div
                      className={`w-full rounded-sm transition-all duration-500 ${bucket.isCurrent ? 'bg-brand-500' : 'bg-brand-500/35 hover:bg-brand-500/60'}`}
                      style={{ height: `${barH}px` }}
                      title={`${bucket.count} event${bucket.count !== 1 ? 's' : ''} — ${bucket.label}`}
                    />
                  </div>
                )
              })}
            </div>
            <div className="flex gap-1">
              {trend.map((bucket, i) => (
                <span
                  key={bucket.key}
                  className={`flex-1 text-center text-2xs truncate ${bucket.isCurrent ? 'text-brand-400 font-semibold' : 'text-slate-400 dark:text-zinc-600'}`}
                >
                  {i % labelStride === 0 || bucket.isCurrent ? bucket.label : ''}
                </span>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function ActivityFeed({ events, loading, className = '' }) {
  return (
    <div className={`bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 flex flex-col ${className}`}>
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Recent Activity</p>
        {!loading && events.length > 0 && (
          <Link to="/asset-history" className="text-xs text-brand-400 hover:text-brand-300 font-medium transition-colors duration-150">View all</Link>
        )}
      </div>
      <div className="flex-1 divide-y divide-slate-100 dark:divide-zinc-800/70">
        {loading ? (
          Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="px-5 py-3.5 flex items-start gap-3">
              <Sk className="w-14 h-5 rounded flex-shrink-0 mt-0.5" />
              <div className="flex-1 space-y-2"><Sk className="h-3.5 w-3/4" /><Sk className="h-3 w-1/2" /></div>
              <Sk className="h-3 w-12 flex-shrink-0 mt-1" />
            </div>
          ))
        ) : events.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-14 gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-9 w-9 text-slate-200 dark:text-zinc-800" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            <p className="text-sm text-slate-400 dark:text-zinc-600">No activity logged yet.</p>
            <Link to="/asset-history" className="text-xs text-brand-400 hover:text-brand-300 font-medium mt-1 transition-colors">Log an event</Link>
          </div>
        ) : (
          events.map((ev, i) => {
            const cfg = EVENT_CFG[ev.eventType] || { label: ev.eventType, color: 'text-zinc-400', bg: 'bg-zinc-400/10' }
            const performer = ev.performedBy?.fullName || ev.performedBy?.username || '—'
            return (
              <div key={i} className="px-5 py-3 flex items-start gap-3 hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                <span className={`flex-shrink-0 mt-0.5 inline-flex items-center px-2 py-0.5 rounded text-2xs font-semibold leading-none whitespace-nowrap ${cfg.color} ${cfg.bg}`}>{cfg.label}</span>
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-slate-700 dark:text-zinc-200 leading-snug truncate font-medium">{ev.asset?.description || '—'}</p>
                  <p className="text-xs text-slate-400 dark:text-zinc-500 mt-0.5 leading-snug truncate">By: {performer}</p>
                </div>
                <time className="flex-shrink-0 text-xs text-slate-400 dark:text-zinc-600 whitespace-nowrap mt-1 tabular-nums cursor-default">
                  {timeAgo(ev.eventDate)}
                </time>
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}

function CategoryBreakdown({ breakdown, total, loading, onSelect }) {
  const max = breakdown[0]?.count || 1
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Assets by Category</p>
        {!loading && <span className="text-xs text-slate-400 dark:text-zinc-600 tabular-nums">{total} total</span>}
      </div>
      <div className="p-4 space-y-3">
        {loading ? (
          Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="space-y-1.5">
              <div className="flex justify-between"><Sk className="h-3 w-28" /><Sk className="h-3 w-6" /></div>
              <Sk className="h-1.5 w-full rounded-full" />
            </div>
          ))
        ) : breakdown.length === 0 ? (
          <p className="text-xs text-slate-400 dark:text-zinc-600 text-center py-6">No assets yet.</p>
        ) : (
          breakdown.map(({ category, categoryId, count }) => {
            const pct = Math.round((count / total) * 100)
            const clickable = categoryId != null
            return (
              <button
                key={category}
                type="button"
                disabled={!clickable}
                onClick={() => onSelect?.(categoryId)}
                title={clickable ? `View ${category} assets` : undefined}
                className={`w-full text-left group ${clickable ? 'cursor-pointer' : 'cursor-default'}`}
              >
                <div className="flex items-center justify-between mb-1.5">
                  <span className={`text-xs text-slate-500 dark:text-zinc-400 truncate max-w-[150px] leading-tight transition-colors duration-150 ${clickable ? 'group-hover:text-slate-700 dark:group-hover:text-zinc-200' : ''}`} title={category}>{category}</span>
                  <div className="flex items-center gap-1.5 flex-shrink-0 ml-2">
                    <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums">{count}</span>
                    <span className="text-[10px] text-slate-400 dark:text-zinc-600 tabular-nums w-7 text-right">{pct}%</span>
                  </div>
                </div>
                <div className="h-1.5 rounded-full bg-slate-100 dark:bg-zinc-800 overflow-hidden">
                  <div className={`h-full w-full rounded-full bg-brand-500 origin-left transition-transform duration-[250ms] ease-out ${clickable ? 'group-hover:bg-brand-400' : ''}`} style={{ transform: `scaleX(${count / max})` }} />
                </div>
              </button>
            )
          })
        )}
      </div>
    </div>
  )
}

// ── Dashboard ─────────────────────────────────────────────────────────────────
function Dashboard() {
  const dispatch = useDispatch()
  const navigate = useNavigate()

  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState(false)
  const [assets, setLocalAssets] = useState([])
  const [history, setHistory]   = useState([])
  const [userCount, setUserCount] = useState(0)
  const [aiSummary, setAiSummary] = useState([])
  const [activityRange, setActivityRange] = useState('week')

  const load = useCallback(() => {
    setLoading(true)
    setError(false)
    Promise.all([
      getAssets().catch(() => null),
      getAssetHistory().catch(() => null),
      getUsers().catch(() => null),
      getRecommendationSummary().catch(() => null),
    ]).then(([assetRes, histRes, userRes, aiRes]) => {
      if (!assetRes && !histRes && !userRes) { setError(true); setLoading(false); return }
      const a = assetRes?.data ?? []
      const h = histRes?.data  ?? []
      const u = userRes?.data  ?? []
      setLocalAssets(a)
      dispatch(setAssets(a))
      setHistory(h)
      setUserCount(u.length)
      setAiSummary(aiRes?.data ?? [])
      setLoading(false)
    })
  }, [dispatch])

  useEffect(() => { load() }, [load])

  // Coalesce bursts of events (e.g. an asset condition change that cascades
  // into maintenance + disposal records) into a single reload.
  const reloadTimerRef = useRef(null)
  const scheduleReload = useCallback(() => {
    clearTimeout(reloadTimerRef.current)
    reloadTimerRef.current = setTimeout(load, 300)
  }, [load])
  useEffect(() => () => clearTimeout(reloadTimerRef.current), [])

  useEventStream('asset', scheduleReload)
  useEventStream('maintenance', scheduleReload)
  useEventStream('disposal', scheduleReload)

  // ── Derived analytics ──────────────────────────────────────────────────────
  const totalAssets = assets.length
  const totalValue  = assets.reduce((s, a) => s + (Number(a.unitValue) || 0) * (Number(a.quantity) || 1), 0)

  const now = new Date()
  const newThisMonth = assets.filter((a) => {
    if (!a.createdAt) return false
    const d = new Date(a.createdAt)
    return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()
  }).length

  const underMaintenance = assets.filter((a) => a.lifecycleStatus === 'UNDER_MAINTENANCE').length
  const disposed = assets.filter((a) => a.lifecycleStatus === 'DISPOSED').length

  const condDist = {}
  assets.forEach((a) => { condDist[a.condition] = (condDist[a.condition] || 0) + 1 })

  const lifecycleDist = {}
  assets.forEach((a) => { lifecycleDist[a.lifecycleStatus] = (lifecycleDist[a.lifecycleStatus] || 0) + 1 })

  const officeDist     = useMemo(() => computeOfficeDist(assets), [assets])
  const topAccountable = useMemo(() => computeTopAccountable(assets), [assets])
  const activityTrend  = useMemo(() => computeActivityTrend(history, activityRange), [history, activityRange])

  const categoryBreakdown = useMemo(() => {
    const map = {}
    assets.forEach((a) => {
      const key = a.category?.categoryName || 'Uncategorized'
      if (!map[key]) map[key] = { category: key, categoryId: a.category?.id ?? null, count: 0 }
      map[key].count++
    })
    return Object.values(map).sort((a, b) => b.count - a.count).slice(0, 8)
  }, [assets])

  const recentEvents = history.slice(0, 8)

  const aiSummaryMap = {}
  let aiSummaryTotal = 0
  aiSummary.forEach(({ recommendation, count }) => { aiSummaryMap[recommendation] = count; aiSummaryTotal += count })

  const animAssets  = useCountUp(totalAssets,     !loading)
  const animValue   = useCountUp(Math.round(totalValue), !loading)
  const animMaint   = useCountUp(underMaintenance, !loading)
  const animUsers   = useCountUp(userCount,        !loading)

  const today = now.toLocaleDateString('en-PH', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })

  const stats = [
    {
      label: 'Assets', value: animAssets.toLocaleString(),
      sub: 'Total registered assets', delta: newThisMonth, href: '/assets',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M3 5a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2.22l.123.489.804.804A1 1 0 0113 18H7a1 1 0 01-.707-1.707l.804-.804L7.22 15H5a2 2 0 01-2-2V5zm5.771 7H5V5h10v7H8.771z" clipRule="evenodd" /></svg>,
    },
    {
      label: 'Asset Value', value: fmtMoney(animValue),
      sub: 'Total acquisition value', href: '/assets',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path d="M8.433 7.418c.155-.103.346-.196.567-.267v1.698a2.305 2.305 0 01-.567-.267C8.07 8.34 8 8.114 8 8c0-.114.07-.34.433-.582zM11 12.849v-1.698c.22.071.412.164.567.267.364.243.433.468.433.582 0 .114-.07.34-.433.582a2.305 2.305 0 01-.567.267z" /><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-13a1 1 0 10-2 0v.092a4.535 4.535 0 00-1.676.662C6.602 6.234 6 7.009 6 8c0 .99.602 1.765 1.324 2.246.48.32 1.054.545 1.676.662v1.941c-.391-.127-.68-.317-.843-.504a1 1 0 10-1.51 1.31c.562.649 1.413 1.076 2.353 1.253V15a1 1 0 102 0v-.092a4.535 4.535 0 001.676-.662C13.398 13.766 14 12.991 14 12c0-.99-.602-1.765-1.324-2.246A4.535 4.535 0 0011 9.092V7.151c.391.127.68.317.843.504a1 1 0 101.511-1.31c-.563-.649-1.413-1.076-2.354-1.253V5z" clipRule="evenodd" /></svg>,
    },
    {
      label: 'Maintenance', value: animMaint.toLocaleString(),
      sub: 'Under maintenance', href: '/maintenance',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" /></svg>,
    },
    {
      label: 'Accounts', value: animUsers.toLocaleString(),
      sub: 'Admin and staff users', href: '/accounts',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path d="M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z" /></svg>,
    },
  ]

  return (
    <MainLayout>
      {/* Header */}
      <div className="flex items-start justify-between gap-4 mb-3">
        <p className="text-xs text-slate-400 dark:text-zinc-600">{today}</p>
        <div className="flex items-center gap-2">
          {error && (
            <span className="text-xs text-red-400 flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-red-400 inline-block" />
              Load failed
            </span>
          )}
          <button
            onClick={load}
            disabled={loading}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-xs font-medium text-slate-500 dark:text-zinc-400 hover:text-slate-900 dark:hover:text-zinc-200 hover:border-slate-300 dark:hover:border-zinc-600 transition-all duration-150 disabled:opacity-40"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Refresh
          </button>
        </div>
      </div>

      {/* Stat strip */}
      <div className="mb-5">
        <StatStrip stats={stats} loading={loading} />
      </div>

      {/* Quick Actions */}
      <div className="mb-5">
        <QuickActions />
      </div>

      {/* Condition + Lifecycle + Office row */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5 mb-5">
        <ConditionDistribution condDist={condDist} total={totalAssets} loading={loading}
          onSelect={(cond) => navigate(`/assets?condition=${cond}`)} />
        <LifecycleDistribution lifecycleDist={lifecycleDist} total={totalAssets} loading={loading}
          onSelect={(status) => navigate(`/assets?lifecycle=${status}`)} />
        <OfficeDistribution offices={officeDist} total={totalAssets} loading={loading}
          onSelect={(officeId) => navigate(`/assets?office=${officeId}`)} />
      </div>

      {/* Activity trend */}
      <div className="mb-5">
        <ActivityTrend trend={activityTrend} loading={loading} range={activityRange} onRangeChange={setActivityRange} />
      </div>

      {/* Activity feed + category breakdown */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_300px] gap-5 items-start">
        <ActivityFeed events={recentEvents} loading={loading} className="h-fit self-start" />
        <div className="space-y-5 h-fit self-start">
          <CategoryBreakdown breakdown={categoryBreakdown} total={totalAssets} loading={loading}
            onSelect={(categoryId) => navigate(`/assets?category=${categoryId}`)} />
          <AiRecommendationsSummary summary={aiSummaryMap} total={aiSummaryTotal} loading={loading} />
          <TopAccountable people={topAccountable} loading={loading}
            onSelect={(name) => navigate(`/assets?search=${encodeURIComponent(name)}`)} />
        </div>
      </div>
    </MainLayout>
  )
}

export default Dashboard
