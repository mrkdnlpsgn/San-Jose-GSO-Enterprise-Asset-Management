import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { useDispatch, useSelector } from 'react-redux'
import { setAssets } from '../../store/slices/assetSlice'
import { getAssets } from '../../services/assetService'
import { Link, useNavigate } from 'react-router-dom'
import MainLayout from '../../components/layout/MainLayout'
import { getDashboardSummary } from '../../services/dashboardService'
import { getEditRequests } from '../../services/assetHistoryService'
import { getUsers } from '../../services/userService'
import { getPlanning, generatePlanningSummary } from '../../services/aiRecommendationService'
import { approveMaintenance, rejectMaintenance } from '../../services/maintenanceService'
import { approveDisposal, rejectDisposal } from '../../services/disposalService'
import { approveTransfer, rejectTransfer } from '../../services/transferService'
import { useToast } from '../../context/ToastContext'
import { RejectRequestModal } from '../../components/common/ApprovalControls'
import ConfirmDialog from '../../components/common/ConfirmDialog'
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

// ── Helpers ───────────────────────────────────────────────────────────────────
function timeAgo(dt) {
  if (!dt) return 'N/A'
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

const fmtNum = (n) => Number(n).toLocaleString('en-PH')

// A non-zero count never shows as 0%.
function fmtPct(count, total) {
  if (!total || !count) return '0%'
  const pct = Math.round((count / total) * 100)
  return pct === 0 ? '<1%' : `${pct}%`
}

const assetLink = (propertyNumber) => `/assets?search=${encodeURIComponent(propertyNumber || '')}`

const CONDITION_ORDER = ['NEW', 'GOOD', 'SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE']
const CONDITION_CFG = {
  NEW:           { bar: 'bg-sky-500',     text: 'text-sky-400',     dot: 'bg-sky-400',     label: 'New' },
  GOOD:          { bar: 'bg-teal-500',    text: 'text-teal-400',    dot: 'bg-teal-400',    label: 'Good' },
  SERVICEABLE:   { bar: 'bg-emerald-500', text: 'text-emerald-400', dot: 'bg-emerald-400', label: 'Serviceable' },
  REPAIRABLE:    { bar: 'bg-amber-500',   text: 'text-amber-400',   dot: 'bg-amber-400',   label: 'Repairable' },
  UNSERVICEABLE: { bar: 'bg-red-500',     text: 'text-red-400',     dot: 'bg-red-400',     label: 'Unserviceable' },
}

// Staff requests (maintenance / disposal / transfer) come from /asset-history/requests in one
// shape; kind is upper-case there. The API calls and wording for each kind:
const REQUEST_KIND = {
  MAINTENANCE: { label: 'Maintenance', badge: 'text-amber-700 dark:text-amber-300 bg-amber-500/10',  approve: approveMaintenance, reject: rejectMaintenance },
  DISPOSAL:    { label: 'Disposal',    badge: 'text-red-700 dark:text-red-300 bg-red-500/10',      approve: approveDisposal,    reject: rejectDisposal },
  TRANSFER:    { label: 'Transfer',    badge: 'text-violet-700 dark:text-violet-300 bg-violet-500/10', approve: approveTransfer,    reject: rejectTransfer },
}
const REQUESTS_LINK = (status) => `/asset-history?view=requests&status=${status}`
const REJECTED_RECENT_DAYS = 14

const TOP_OFFICES = 6

// ── Skeleton ──────────────────────────────────────────────────────────────────
function Sk({ className, style }) {
  return <div className={`animate-pulse rounded bg-slate-200 dark:bg-zinc-800 ${className}`} style={style} />
}

// ── Sub-components ────────────────────────────────────────────────────────────

function StatStrip({ stats, loading }) {
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 overflow-hidden">
      {/* Four across when there's room for 14rem each, otherwise two - measured in rem, so it
          follows the Text Size setting. The 1px gap over a tinted background draws the dividers. */}
      <div className="flex flex-wrap gap-px bg-slate-200 dark:bg-zinc-800">
        {stats.map(({ label, value, sub, delta, href, icon, loading: tileLoading }) => (
          <Link
            key={label}
            to={href}
            className="grow basis-[clamp(24%,(56rem_-_100%)_*_999,49%)] min-w-0 group flex items-start gap-3 px-3.5 sm:px-5 py-4 bg-white dark:bg-zinc-900 hover:bg-slate-50 dark:hover:bg-zinc-800/50 transition-colors duration-150"
          >
            <div className="w-8 h-8 rounded-lg bg-slate-100 dark:bg-zinc-800 hidden sm:flex items-center justify-center flex-shrink-0 mt-0.5 text-slate-600 dark:text-zinc-400 group-hover:text-brand-500 dark:group-hover:text-brand-400 group-hover:bg-brand-500/10 transition-all duration-150">
              {icon}
            </div>
            <div className="min-w-0">
              <p className="text-xs font-semibold text-slate-600 dark:text-zinc-400 uppercase tracking-normal sm:tracking-wider leading-tight sm:leading-none [overflow-wrap:anywhere]">{label}</p>
              {loading || tileLoading ? (
                <Sk className="h-7 w-16 mt-2 mb-1" />
              ) : (
                <p className="text-lg sm:text-2xl font-bold text-slate-900 dark:text-white mt-1.5 leading-tight sm:leading-none tabular-nums [overflow-wrap:anywhere]">{value}</p>
              )}
              <div className="flex items-center gap-1.5 mt-1">
                <p className="text-xs text-slate-600 dark:text-zinc-400 leading-tight">{sub}</p>
                {!loading && delta != null && delta > 0 && (
                  <span className="text-xs font-semibold text-emerald-700 dark:text-emerald-300 bg-emerald-500/10 px-1.5 py-0.5 rounded leading-none">
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

// "Needs attention": one row per problem, shown only when there is something to do. A row
// can list the assets behind its count (each opens that asset), since the Assets page has
// no filter for things like "no accountable person".
// assets: the first few matching assets (the server sends up to 10); total: how many match.
function AttentionRow({ tone, text, link, assets, total = assets?.length ?? 0 }) {
  const [open, setOpen] = useState(false)
  const dot = tone === 'red' ? 'bg-red-500' : 'bg-amber-500'
  return (
    <div className="px-5 py-3">
      <div className="flex items-center gap-3">
        <span className={`w-2 h-2 rounded-full flex-shrink-0 ${dot}`} />
        <p className="flex-1 min-w-0 text-sm text-slate-700 dark:text-zinc-200">{text}</p>
        {assets?.length > 0 && (
          <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
            aria-label={`${open ? 'Hide' : 'Show'} the list: ${text}`}
            className="flex-shrink-0 -my-1 px-2 py-1 rounded-md text-sm font-medium text-brand-700 dark:text-brand-300 hover:text-brand-800 dark:hover:text-brand-200 hover:underline transition-colors">
            {open ? 'Hide' : 'Show'}
          </button>
        )}
        {link && (
          <Link to={link.to} aria-label={`${link.label}: ${text}`} className="flex-shrink-0 -my-1 px-2 py-1 rounded-md text-sm font-medium text-brand-700 dark:text-brand-300 hover:text-brand-800 dark:hover:text-brand-200 hover:underline transition-colors">
            {link.label}
          </Link>
        )}
      </div>
      {open && (
        <ul className="mt-2 ml-5 space-y-1">
          {assets.map((a) => (
            <li key={a.id} className="text-xs truncate">
              <Link to={assetLink(a.propertyNumber)} className="text-slate-600 dark:text-zinc-300 hover:text-brand-600 dark:hover:text-brand-400">
                <span className="font-mono text-slate-600 dark:text-zinc-400 mr-1.5">{a.propertyNumber}</span>
                {a.description || 'N/A'}
              </Link>
            </li>
          ))}
          {total > assets.length && (
            <li className="text-xs text-slate-600 dark:text-zinc-400">and {fmtNum(total - assets.length)} more</li>
          )}
        </ul>
      )}
    </div>
  )
}

function NeedsAttention({ items }) {
  if (items.length === 0) return null
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-amber-500/40">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Needs attention</p>
      </div>
      <div className="divide-y divide-slate-100 dark:divide-zinc-800/70">
        {items.map((item) => <AttentionRow key={item.key} {...item} />)}
      </div>
    </div>
  )
}

function ConditionDistribution({ condDist, total, loading, onSelect }) {
  const needAction = (condDist.REPAIRABLE || 0) + (condDist.UNSERVICEABLE || 0)
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800 flex flex-col">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Asset Condition</p>
        {!loading && <span className="text-sm font-medium text-slate-600 dark:text-zinc-400 tabular-nums">{fmtNum(total)} assets</span>}
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
          <p className="text-xs text-slate-600 dark:text-zinc-400 text-center py-6">No assets registered yet.</p>
        ) : (
          <>
            <div aria-hidden="true" className="flex h-2.5 rounded-full overflow-hidden mb-4 gap-px bg-zinc-100 dark:bg-zinc-800">
              {CONDITION_ORDER.map((cond) => {
                const count = condDist[cond] || 0
                if (count === 0) return null
                return (
                  <div
                    key={cond}
                    className={`h-full min-w-[4px] ${CONDITION_CFG[cond].bar} transition-all duration-700`}
                    style={{ width: `${(count / total) * 100}%` }}
                    title={`${CONDITION_CFG[cond].label}: ${fmtNum(count)}`}
                  />
                )
              })}
            </div>
            <div className="space-y-2.5">
              {CONDITION_ORDER.map((cond) => {
                const count = condDist[cond] || 0
                if (count === 0) return null
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
                    <span className="text-xs text-slate-600 dark:text-zinc-400 flex-1 truncate text-left group-hover:text-slate-700 dark:group-hover:text-zinc-200 transition-colors duration-150">{cfg.label}</span>
                    <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums">{fmtNum(count)}</span>
                    <span className="text-xs text-slate-600 dark:text-zinc-400 tabular-nums w-10 text-right">{fmtPct(count, total)}</span>
                  </button>
                )
              })}
            </div>
          </>
        )}
      </div>
      {!loading && total > 0 && (
        // mt-auto pins this to the bottom when the row's taller cards stretch this one
        <div className="mt-auto px-5 py-3 border-t border-slate-200 dark:border-zinc-800 text-xs text-slate-600 dark:text-zinc-400">
          <span className="font-semibold text-slate-700 dark:text-zinc-200 tabular-nums">{fmtNum(needAction)}</span>
          {' '}{needAction === 1 ? 'asset needs' : 'assets need'} repair or disposal
          <span className="text-slate-600 dark:text-zinc-400 tabular-nums"> · {fmtPct(needAction, total)}</span>
        </div>
      )}
    </div>
  )
}

// Bars are scaled to the largest office, so no share-of-total percentage is shown beside them.
function OfficeDistribution({ offices, officeCount, loading, onSelect }) {
  const max = offices[0]?.count || 1
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Assets by Office</p>
        {!loading && officeCount > 0 && (
          <span className="text-sm font-medium text-slate-600 dark:text-zinc-400 tabular-nums">
            {officeCount > offices.length ? `Top ${offices.length} of ${officeCount} offices` : `${officeCount} offices`}
          </span>
        )}
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
          <p className="text-xs text-slate-600 dark:text-zinc-400 text-center py-6">No office data available.</p>
        ) : (
          offices.map(({ office, officeId, count }) => {
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
                  <span className={`text-xs text-slate-600 dark:text-zinc-400 truncate min-w-0 flex-1 leading-tight transition-colors duration-150 ${clickable ? 'group-hover:text-slate-700 dark:group-hover:text-zinc-200' : ''}`} title={office}>{office}</span>
                  <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums flex-shrink-0 ml-2">{fmtNum(count)}</span>
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

function CategoryBreakdown({ breakdown, total, loading, onSelect }) {
  const max = breakdown[0]?.count || 1
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Assets by Category</p>
        {!loading && <span className="text-sm font-medium text-slate-600 dark:text-zinc-400 tabular-nums">{fmtNum(total)} assets</span>}
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
          <p className="text-xs text-slate-600 dark:text-zinc-400 text-center py-6">No assets yet.</p>
        ) : (
          breakdown.map(({ category, categoryId, count }) => {
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
                  <span className={`text-xs text-slate-600 dark:text-zinc-400 truncate min-w-0 flex-1 leading-tight transition-colors duration-150 ${clickable ? 'group-hover:text-slate-700 dark:group-hover:text-zinc-200' : ''}`} title={category}>{category}</span>
                  <div className="flex items-center gap-1.5 flex-shrink-0 ml-2">
                    <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums">{fmtNum(count)}</span>
                    <span className="text-xs text-slate-600 dark:text-zinc-400 tabular-nums w-10 text-right">{fmtPct(count, total)}</span>
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

// "Budget & Planning" (admins only): what needs replacing and when (ReplacementForecastService)
// next to what the assets are worth on the books (DepreciationService), with one AI summary for
// both (PlanningInsightService). The data is loaded by Dashboard, which also uses it for the
// Book Value tile and the "due for replacement" row in Needs attention.
const TOP_PLANNING_CATEGORIES = 5

function PlanningTile({ label, value, sub, highlight }) {
  return (
    <div className={`rounded-lg border px-3 py-2.5 min-w-0 ${highlight
      ? 'border-amber-300 dark:border-amber-500/40 bg-amber-50 dark:bg-amber-500/10'
      : 'border-slate-200 dark:border-zinc-800'}`}>
      <p className="text-xs font-medium text-slate-600 dark:text-zinc-400 leading-tight">{label}</p>
      <p className="text-lg font-semibold text-slate-900 dark:text-white tabular-nums mt-0.5">{value}</p>
      <p className="text-xs text-slate-600 dark:text-zinc-400 tabular-nums">{sub}</p>
    </div>
  )
}

function BudgetPlanning({ data, loading, onChange }) {
  const [generating, setGenerating] = useState(false)
  const [aiError, setAiError]       = useState('')

  const generate = async () => {
    setGenerating(true)
    setAiError('')
    try {
      const { data } = await generatePlanningSummary(true)
      onChange(data)
    } catch (err) {
      setAiError(err.response?.data?.message || 'Could not generate the summary.')
    } finally {
      setGenerating(false)
    }
  }

  const r = data?.replacement
  const d = data?.depreciation?.total
  const year = data?.depreciation?.asOf?.slice(0, 4)
  const categories = (r?.byCategory || []).slice(0, TOP_PLANNING_CATEGORIES)
  const maxCost = Number(categories[0]?.cost) || 1
  const missingLife = r?.excluded?.noExpectedLife || []
  const subhead = 'text-xs font-semibold uppercase tracking-wider text-slate-600 dark:text-zinc-400'

  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
        <div className="min-w-0">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Budget &amp; Planning</p>
          <p className="text-xs text-slate-600 dark:text-zinc-400 mt-px">
            What needs replacing and what the assets are worth on the books
            {data ? `, as of ${new Date(data.depreciation.asOf).toLocaleDateString('en-PH', { year: 'numeric', month: 'long', day: 'numeric' })}` : ''}
          </p>
        </div>
        <div className="flex items-center gap-4 text-xs font-semibold">
          <Link to="/reports?report=replacement" className="text-brand-700 dark:text-brand-300 hover:underline">Replacement forecast</Link>
          <Link to="/reports?report=depreciation" className="text-brand-700 dark:text-brand-300 hover:underline">Depreciation schedule</Link>
        </div>
      </div>

      <div className="px-5 py-4 space-y-5">
        {loading ? (
          <div className="grid grid-cols-1 lg:grid-cols-[3fr_2fr] gap-6">
            <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">{Array.from({ length: 5 }).map((_, i) => <Sk key={i} className="h-16" />)}</div>
            <div className="grid grid-cols-2 gap-3">{Array.from({ length: 4 }).map((_, i) => <Sk key={i} className="h-16" />)}</div>
          </div>
        ) : !data ? (
          <p className="text-sm text-slate-600 dark:text-zinc-400">Couldn't load the budget and planning figures.</p>
        ) : (
          <>
            <div className="grid grid-cols-1 lg:grid-cols-[3fr_2fr] gap-6">
              <section aria-label="Replacement forecast" className="min-w-0 space-y-4">
                <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                  <p className={subhead}>Replacement cost by year</p>
                  <span className="text-xs font-medium text-slate-600 dark:text-zinc-400 tabular-nums">
                    Next {r.years} years: {fmtMoney(r.total.cost)} · {fmtNum(r.total.assets)} assets
                  </span>
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
                  {r.buckets.map((b) => (
                    <div key={b.key} className={b.key === 'NOW' ? 'col-span-2 sm:col-span-1' : ''}>
                      <PlanningTile label={b.label} value={fmtMoney(b.cost)} highlight={b.key === 'NOW' && b.assets > 0}
                        sub={`${fmtNum(b.assets)} ${b.assets === 1 ? 'asset' : 'assets'}`} />
                    </div>
                  ))}
                </div>
                {categories.length > 0 && (
                  <div className="space-y-2.5">
                    {categories.map((c) => (
                      <div key={c.category}>
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-xs text-slate-600 dark:text-zinc-400 truncate min-w-0 flex-1" title={c.category}>
                            {c.category} <span className="text-slate-400 dark:text-zinc-500">({c.usefulLifeYears} yrs)</span>
                          </span>
                          <span className="text-xs font-semibold text-slate-600 dark:text-zinc-300 tabular-nums ml-2">
                            {fmtMoney(c.cost)} <span className="font-normal text-slate-600 dark:text-zinc-400">· {fmtNum(c.assets)}</span>
                          </span>
                        </div>
                        <div className="h-1.5 rounded-full bg-slate-100 dark:bg-zinc-800 overflow-hidden">
                          <div className="h-full w-full rounded-full bg-brand-500 origin-left" style={{ transform: `scaleX(${Number(c.cost) / maxCost})` }} />
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </section>

              <section aria-label="Depreciation" className="min-w-0 space-y-4">
                <p className={subhead}>Asset value on the books</p>
                <div className="grid grid-cols-2 gap-3">
                  <PlanningTile label="Total cost" value={fmtMoney(d.totalCost)} sub={`${fmtNum(d.assets)} assets`} />
                  <PlanningTile label="Book value" value={fmtMoney(d.bookValue)} sub="Cost less depreciation" />
                  <PlanningTile label="Accumulated depreciation" value={fmtMoney(d.accumulatedDepreciation)}
                    sub={`${fmtPct(Number(d.accumulatedDepreciation), Number(d.totalCost))} of cost`} />
                  <PlanningTile label={`Depreciation expense ${year}`} value={fmtMoney(d.depreciationExpense)}
                    sub={`${fmtMoney(d.monthlyDepreciation)} per month`} />
                </div>
                <p className="text-sm text-slate-600 dark:text-zinc-300">
                  <span className="font-semibold text-slate-900 dark:text-white tabular-nums">{fmtNum(d.fullyDepreciated)}</span>
                  {' '}{d.fullyDepreciated === 1 ? 'asset is' : 'assets are'} fully depreciated (only the 5% residual value is left).
                </p>
              </section>
            </div>

            <div className="rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-950/50 px-4 py-3">
              <div className="flex items-center justify-between gap-3">
                <p className={subhead}>AI Summary</p>
                <button onClick={generate} disabled={generating}
                  className="text-xs font-semibold text-brand-700 dark:text-brand-300 hover:text-brand-800 dark:hover:text-brand-200 hover:underline disabled:opacity-50 transition-colors">
                  {generating ? 'Generating…' : data.summary ? 'Regenerate' : 'Generate'}
                </button>
              </div>
              {aiError ? (
                <p className="text-xs text-red-700 dark:text-red-300 mt-2">{aiError}</p>
              ) : data.summary ? (
                <p className="text-sm text-slate-600 dark:text-zinc-300 leading-relaxed mt-2">{data.summary}</p>
              ) : generating ? (
                <p className="text-sm text-slate-600 dark:text-zinc-400 mt-2" role="status">Writing a budget note…</p>
              ) : (
                <p className="text-xs text-slate-600 dark:text-zinc-400 mt-2">A short budget note: what to replace and when, and what the assets are worth on the books.</p>
              )}
            </div>

            <p className="text-xs text-slate-500 dark:text-zinc-500">
              Due now = past its expected life, or unserviceable and awaiting disposal. Replacement costs are acquisition values plus
              {' '}{r.priceIncreasePercent}% a year. Depreciation is straight-line to a 5% residual value. Expected life per category is set on the Categories page.
              {missingLife.length > 0 && ` Not counted (no expected life set): ${missingLife.join(', ')}.`}
            </p>
          </>
        )}
      </div>
    </div>
  )
}

// Staff accounts are scoped to their office's assets (see AccessService), so an
// active staff account with no office sees nothing until one is assigned.
function UnassignedOffices({ accounts }) {
  const count = accounts.length
  const names = accounts.slice(0, 3).map((u) => u.fullName || u.username)
  const more  = count - names.length

  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-amber-500/40 px-5 py-4 flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4" role="status">
      <div className="w-9 h-9 rounded-full bg-amber-50 dark:bg-amber-950 flex items-center justify-center shrink-0">
        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-amber-500 dark:text-amber-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
        </svg>
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">
          {count === 1 ? '1 staff account has no office assigned' : `${count} staff accounts have no office assigned`}
        </p>
        <p className="text-sm text-slate-600 dark:text-zinc-400 mt-0.5">
          {names.join(', ')}{more > 0 ? ` and ${more} more` : ''}: {count === 1 ? 'this account' : 'these accounts'} can't see any assets until an office is assigned.
        </p>
      </div>
      <Link
        to="/personnel"
        className="shrink-0 inline-flex items-center justify-center px-4 py-2 text-sm font-semibold rounded-md bg-brand-700 text-white hover:bg-brand-800 transition-colors duration-150"
      >
        Assign offices
      </Link>
    </div>
  )
}

// Admin inbox for staff requests waiting to be approved or rejected. Updates live via the
// dashboard's SSE reload, so it doubles as the admin's request notification.
const PENDING_PREVIEW = 6

function PendingApprovals({ requests, loading, failed, onRetry, onApprove, onReject, busyId }) {
  const count = requests.length
  const shown = requests.slice(0, PENDING_PREVIEW)

  return (
    <div className={`bg-white dark:bg-zinc-900 rounded-xl border ${count > 0 || failed ? 'border-amber-500/40' : 'border-slate-200 dark:border-zinc-800'}`}>
      <div className="px-5 py-3.5 border-b border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <p className="text-sm font-semibold text-slate-700 dark:text-zinc-200">Pending Approvals</p>
          {!loading && !failed && (
            <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${count > 0 ? 'bg-amber-500/10 text-amber-800 dark:text-amber-300' : 'bg-slate-100 dark:bg-zinc-800 text-slate-600 dark:text-zinc-400'}`}>
              {count}
            </span>
          )}
        </div>
        {count > PENDING_PREVIEW && (
          <Link to={REQUESTS_LINK('PENDING_APPROVAL')} className="text-xs text-brand-700 dark:text-brand-300 hover:text-brand-800 dark:hover:text-brand-200 hover:underline font-medium transition-colors duration-150">View all {count}</Link>
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
      ) : failed ? (
        // Never show "nothing waiting" when the list simply didn't load.
        <div className="px-5 py-4 flex items-center justify-between gap-3">
          <p className="text-sm text-red-700 dark:text-red-300">Couldn't load requests, so some may be waiting.</p>
          <button onClick={onRetry} className="text-xs font-semibold text-brand-700 dark:text-brand-300 hover:text-brand-800 dark:hover:text-brand-200 hover:underline">Try again</button>
        </div>
      ) : count === 0 ? (
        <p className="px-5 py-4 text-sm text-slate-600 dark:text-zinc-400">No maintenance, disposal or transfer requests are waiting for approval.</p>
      ) : (
        <div className="divide-y divide-slate-100 dark:divide-zinc-800/70">
          {shown.map((r) => {
            const cfg = REQUEST_KIND[r.kind]
            const key = `${r.kind}:${r.recordId}`
            return (
              <div key={key} className="px-5 py-3 flex items-center gap-3 hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100">
                <span className={`flex-shrink-0 inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold leading-none whitespace-nowrap ${cfg.badge}`}>
                  {cfg.label}
                </span>
                <Link to={assetLink(r.propertyNumber)} className="flex-1 min-w-0 group">
                  <p className="text-sm text-slate-700 dark:text-zinc-200 leading-snug truncate font-medium group-hover:text-slate-900 dark:group-hover:text-white">
                    <span className="font-mono text-xs text-slate-600 dark:text-zinc-400 mr-1.5">{r.propertyNumber}</span>
                    {r.assetDescription || 'N/A'}
                  </p>
                  <p className="text-xs text-slate-600 dark:text-zinc-400 mt-0.5 leading-snug truncate">
                    {r.detail}{r.requestedByName ? `, requested by ${r.requestedByName}` : ''}
                  </p>
                </Link>
                <time className="hidden sm:block flex-shrink-0 text-xs text-slate-600 dark:text-zinc-400 whitespace-nowrap tabular-nums">{timeAgo(r.requestedAt)}</time>
                <div className="flex items-center gap-1 flex-shrink-0">
                  <button onClick={() => onApprove(r)} disabled={busyId === key}
                    aria-label={`Approve ${cfg.label.toLowerCase()} request for ${r.propertyNumber}`}
                    className="px-2.5 py-1.5 rounded-md text-xs font-semibold text-emerald-700 dark:text-emerald-300 hover:bg-emerald-500/10 disabled:opacity-40 transition-all duration-150">
                    Approve
                  </button>
                  <button onClick={() => onReject(r)} disabled={busyId === key}
                    aria-label={`Reject ${cfg.label.toLowerCase()} request for ${r.propertyNumber}`}
                    className="px-2.5 py-1.5 rounded-md text-xs font-semibold text-red-700 dark:text-red-300 hover:bg-red-500/10 disabled:opacity-40 transition-all duration-150">
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

const ICONS = {
  assets: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M3 5a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2.22l.123.489.804.804A1 1 0 0113 18H7a1 1 0 01-.707-1.707l.804-.804L7.22 15H5a2 2 0 01-2-2V5zm5.771 7H5V5h10v7H8.771z" clipRule="evenodd" /></svg>,
  value:  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path d="M8.433 7.418c.155-.103.346-.196.567-.267v1.698a2.305 2.305 0 01-.567-.267C8.07 8.34 8 8.114 8 8c0-.114.07-.34.433-.582zM11 12.849v-1.698c.22.071.412.164.567.267.364.243.433.468.433.582 0 .114-.07.34-.433.582a2.305 2.305 0 01-.567.267z" /><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-13a1 1 0 10-2 0v.092a4.535 4.535 0 00-1.676.662C6.602 6.234 6 7.009 6 8c0 .99.602 1.765 1.324 2.246.48.32 1.054.545 1.676.662v1.941c-.391-.127-.68-.317-.843-.504a1 1 0 10-1.51 1.31c.562.649 1.413 1.076 2.353 1.253V15a1 1 0 102 0v-.092a4.535 4.535 0 001.676-.662C13.398 13.766 14 12.991 14 12c0-.99-.602-1.765-1.324-2.246A4.535 4.535 0 0011 9.092V7.151c.391.127.68.317.843.504a1 1 0 101.511-1.31c-.563-.649-1.413-1.076-2.354-1.253V5z" clipRule="evenodd" /></svg>,
  repair: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" /></svg>,
  dispose: <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" /></svg>,
}

// ── Dashboard ─────────────────────────────────────────────────────────────────
function Dashboard() {
  const navigate = useNavigate()
  // Staff only ever receive their own office's data from the API (see AccessService);
  // the admin-only parts of the page (approvals, offices, unassigned staff) are hidden for them.
  const dispatch = useDispatch()
  const user     = useSelector((s) => s.auth.user)
  const isAdmin  = user?.role === 'ADMIN'
  const cachedAssetCount = useSelector((s) => s.assets.items.length)
  const toast    = useToast()
  const [rejecting, setRejecting]   = useState(null)
  const [approving, setApproving]   = useState(null)   // disposal waiting for the confirm dialog
  const [busyId, setBusyId]         = useState(null)

  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState(false)
  const [summary, setSummary]   = useState(null)   // asset numbers worked out by the server
  const [unassignedStaff, setUnassignedStaff] = useState([])
  const [requests, setRequests] = useState([])
  const [requestsFailed, setRequestsFailed] = useState(false)
  const [insightToken, setInsightToken] = useState(0)   // bumps on every quiet reload so Budget & Planning refetches

  const load = useCallback(({ silent = false } = {}) => {
    if (!silent) { setLoading(true); setError(false) }
    Promise.all([
      getDashboardSummary().catch(() => null),
      isAdmin ? getUsers().catch(() => null) : Promise.resolve(null),
      // Admin: everyone's requests. Staff: the backend returns only their own.
      getEditRequests().catch(() => null),
    ]).then(([sumRes, userRes, reqRes]) => {
      if (!sumRes) {
        if (!silent) { setError(true); setLoading(false) }
        return
      }
      if (sumRes) setSummary(sumRes.data)
      setUnassignedStaff((userRes?.data ?? []).filter((x) => x.role === 'STAFF' && x.isActive && !x.officeId && !x.officeName))
      setRequests(reqRes?.data ?? [])
      setRequestsFailed(!reqRes)
      if (silent) setInsightToken((t) => t + 1)  // Budget & Planning loads itself on first open
      if (!silent) setLoading(false)
    })
  }, [isAdmin])

  // Budget & Planning (admins only), loaded after the main numbers so it doesn't slow them down.
  // Also feeds the Book Value tile and the "due for replacement" row in Needs attention.
  const [planning, setPlanning]               = useState(null)
  const [planningLoading, setPlanningLoading] = useState(true)
  useEffect(() => {
    if (!isAdmin || loading) return
    let alive = true
    getPlanning()
      .then(({ data }) => { if (alive) setPlanning(data) })
      .catch(() => { if (alive) setPlanning(null) })
      .finally(() => { if (alive) setPlanningLoading(false) })
    return () => { alive = false }
  }, [isAdmin, loading, insightToken])

  // Once the dashboard is in, quietly load the asset list (the slim one) so Assets and Transfer
  // Asset open at once from it and refresh in the background.
  useEffect(() => {
    if (loading || cachedAssetCount > 0) return
    const timer = setTimeout(() => {
      getAssets('', { summary: true }).then(({ data }) => dispatch(setAssets(data))).catch(() => {})
    }, 1000)
    return () => clearTimeout(timer)
  }, [loading]) // eslint-disable-line react-hooks/exhaustive-deps

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

  // ── Numbers (from /api/dashboard/summary) ──────────────────────────────────
  // The server applies the rules: "in use" leaves out archived assets and finished disposals;
  // "under repair" is maintenance not yet finished.
  const totalAssets  = summary?.inUse ?? 0
  const totalValue   = Number(summary?.totalValue ?? 0)
  const newThisMonth = summary?.newThisMonth ?? 0
  const underRepair  = summary?.underRepair ?? 0
  const forDisposal  = summary?.forDisposal ?? 0
  const condDist     = summary?.condition ?? {}
  const officeDist   = summary?.offices ?? []
  const categoryBreakdown = (summary?.categories ?? []).slice(0, 6)

  // Requests, newest first.
  const pendingList = useMemo(() => requests
    .filter((r) => r.approvalStatus === 'PENDING_APPROVAL' && REQUEST_KIND[r.kind])
    .sort((a, b) => new Date(b.requestedAt || 0) - new Date(a.requestedAt || 0)), [requests])
  const recentlyRejected = useMemo(() => {
    const cutoff = Date.now() - REJECTED_RECENT_DAYS * 86400000
    return requests.filter((r) => r.approvalStatus === 'REJECTED' && new Date(r.reviewedAt || 0).getTime() >= cutoff)
  }, [requests])

  // ── Needs attention ────────────────────────────────────────────────────────
  const att = summary?.attention ?? {}
  const noAccountable = att.noAccountable ?? { count: 0, items: [] }
  const noOffice      = att.noOffice ?? { count: 0, items: [] }
  const unserviceableNoDisposal = att.unserviceableNoDisposal ?? { count: 0, items: [] }
  const plural = (n, one, many) => `${fmtNum(n)} ${n === 1 ? one : many}`

  const attention = []
  if (!isAdmin && pendingList.length > 0) attention.push({
    key: 'mine-pending', tone: 'amber',
    text: `${plural(pendingList.length, 'of your requests is', 'of your requests are')} waiting for admin approval`,
    link: { to: REQUESTS_LINK('PENDING_APPROVAL'), label: 'View' },
  })
  if (!isAdmin && recentlyRejected.length > 0) attention.push({
    key: 'mine-rejected', tone: 'red',
    text: `${plural(recentlyRejected.length, 'of your requests was', 'of your requests were')} rejected in the last ${REJECTED_RECENT_DAYS} days`,
    link: { to: REQUESTS_LINK('REJECTED'), label: 'See reasons' },
  })
  if (!isAdmin && requestsFailed) attention.push({
    key: 'mine-failed', tone: 'red', text: "Couldn't load your requests. Refresh to try again.",
  })
  if (unserviceableNoDisposal.count > 0) attention.push({
    key: 'unserviceable', tone: 'red',
    text: `${plural(unserviceableNoDisposal.count, 'unserviceable asset has', 'unserviceable assets have')} no disposal record yet`,
    assets: unserviceableNoDisposal.items, total: unserviceableNoDisposal.count,
  })
  if (noAccountable.count > 0) attention.push({
    key: 'no-accountable', tone: 'amber',
    text: `${plural(noAccountable.count, 'asset has', 'assets have')} no accountable person`,
    assets: noAccountable.items, total: noAccountable.count,
  })
  if (isAdmin && noOffice.count > 0) attention.push({
    key: 'no-office', tone: 'amber',
    text: `${plural(noOffice.count, 'asset is', 'assets are')} not assigned to an office`,
    assets: noOffice.items, total: noOffice.count,
  })
  const dueNow = planning?.replacement?.buckets?.find((b) => b.key === 'NOW')
  if (isAdmin && dueNow?.assets > 0) attention.push({
    key: 'replace-now', tone: 'amber',
    text: `${plural(dueNow.assets, 'asset is', 'assets are')} due for replacement now (about ${fmtMoney(dueNow.cost)})`,
    link: { to: '/reports?report=replacement', label: 'View' },
  })

  // ── Approvals ──────────────────────────────────────────────────────────────
  const approveRequest = async (r) => {
    const key = `${r.kind}:${r.recordId}`
    setBusyId(key)
    try {
      await REQUEST_KIND[r.kind].approve(r.recordId)
      toast.show(`${REQUEST_KIND[r.kind].label} request approved.`, 'success')
      load({ silent: true })
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to approve the request.', 'error')
    } finally {
      setBusyId(null)
    }
  }
  // Disposal is the step that's hardest to undo, so it asks first.
  const onApprove = (r) => (r.kind === 'DISPOSAL' ? setApproving(r) : approveRequest(r))

  const rejectRequest = async (note) => {
    const r = rejecting
    await REQUEST_KIND[r.kind].reject(r.recordId, note)
    toast.show('Request rejected.', 'warning')
    load({ silent: true })
  }

  const animAssets = useCountUp(totalAssets, !loading)
  const animValue  = useCountUp(Math.round(totalValue), !loading)
  const animRepair = useCountUp(underRepair, !loading)
  const animDisp   = useCountUp(forDisposal, !loading)
  const bookValue  = planning?.depreciation?.total?.bookValue
  const animBook   = useCountUp(Math.round(Number(bookValue ?? 0)), bookValue != null)
  // Admins see the book value (from Budget & Planning); staff, or when that failed to load, the cost.
  const showBook   = isAdmin && (planningLoading || bookValue != null)

  const stats = [
    {
      label: 'Assets in use', value: fmtNum(animAssets),
      sub: isAdmin ? 'All offices' : (user?.officeName || 'Your office'), delta: newThisMonth, href: '/assets', icon: ICONS.assets,
    },
    showBook ? {
      label: 'Book Value', value: fmtMoney(animBook), loading: bookValue == null,
      sub: `Of ${fmtMoney(totalValue)} acquisition cost`, href: '/reports?report=depreciation', icon: ICONS.value,
    } : {
      label: 'Asset Value', value: fmtMoney(animValue),
      sub: 'Acquisition cost of assets in use', href: '/assets', icon: ICONS.value,
    },
    {
      label: 'Under Repair', value: fmtNum(animRepair),
      sub: 'Maintenance not yet finished', href: '/maintenance', icon: ICONS.repair,
    },
    {
      label: 'For Disposal', value: fmtNum(animDisp),
      sub: 'Disposal not yet finished', href: '/disposal', icon: ICONS.dispose,
    },
  ]

  return (
    <MainLayout>
      {/* Header */}
      <div className="flex items-center justify-between gap-4 mb-4">
        <p className="text-base font-semibold text-slate-800 dark:text-zinc-100">
          {new Date().toLocaleDateString('en-PH', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
        </p>
        <div className="flex items-center gap-2">
          {error && (
            <span className="text-xs text-red-700 dark:text-red-300 flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-red-400 inline-block" />
              Couldn't load Home
            </span>
          )}
          <button
            onClick={() => load()}
            disabled={loading}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-xs font-medium text-slate-600 dark:text-zinc-400 hover:text-slate-900 dark:hover:text-zinc-200 hover:border-slate-300 dark:hover:border-zinc-600 transition-all duration-150 disabled:opacity-40"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Refresh
          </button>
        </div>
      </div>

      <div className="space-y-5">
        <StatStrip stats={stats} loading={loading} />

        {isAdmin && !loading && unassignedStaff.length > 0 && <UnassignedOffices accounts={unassignedStaff} />}

        {isAdmin && (
          <PendingApprovals requests={pendingList} loading={loading} failed={requestsFailed} onRetry={() => load()}
            busyId={busyId} onApprove={onApprove} onReject={setRejecting} />
        )}

        {!loading && <NeedsAttention items={attention} />}

        {isAdmin && <BudgetPlanning data={planning} loading={loading || planningLoading} onChange={setPlanning} />}

        <div className={`grid grid-cols-1 ${isAdmin ? 'lg:grid-cols-3' : 'lg:grid-cols-2'} gap-5`}>
          <ConditionDistribution condDist={condDist} total={totalAssets} loading={loading}
            onSelect={(cond) => navigate(`/assets?condition=${cond}`)} />
          {isAdmin && (
            <OfficeDistribution offices={officeDist.slice(0, TOP_OFFICES)} officeCount={officeDist.length} loading={loading}
              onSelect={(officeId) => navigate(`/assets?office=${officeId}`)} />
          )}
          <CategoryBreakdown breakdown={categoryBreakdown} total={totalAssets} loading={loading}
            onSelect={(categoryId) => navigate(`/assets?category=${categoryId}`)} />
        </div>
      </div>

      {rejecting && (
        <RejectRequestModal
          record={{ ...rejecting, kind: rejecting.kind.toLowerCase(), id: rejecting.recordId }}
          describe={(r) => `${REQUEST_KIND[rejecting.kind].label}: ${r.propertyNumber || ''} ${r.assetDescription || ''}`}
          onClose={() => setRejecting(null)}
          onConfirm={rejectRequest}
        />
      )}
      {approving && (
        <ConfirmDialog
          title="Approve this disposal?"
          message={`${approving.propertyNumber} ${approving.assetDescription || ''} will be marked for disposal${approving.detail ? ` (${approving.detail})` : ''}.`}
          confirmLabel="Approve disposal"
          onCancel={() => setApproving(null)}
          onConfirm={() => { const r = approving; setApproving(null); approveRequest(r) }}
        />
      )}
    </MainLayout>
  )
}

export default Dashboard
