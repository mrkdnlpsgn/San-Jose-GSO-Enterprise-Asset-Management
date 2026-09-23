import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { useDispatch, useSelector } from 'react-redux'
import { Link, useNavigate } from 'react-router-dom'
import { setAssets } from '../../store/slices/assetSlice'
import MainLayout from '../../components/layout/MainLayout'
import { getAssets } from '../../services/assetService'
import { getAssetHistory } from '../../services/assetHistoryService'
import { getUsers } from '../../services/userService'
import { getLifecycleInsights, generateLifecycleSummary } from '../../services/aiRecommendationService'
import { getMaintenance, approveMaintenance, rejectMaintenance } from '../../services/maintenanceService'
import { getDisposal, approveDisposal, rejectDisposal } from '../../services/disposalService'
import { useToast } from '../../context/ToastContext'
import { RejectRequestModal } from '../../components/common/ApprovalControls'
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

// REGISTERED merges the old REGISTERED+ASSIGNED asset lifecycle statuses (every
// asset has a location by default, so that distinction wasn't meaningful here).
// The maintenance/disposal buckets are no longer asset.lifecycleStatus counts —
// they're driven by the active (non-deleted) maintenance_ledger/disposal_ledger
// records themselves, split by their own status fields, so this chart mixes
// "current asset state" with "current ledger activity" by design.
const LIFECYCLE_ORDER = [
  'REGISTERED', 'TRANSFERRED',
  'MAINT_ONGOING', 'MAINT_SCHEDULED', 'MAINT_REPAIRED',
  'DISP_PENDING', 'DISP_TRANSFERRED', 'DISP_DESTRUCTED',
  'ARCHIVED',
]
const LIFECYCLE_CFG = {
  REGISTERED:        { bar: 'bg-blue-500',    dot: 'bg-blue-400',    label: 'Registered',           hex: '#3b82f6' },
  TRANSFERRED:        { bar: 'bg-orange-500',  dot: 'bg-orange-400',  label: 'Transferred',          hex: '#f97316' },
  MAINT_ONGOING:      { bar: 'bg-amber-500',   dot: 'bg-amber-400',   label: 'Ongoing Maintenance',  hex: '#f59e0b' },
  MAINT_SCHEDULED:    { bar: 'bg-yellow-500',  dot: 'bg-yellow-400',  label: 'Scheduled Maintenance',hex: '#eab308' },
  MAINT_REPAIRED:     { bar: 'bg-lime-500',    dot: 'bg-lime-400',    label: 'Repaired',             hex: '#84cc16' },
  DISP_PENDING:       { bar: 'bg-rose-400',    dot: 'bg-rose-300',    label: 'Pending Disposal',     hex: '#fb7185' },
  DISP_TRANSFERRED:   { bar: 'bg-pink-500',    dot: 'bg-pink-400',    label: 'Transferred Disposal', hex: '#ec4899' },
  DISP_DESTRUCTED:    { bar: 'bg-red-600',     dot: 'bg-red-500',     label: 'Destructed',           hex: '#dc2626' },
  ARCHIVED:           { bar: 'bg-zinc-500',    dot: 'bg-zinc-400',    label: 'Archived',             hex: '#71717a' },
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

function QuickActions({ isAdmin }) {
  const actions = [
    {
      label: isAdmin ? 'Add Asset' : 'My Office Assets',
      desc: isAdmin ? 'Register new equipment' : 'View and update your assets',
      to: '/assets',
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
      label: 'Reports', desc: 'RPCPPE, IIRUP & more', to: '/reports?report=rpcppe',
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

function LifecycleDistribution({ lifecycleDist, total, loading }) {
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
                  <div key={s} className="flex items-center gap-2">
                    <span className={`w-2 h-2 rounded-full flex-shrink-0 ${cfg.dot}`} />
                    <span className="text-xs text-slate-500 dark:text-zinc-400 flex-1 truncate">{cfg.label}</span>
                    <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums">{count}</span>
                    <span className="text-[10px] text-slate-400 dark:text-zinc-600 tabular-nums w-7 text-right">{pct}%</span>
                  </div>
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

// How many assets were maintained / disposed over a period, vs. the period before, with an
// on-demand AI summary (LifecycleInsightService). Staff see only their office.
const INSIGHT_RANGES = [
  { key: 'day',   label: 'Day' },
  { key: 'week',  label: 'Week' },
  { key: 'month', label: 'Month' },
  { key: 'year',  label: 'Year' },
]

function InsightDelta({ now, before }) {
  if (now === before) return <span className="text-2xs text-slate-400 dark:text-zinc-500">same as previous period</span>
  const up = now > before
  const pct = before > 0 ? `${Math.round((Math.abs(now - before) / before) * 100)}%` : null
  return (
    <span className={`text-2xs font-medium ${up ? 'text-amber-500' : 'text-emerald-500'}`}>
      {up ? '▲' : '▼'} {pct ? `${pct} ` : ''}{up ? 'more' : 'fewer'} than previous period ({before})
    </span>
  )
}

function bucketLabel(bucket, range) {
  if (range === 'year') return new Date(`${bucket}-01T00:00:00`).toLocaleDateString('en-PH', { month: 'short' })
  const d = new Date(`${bucket}T00:00:00`)
  return range === 'week' ? d.toLocaleDateString('en-PH', { weekday: 'short' }) : String(d.getDate())
}

function LifecycleInsights({ refreshToken }) {
  const [range, setRange]       = useState('month')
  const [data, setData]         = useState(null)
  const [loading, setLoading]   = useState(true)
  const [summaries, setSummaries] = useState({})   // range -> AI text
  const [generating, setGenerating] = useState(false)
  const [aiError, setAiError]   = useState('')

  useEffect(() => {
    let alive = true
    setLoading(true)
    getLifecycleInsights(range)
      .then(({ data }) => { if (alive) setData(data) })
      .catch(() => { if (alive) setData(null) })
      .finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [range, refreshToken])

  const generate = async () => {
    setGenerating(true)
    setAiError('')
    try {
      const { data } = await generateLifecycleSummary(range)
      setData(data)
      setSummaries((prev) => ({ ...prev, [range]: data.summary }))
    } catch (err) {
      setAiError(err.response?.data?.message || 'Could not generate the summary.')
    } finally {
      setGenerating(false)
    }
  }

  const m = data?.maintenance
  const d = data?.disposal
  const series = m ? m.series.map((p, i) => ({ bucket: p.bucket, maint: p.assets, disp: d.series[i]?.assets || 0 })) : []
  const max = Math.max(1, ...series.map((p) => Math.max(p.maint, p.disp)))
  const labelStride = series.length > 14 ? Math.ceil(series.length / 8) : 1
  const summary = summaries[range]

  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Maintenance &amp; Disposal Summary</p>
          {data && <span className="text-xs text-slate-400 dark:text-zinc-600">{data.label} · {fmtDateShort(data.from)} – {fmtDateShort(data.to)}</span>}
        </div>
        <div className="inline-flex items-center rounded-lg border border-slate-200 dark:border-zinc-700 bg-slate-50 dark:bg-zinc-800/60 p-0.5">
          {INSIGHT_RANGES.map((opt) => (
            <button key={opt.key} onClick={() => { setRange(opt.key); setAiError('') }}
              className={`px-2.5 py-1 rounded-md text-2xs font-medium transition-all duration-150 ${
                range === opt.key
                  ? 'bg-white dark:bg-zinc-900 text-slate-900 dark:text-zinc-100 shadow-sm'
                  : 'text-slate-400 dark:text-zinc-500 hover:text-slate-600 dark:hover:text-zinc-300'
              }`}>{opt.label}</button>
          ))}
        </div>
      </div>

      <div className="px-5 py-4 space-y-4">
        {loading && !data ? (
          <div className="grid grid-cols-2 gap-4"><Sk className="h-14" /><Sk className="h-14" /></div>
        ) : !data ? (
          <p className="text-sm text-slate-400 dark:text-zinc-500">Couldn't load maintenance and disposal activity.</p>
        ) : (
          <>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <p className="text-2xs font-semibold uppercase tracking-wider text-amber-500">Maintained</p>
                <p className="text-2xl font-semibold text-slate-900 dark:text-white tabular-nums">{m.assets.toLocaleString()} <span className="text-sm font-normal text-slate-400 dark:text-zinc-500">asset{m.assets !== 1 ? 's' : ''}</span></p>
                <InsightDelta now={m.assets} before={m.previousAssets} />
                <p className="text-2xs text-slate-400 dark:text-zinc-500 mt-0.5">{m.records} record{m.records !== 1 ? 's' : ''} · cost {fmtMoney(Number(m.totalCost) || 0)}</p>
              </div>
              <div>
                <p className="text-2xs font-semibold uppercase tracking-wider text-red-400">Disposed</p>
                <p className="text-2xl font-semibold text-slate-900 dark:text-white tabular-nums">{d.assets.toLocaleString()} <span className="text-sm font-normal text-slate-400 dark:text-zinc-500">asset{d.assets !== 1 ? 's' : ''}</span></p>
                <InsightDelta now={d.assets} before={d.previousAssets} />
                <p className="text-2xs text-slate-400 dark:text-zinc-500 mt-0.5">{d.records} record{d.records !== 1 ? 's' : ''} · proceeds {fmtMoney(Number(d.totalProceeds) || 0)}</p>
              </div>
            </div>

            {series.length > 1 && (
              <div className="flex flex-col gap-1.5">
                <div className="flex items-end gap-1" style={{ height: '64px' }}>
                  {series.map((p) => (
                    <div key={p.bucket} className="flex-1 h-full flex items-end justify-center gap-px min-w-0"
                      title={`${p.bucket}: ${p.maint} maintained, ${p.disp} disposed`}>
                      <div className="w-1/2 rounded-sm bg-amber-500/70" style={{ height: `${p.maint === 0 ? 2 : Math.max((p.maint / max) * 60, 4)}px` }} />
                      <div className="w-1/2 rounded-sm bg-red-400/70" style={{ height: `${p.disp === 0 ? 2 : Math.max((p.disp / max) * 60, 4)}px` }} />
                    </div>
                  ))}
                </div>
                <div className="flex gap-1">
                  {series.map((p, i) => (
                    <span key={p.bucket} className="flex-1 text-center text-2xs text-slate-400 dark:text-zinc-600 truncate">
                      {i % labelStride === 0 ? bucketLabel(p.bucket, range) : ''}
                    </span>
                  ))}
                </div>
              </div>
            )}

            <div className="rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-950/50 px-4 py-3">
              <div className="flex items-center justify-between gap-3">
                <p className="text-2xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">AI Summary</p>
                <button onClick={generate} disabled={generating}
                  className="text-xs font-semibold text-brand-500 dark:text-brand-400 hover:text-brand-600 dark:hover:text-brand-300 disabled:opacity-50 transition-colors">
                  {generating ? 'Generating…' : summary ? 'Regenerate' : 'Generate summary'}
                </button>
              </div>
              {aiError ? (
                <p className="text-xs text-red-400 mt-2">{aiError}</p>
              ) : summary ? (
                <p className="text-sm text-slate-600 dark:text-zinc-300 leading-relaxed mt-2">{summary}</p>
              ) : (
                <p className="text-xs text-slate-400 dark:text-zinc-500 mt-2">
                  Get a plain-language summary of this period's maintenance and disposal activity, written by AI from the numbers above.
                </p>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function fmtDateShort(iso) {
  return new Date(`${iso}T00:00:00`).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })
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
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 flex flex-col h-full">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Assets by Category</p>
        {!loading && <span className="text-xs text-slate-400 dark:text-zinc-600 tabular-nums">{total} total</span>}
      </div>
      <div className="p-4 flex-1 flex flex-col justify-around gap-3">
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

// Admin inbox for staff requests — maintenance / disposal records a STAFF account added,
// waiting to be approved or rejected (see ApprovalControls). Updates live via the
// dashboard's SSE reload, so it doubles as the admin's request notification.
const PENDING_PREVIEW = 6

function PendingApprovals({ requests, loading, onApprove, onReject, busyId }) {
  const count = requests.length
  const shown = requests.slice(0, PENDING_PREVIEW)
  const kinds = new Set(requests.map((r) => r.kind))
  const viewAll = kinds.size === 1 && kinds.has('disposal') ? '/disposal?pending=1' : '/maintenance?pending=1'

  return (
    <div className={`bg-white dark:bg-zinc-900 rounded-xl border ${count > 0 ? 'border-amber-500/40' : 'border-slate-200 dark:border-zinc-800'}`}>
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          {count > 0 && (
            <span className="relative flex h-2.5 w-2.5">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75" />
              <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-amber-500" />
            </span>
          )}
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Pending Approvals</p>
          {!loading && (
            <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${count > 0 ? 'bg-amber-500/10 text-amber-600 dark:text-amber-400' : 'bg-slate-100 dark:bg-zinc-800 text-slate-500 dark:text-zinc-400'}`}>
              {count}
            </span>
          )}
        </div>
        {count > PENDING_PREVIEW && (
          <Link to={viewAll} className="text-xs text-brand-400 hover:text-brand-300 font-medium transition-colors duration-150">View all</Link>
        )}
      </div>
      {loading ? (
        <div className="divide-y divide-slate-100 dark:divide-zinc-800/70">
          {Array.from({ length: 2 }).map((_, i) => (
            <div key={i} className="px-5 py-3.5 flex items-center gap-3">
              <Sk className="w-20 h-5 rounded flex-shrink-0" />
              <div className="flex-1 space-y-2"><Sk className="h-3.5 w-2/3" /><Sk className="h-3 w-1/3" /></div>
            </div>
          ))}
        </div>
      ) : count === 0 ? (
        <p className="px-5 py-4 text-sm text-slate-400 dark:text-zinc-500">No maintenance or disposal requests are waiting for approval.</p>
      ) : (
        <div className="divide-y divide-slate-100 dark:divide-zinc-800/70">
          {shown.map((r) => {
            const isMaint = r.kind === 'maintenance'
            const detail = isMaint
              ? `${r.maintenanceType || ''}${r.findings ? ` · ${r.findings}` : ''}`
              : `${r.recommendedMethod || ''}${r.reason ? ` · ${r.reason}` : ''}`
            return (
              <div key={`${r.kind}:${r.id}`} className="px-5 py-3 flex items-center gap-3 hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                <span className={`flex-shrink-0 inline-flex items-center px-2 py-0.5 rounded text-2xs font-semibold leading-none whitespace-nowrap ${isMaint ? 'text-amber-500 bg-amber-500/10' : 'text-red-400 bg-red-400/10'}`}>
                  {isMaint ? 'Maintenance' : 'Disposal'}
                </span>
                <Link to={`/${r.kind}?assetId=${r.asset?.id ?? ''}&pending=1`} className="flex-1 min-w-0 group">
                  <p className="text-sm text-slate-700 dark:text-zinc-200 leading-snug truncate font-medium group-hover:text-slate-900 dark:group-hover:text-white">
                    <span className="font-mono text-xs text-slate-400 dark:text-zinc-500 mr-1.5">{r.asset?.propertyNumber}</span>
                    {r.asset?.description || '—'}
                  </p>
                  <p className="text-xs text-slate-400 dark:text-zinc-500 mt-0.5 leading-snug truncate">
                    {detail}{r.requestedByName ? ` — requested by ${r.requestedByName}` : ''}
                  </p>
                </Link>
                <time className="hidden sm:block flex-shrink-0 text-xs text-slate-400 dark:text-zinc-600 whitespace-nowrap tabular-nums">{timeAgo(r.createdAt)}</time>
                <div className="flex items-center gap-1 flex-shrink-0">
                  <button onClick={() => onApprove(r)} disabled={busyId === `${r.kind}:${r.id}`}
                    className="px-2.5 py-1.5 rounded-md text-xs font-semibold text-emerald-600 dark:text-emerald-400 hover:bg-emerald-500/10 disabled:opacity-40 transition-all duration-150">
                    Approve
                  </button>
                  <button onClick={() => onReject(r)} disabled={busyId === `${r.kind}:${r.id}`}
                    className="px-2.5 py-1.5 rounded-md text-xs font-semibold text-red-500 dark:text-red-400 hover:bg-red-500/10 disabled:opacity-40 transition-all duration-150">
                    Reject
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── Dashboard ─────────────────────────────────────────────────────────────────
function Dashboard() {
  const dispatch = useDispatch()
  const navigate = useNavigate()
  // Staff only ever receive their own office's data from the API (see AccessService);
  // the admin-only parts of the page (account count, office distribution) are hidden for them.
  const user     = useSelector((s) => s.auth.user)
  const isAdmin  = user?.role === 'ADMIN'
  const toast    = useToast()
  const [rejecting, setRejecting] = useState(null)
  const [busyId, setBusyId]       = useState(null)

  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState(false)
  const [assets, setLocalAssets] = useState([])
  const [history, setHistory]   = useState([])
  const [userCount, setUserCount] = useState(0)
  const [maintenanceRecords, setMaintenanceRecords] = useState([])
  const [disposalRecords, setDisposalRecords] = useState([])
  const [activityRange, setActivityRange] = useState('week')
  const [insightToken, setInsightToken] = useState(0)   // bumps on every (re)load so the summary card refetches

  const load = useCallback(({ silent = false } = {}) => {
    if (!silent) { setLoading(true); setError(false) }
    Promise.all([
      getAssets().catch(() => null),
      getAssetHistory().catch(() => null),
      isAdmin ? getUsers().catch(() => null) : Promise.resolve(null),
      getMaintenance().catch(() => null),
      getDisposal().catch(() => null),
    ]).then(([assetRes, histRes, userRes, maintRes, dispRes]) => {
      if (!assetRes && !histRes) {
        if (!silent) { setError(true); setLoading(false) }
        return
      }
      const a = assetRes?.data ?? []
      const h = histRes?.data  ?? []
      const u = userRes?.data  ?? []
      setLocalAssets(a)
      dispatch(setAssets(a))
      setHistory(h)
      setUserCount(u.length)
      setMaintenanceRecords(maintRes?.data ?? [])
      setDisposalRecords(dispRes?.data ?? [])
      setInsightToken((t) => t + 1)
      if (!silent) setLoading(false)
    })
  }, [dispatch, isAdmin])

  useEffect(() => { load() }, [load])

  // Coalesce bursts of events (e.g. an asset condition change that cascades
  // into maintenance + disposal records) into a single reload.
  const reloadTimerRef = useRef(null)
  const scheduleReload = useCallback(() => {
    clearTimeout(reloadTimerRef.current)
    reloadTimerRef.current = setTimeout(() => load({ silent: true }), 300)
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

  // Every asset is counted exactly once, so this always sums to totalAssets.
  // Registered+Assigned merge into one bucket; an UNDER_MAINTENANCE/DISPOSED
  // asset is further split into its 3 sub-buckets by looking up that asset's
  // own active maintenance/disposal ledger record (there's at most one, per
  // handleConditionLedger's delete-on-transition design) rather than counting
  // ledger rows independently — a ledger record for an asset that's since
  // moved on (e.g. repaired and now SERVICEABLE again) isn't double-counted.
  const maintByAsset = {}
  const approved = (r) => !r.approvalStatus || r.approvalStatus === 'APPROVED' // skip pending/rejected requests
  maintenanceRecords.forEach((m) => { if (m.asset?.id != null && approved(m)) maintByAsset[m.asset.id] = m })
  const dispByAsset = {}
  disposalRecords.forEach((d) => { if (d.asset?.id != null && approved(d)) dispByAsset[d.asset.id] = d })

  const lifecycleDist = {}
  assets.forEach((a) => {
    const status = a.lifecycleStatus
    let key
    if (status === 'REGISTERED' || status === 'ASSIGNED') key = 'REGISTERED'
    else if (status === 'TRANSFERRED' || status === 'ARCHIVED') key = status
    else if (status === 'UNDER_MAINTENANCE') {
      const m = maintByAsset[a.id]
      key = m?.status === 'SCHEDULED' ? 'MAINT_SCHEDULED'
        : m?.status === 'COMPLETED' ? 'MAINT_REPAIRED'
        : 'MAINT_ONGOING'
    } else if (status === 'DISPOSED') {
      const d = dispByAsset[a.id]
      key = d?.disposalStatus !== 'COMPLETED' ? 'DISP_PENDING'
        : d.recommendedMethod === 'TRANSFER' ? 'DISP_TRANSFERRED'
        : 'DISP_DESTRUCTED'
    }
    if (key) lifecycleDist[key] = (lifecycleDist[key] || 0) + 1
  })
  const lifecycleTotal = Object.values(lifecycleDist).reduce((s, c) => s + c, 0)

  const officeDist     = useMemo(() => computeOfficeDist(assets), [assets])
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


  const animAssets  = useCountUp(totalAssets,     !loading)
  const animValue   = useCountUp(Math.round(totalValue), !loading)
  const animMaint   = useCountUp(underMaintenance, !loading)
  // newest first — the admin's request inbox (and the staff "Awaiting Approval" count)
  const pendingList = useMemo(() => [
    ...maintenanceRecords.map((r) => ({ ...r, kind: 'maintenance' })),
    ...disposalRecords.map((r) => ({ ...r, kind: 'disposal' })),
  ].filter((r) => r.approvalStatus === 'PENDING_APPROVAL')
   .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0)), [maintenanceRecords, disposalRecords])
  const pendingRequests = pendingList.length

  const approveRequest = async (r) => {
    setBusyId(`${r.kind}:${r.id}`)
    try {
      await (r.kind === 'maintenance' ? approveMaintenance : approveDisposal)(r.id)
      toast.show(`${r.kind === 'maintenance' ? 'Maintenance' : 'Disposal'} request approved.`, 'success')
      load({ silent: true })
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to approve the request.', 'error')
    } finally {
      setBusyId(null)
    }
  }

  const rejectRequest = async (note) => {
    const r = rejecting
    await (r.kind === 'maintenance' ? rejectMaintenance : rejectDisposal)(r.id, note)
    toast.show('Request rejected.', 'warning')
    load({ silent: true })
  }
  const animUsers   = useCountUp(isAdmin ? userCount : pendingRequests, !loading)

  const today = now.toLocaleDateString('en-PH', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })

  const stats = [
    {
      label: 'Assets', value: animAssets.toLocaleString(),
      sub: isAdmin ? 'Total registered assets' : `Assets in ${user?.officeName || 'your office'}`, delta: newThisMonth, href: '/assets',
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
    isAdmin ? {
      label: 'Accounts', value: animUsers.toLocaleString(),
      sub: 'Admin and staff users', href: '/accounts',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path d="M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z" /></svg>,
    } : {
      label: 'Awaiting Approval', value: animUsers.toLocaleString(),
      sub: 'Maintenance & disposal requests', href: '/maintenance',
      icon: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clipRule="evenodd" /></svg>,
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

      {isAdmin && (
        <div className="mb-5">
          <PendingApprovals requests={pendingList} loading={loading} busyId={busyId}
            onApprove={approveRequest} onReject={setRejecting} />
        </div>
      )}

      {/* Quick Actions */}
      <div className="mb-5">
        <QuickActions isAdmin={isAdmin} />
      </div>

      {/* Condition + Lifecycle + Office row */}
      <div className={`grid grid-cols-1 ${isAdmin ? 'lg:grid-cols-3' : 'lg:grid-cols-2'} gap-5 mb-5`}>
        <ConditionDistribution condDist={condDist} total={totalAssets} loading={loading}
          onSelect={(cond) => navigate(`/assets?condition=${cond}`)} />
        <LifecycleDistribution lifecycleDist={lifecycleDist} total={lifecycleTotal} loading={loading} />
        {isAdmin && (
          <OfficeDistribution offices={officeDist} total={totalAssets} loading={loading}
            onSelect={(officeId) => navigate(`/assets?office=${officeId}`)} />
        )}
      </div>

      {/* Activity trend */}
      <div className="mb-5">
        <ActivityTrend trend={activityTrend} loading={loading} range={activityRange} onRangeChange={setActivityRange} />
      </div>

      {/* Maintenance & disposal over a period + AI summary */}
      <div className="mb-5">
        <LifecycleInsights refreshToken={insightToken} />
      </div>

      {/* Activity feed + category breakdown */}
      {/* grid items stretch, so both cards share the taller one's height */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_300px] gap-5">
        <ActivityFeed events={recentEvents} loading={loading} />
        <CategoryBreakdown breakdown={categoryBreakdown} total={totalAssets} loading={loading}
          onSelect={(categoryId) => navigate(`/assets?category=${categoryId}`)} />
      </div>
      {rejecting && (
        <RejectRequestModal
          record={rejecting}
          describe={(r) => `${r.kind === 'maintenance' ? 'Maintenance' : 'Disposal'} — ${r.asset?.propertyNumber || ''} ${r.asset?.description || ''}`}
          onClose={() => setRejecting(null)}
          onConfirm={rejectRequest}
        />
      )}
    </MainLayout>
  )
}

export default Dashboard
