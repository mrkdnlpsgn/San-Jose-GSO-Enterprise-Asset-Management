import { useState, useEffect, useCallback, useRef } from 'react'
import { useDispatch, useSelector } from 'react-redux'
import { setAssets } from '../../store/slices/assetSlice'
import { getAssets } from '../../services/assetService'
import { Link, useNavigate } from 'react-router-dom'
import MainLayout from '../../components/layout/MainLayout'
import { getDashboardSummary } from '../../services/dashboardService'
import { getPlanning, generatePlanningSummary, setPlanningPriceIncrease } from '../../services/aiRecommendationService'
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

const CONDITION_ORDER = ['NEW', 'GOOD', 'SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE']
const CONDITION_CFG = {
  NEW:           { bar: 'bg-sky-500',     text: 'text-sky-400',     dot: 'bg-sky-400',     label: 'New' },
  GOOD:          { bar: 'bg-teal-500',    text: 'text-teal-400',    dot: 'bg-teal-400',    label: 'Good' },
  SERVICEABLE:   { bar: 'bg-emerald-500', text: 'text-emerald-400', dot: 'bg-emerald-400', label: 'Serviceable' },
  REPAIRABLE:    { bar: 'bg-amber-500',   text: 'text-amber-400',   dot: 'bg-amber-400',   label: 'Repairable' },
  UNSERVICEABLE: { bar: 'bg-red-500',     text: 'text-red-400',     dot: 'bg-red-400',     label: 'Unserviceable' },
}


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

// "Budget & Planning" (admins and Admin-Staff), laid out for reading at a glance, including by older
// staff: large figures with a plain label above each, money written as "₱321.9 million" with
// the exact amount under it, and the coming years as a table with a total. Breakdowns by
// type and the book-value figures live in the Replacement Forecast and Depreciation
// Schedule reports. Data: PlanningInsightService (replacement forecast + depreciation, one AI
// summary). Dashboard loads it and also uses it for the Book Value tile.
const plural = (n, one, many) => `${fmtNum(n)} ${n === 1 ? one : many}`

// ₱321,868,619.98 -> "₱321.9 million"; smaller amounts in full, without centavos.
const pesoExact = (v) => '₱' + Math.round(Number(v) || 0).toLocaleString('en-PH')
function pesoWords(v) {
  const n = Number(v) || 0
  if (n >= 1_000_000_000) return `₱${(n / 1_000_000_000).toFixed(1)} billion`
  if (n >= 1_000_000) return `₱${(n / 1_000_000).toFixed(1)} million`
  return pesoExact(n)
}

function BigFigure({ label, value, exact }) {
  return (
    <div className="min-w-0 px-5 py-4">
      <dt className="text-sm font-semibold text-slate-700 dark:text-zinc-300">{label}</dt>
      <dd className="text-3xl font-bold text-slate-900 dark:text-white tabular-nums leading-tight mt-1">{value}</dd>
      {exact && <dd className="text-sm text-slate-700 dark:text-zinc-300 tabular-nums mt-0.5">Exact: {exact}</dd>}
    </div>
  )
}

// One year in "Coming up": the whole card opens the Replacement Forecast on that year.
function YearCard({ bucket, label }) {
  return (
    <Link to={`/reports?report=replacement&replaceIn=${encodeURIComponent(bucket.key)}`}
      aria-label={`${label}: ${plural(bucket.assets, 'asset', 'assets')}, about ${pesoWords(bucket.cost)}. View the list.`}
      className="group flex flex-col rounded-lg border border-slate-300 dark:border-zinc-700 bg-white dark:bg-zinc-900 px-4 py-3.5 transition-colors duration-150 hover:border-brand-600 hover:bg-slate-50 dark:hover:border-brand-400 dark:hover:bg-zinc-800/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-zinc-900">
      <span className="text-base font-semibold text-slate-800 dark:text-zinc-200">{label}</span>
      <span className="text-2xl font-bold text-slate-900 dark:text-white tabular-nums leading-tight mt-2" title={pesoExact(bucket.cost)}>{pesoWords(bucket.cost)}</span>
      <span className="text-base text-slate-700 dark:text-zinc-300 tabular-nums">{plural(bucket.assets, 'asset', 'assets')}</span>
      <span className="mt-3 pt-2.5 border-t border-slate-200 dark:border-zinc-800 text-sm font-semibold text-brand-700 dark:text-brand-300 group-hover:underline underline-offset-2">
        View assets <span aria-hidden="true" className="inline-block transition-transform duration-150 group-hover:translate-x-0.5">›</span>
      </span>
    </Link>
  )
}

// The yearly price increase every forecast here uses. Everyone sees it; an administrator can
// change it (e.g. to the rate the Budget Office gives for the budget call). Saving answers with
// the planning figures worked out again, which replace the section's data.
function PriceIncreaseRow({ percent, canEdit, onSaved }) {
  const [editing, setEditing] = useState(false)
  const [value, setValue]     = useState('')
  const [saving, setSaving]   = useState(false)
  const [error, setError]     = useState('')

  const start = () => { setValue(String(percent)); setError(''); setEditing(true) }
  const save = async (e) => {
    e.preventDefault()
    const n = Number(value)
    if (value.trim() === '' || Number.isNaN(n) || n < 0 || n > 20) { setError('Enter a number from 0 to 20.'); return }
    setSaving(true)
    try {
      const { data } = await setPlanningPriceIncrease(n)
      onSaved(data)
      setEditing(false)
    } catch (err) {
      setError(err.response?.data?.message || 'Could not save the rate.')
    } finally {
      setSaving(false)
    }
  }

  if (!editing) {
    return (
      <p className="text-base text-slate-800 dark:text-zinc-200">
        These estimates assume prices rise <span className="font-semibold">{percent}% a year</span>.
        {canEdit && (
          <button type="button" onClick={start}
            className="ml-2 font-semibold text-brand-700 dark:text-brand-300 underline underline-offset-2 hover:text-brand-800 dark:hover:text-brand-200">
            Change
          </button>
        )}
      </p>
    )
  }
  return (
    <form onSubmit={save} noValidate className="rounded-lg border border-slate-300 dark:border-zinc-700 px-4 py-3.5 space-y-2.5 animate-fade-in">
      <label htmlFor="bp-rate" className="block text-base font-semibold text-slate-900 dark:text-white">Yearly price increase</label>
      <p className="text-sm text-slate-700 dark:text-zinc-300">
        Used for the replacement and repairs estimates. 3% is the middle of the BSP's 2% to 4% inflation target; use the Budget Office's rate if it gives one.
      </p>
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-2">
          <input id="bp-rate" type="number" inputMode="decimal" min="0" max="20" step="0.1" autoFocus
            value={value} onChange={(e) => { setValue(e.target.value); setError('') }}
            aria-invalid={error ? true : undefined} aria-describedby={error ? 'bp-rate-error' : undefined}
            className="w-24 rounded-md border border-slate-300 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3 py-2 text-base text-slate-900 dark:text-white tabular-nums focus:outline-none focus:ring-2 focus:ring-brand-500" />
          <span className="text-base text-slate-800 dark:text-zinc-200">% a year</span>
        </div>
        <button type="submit" disabled={saving}
          className="rounded-lg bg-brand-700 hover:bg-brand-800 text-white text-sm font-semibold px-4 py-2 min-h-[40px] disabled:opacity-50 transition-colors">
          {saving ? 'Saving…' : 'Save'}
        </button>
        <button type="button" onClick={() => setEditing(false)} disabled={saving}
          className="text-sm font-medium text-slate-600 dark:text-zinc-400 hover:underline underline-offset-2">
          Cancel
        </button>
      </div>
      {error && <p id="bp-rate-error" role="alert" className="text-sm font-medium text-red-700 dark:text-red-300">{error}</p>}
    </form>
  )
}

// Repairs and maintenance: last full year against the first of the three
const TREND_TEXT = {
  RISING:  { label: 'Rising',  cls: 'bg-amber-100 text-amber-900 dark:bg-amber-500/15 dark:text-amber-200' },
  FALLING: { label: 'Falling', cls: 'bg-emerald-100 text-emerald-900 dark:bg-emerald-500/15 dark:text-emerald-200' },
  STEADY:  { label: 'Steady',  cls: 'bg-slate-100 text-slate-800 dark:bg-zinc-800 dark:text-zinc-200' },
}

// canEditCategories: an administrator (sets the expected years of use and the price increase)
function BudgetPlanning({ data, loading, onChange, canEditCategories }) {
  const [generating, setGenerating] = useState(false)
  const [aiError, setAiError]       = useState('')

  const generate = async () => {
    setGenerating(true)
    setAiError('')
    try {
      const { data } = await generatePlanningSummary(true)
      onChange(data)
    } catch (err) {
      setAiError(err.response?.data?.message || 'Could not write the summary.')
    } finally {
      setGenerating(false)
    }
  }

  const r = data?.replacement
  const m = data?.maintenance
  const risk = data?.repairRisk?.notEnoughHistory === false ? data.repairRisk : null
  const asOf = data?.depreciation?.asOf
  const thisYear = asOf?.slice(0, 4)
  const dueNow = r?.buckets.find((b) => b.key === 'NOW')
  const coming = (r?.buckets || []).filter((b) => b.key !== 'NOW')
  const comingTotal = coming.reduce((t, b) => ({ assets: t.assets + b.assets, cost: t.cost + Number(b.cost) }), { assets: 0, cost: 0 })
  const missingLife = r?.excluded?.noExpectedLife || []
  const link = 'font-semibold text-brand-700 dark:text-brand-300 underline underline-offset-2 hover:text-brand-800 dark:hover:text-brand-200'

  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-4 border-b border-slate-200 dark:border-zinc-800">
        <h2 className="text-lg font-semibold text-slate-900 dark:text-white">Budget &amp; Planning</h2>
        <p className="text-sm text-slate-700 dark:text-zinc-300 mt-0.5">
          Assets that need replacing, what repairs will cost, and about how much to budget
          {asOf ? `. As of ${new Date(asOf).toLocaleDateString('en-PH', { year: 'numeric', month: 'long', day: 'numeric' })}.` : '.'}
        </p>
      </div>

      <div className="px-5 py-5 space-y-6">
        {loading ? (
          <div className="space-y-4">
            <Sk className="h-32" />
            {Array.from({ length: 4 }).map((_, i) => <Sk key={i} className="h-7" />)}
          </div>
        ) : !data ? (
          <p className="text-base text-slate-700 dark:text-zinc-300">Couldn't load the budget and planning figures.</p>
        ) : (
          <>
            {/* 1. Due now */}
            {dueNow?.assets > 0 ? (
              // Laid out like a form: a titled header row, the two figures side by side, and the
              // explanation with the action in a footer row.
              <section aria-labelledby="bp-due-now" className="rounded-lg border border-slate-300 dark:border-zinc-700 overflow-hidden">
                <div className="flex flex-wrap items-center justify-between gap-2 px-5 py-3 bg-slate-50 dark:bg-zinc-800/50 border-b border-slate-300 dark:border-zinc-700">
                  <h3 id="bp-due-now" className="text-base font-semibold text-slate-900 dark:text-white">Due for replacement now</h3>
                  <span className="text-sm font-semibold px-2.5 py-0.5 rounded bg-amber-100 text-amber-900 dark:bg-amber-500/15 dark:text-amber-200">Needs budget</span>
                </div>
                <dl className="grid grid-cols-1 sm:grid-cols-2 divide-y sm:divide-y-0 sm:divide-x divide-slate-200 dark:divide-zinc-800">
                  <BigFigure label="Number of assets" value={fmtNum(dueNow.assets)} />
                  <BigFigure label="Estimated cost to replace" value={pesoWords(dueNow.cost)}
                    exact={Number(dueNow.cost) >= 1_000_000 ? pesoExact(dueNow.cost) : null} />
                </dl>
                <div className="flex flex-col sm:flex-row sm:items-center gap-3 px-5 py-4 border-t border-slate-200 dark:border-zinc-800">
                  <p className="flex-1 text-base text-slate-800 dark:text-zinc-200">
                    These assets are past their expected years of use, or broken and waiting for disposal.
                  </p>
                  <Link to="/reports?report=replacement&replaceIn=NOW"
                    className="shrink-0 inline-flex items-center justify-center rounded-lg bg-brand-700 hover:bg-brand-800 text-white text-base font-semibold px-5 py-2.5 min-h-[44px] transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-zinc-900">
                    See the list of assets
                  </Link>
                </div>
              </section>
            ) : (
              <p className="text-base text-slate-800 dark:text-zinc-200">No assets are due for replacement right now.</p>
            )}

            {/* 2. The coming years */}
            {coming.length > 0 && (
              <section aria-labelledby="bp-coming">
                <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                  <h3 id="bp-coming" className="text-base font-semibold text-slate-900 dark:text-white">Coming up in the next years</h3>
                  <p className="text-base text-slate-800 dark:text-zinc-200 tabular-nums">
                    Total: <span className="font-bold" title={pesoExact(comingTotal.cost)}>{pesoWords(comingTotal.cost)}</span> for {plural(comingTotal.assets, 'asset', 'assets')}
                  </p>
                </div>
                <p className="text-sm text-slate-700 dark:text-zinc-300 mt-0.5">Choose a year to see its assets.</p>
                <div className="grid grid-cols-1 min-[420px]:grid-cols-2 lg:grid-cols-4 gap-3 mt-3">
                  {coming.map((b) => (
                    <YearCard key={b.key} bucket={b} label={b.key === thisYear ? `Rest of ${b.key}` : b.key} />
                  ))}
                </div>
              </section>
            )}

            {/* 3. Repairs and maintenance: last years' spending and next year's estimate */}
            {m && (
              <section aria-labelledby="bp-repairs" className="rounded-lg border border-slate-300 dark:border-zinc-700 overflow-hidden">
                <div className="flex flex-wrap items-center justify-between gap-2 px-5 py-3 bg-slate-50 dark:bg-zinc-800/50 border-b border-slate-300 dark:border-zinc-700">
                  <h3 id="bp-repairs" className="text-base font-semibold text-slate-900 dark:text-white">Repairs and maintenance</h3>
                  {TREND_TEXT[m.trend] && (
                    <span className={`text-sm font-semibold px-2.5 py-0.5 rounded ${TREND_TEXT[m.trend].cls}`}>{TREND_TEXT[m.trend].label}</span>
                  )}
                </div>
                <dl className="grid grid-cols-1 sm:grid-cols-2 divide-y sm:divide-y-0 sm:divide-x divide-slate-200 dark:divide-zinc-800">
                  <BigFigure label={`Estimated budget for ${m.forecast.year}`} value={pesoWords(m.forecast.cost)}
                    exact={Number(m.forecast.cost) >= 1_000_000 ? pesoExact(m.forecast.cost) : null} />
                  <div className="min-w-0 px-5 py-4">
                    <dt className="text-sm font-semibold text-slate-700 dark:text-zinc-300">Spent in past years</dt>
                    <dd className="mt-1.5">
                      <ul className="space-y-1 text-base tabular-nums">
                        {m.years.map((y) => (
                          <li key={y.year} className="flex justify-between gap-4">
                            <span className="text-slate-700 dark:text-zinc-300">{y.year}{y.soFar ? ' (so far)' : ''}</span>
                            <span className="font-semibold text-slate-900 dark:text-white" title={pesoExact(y.cost)}>{pesoWords(y.cost)}</span>
                          </li>
                        ))}
                      </ul>
                    </dd>
                  </div>
                </dl>
                {m.accuracy?.averageErrorPercent != null && (
                  <details className="px-5 py-3 border-t border-slate-200 dark:border-zinc-800">
                    <summary className="cursor-pointer text-base text-slate-800 dark:text-zinc-200">
                      Checked against past years, this method was off by about{' '}
                      <span className="font-semibold">{m.accuracy.averageErrorPercent}%</span> on average.
                    </summary>
                    <p className="text-sm text-slate-700 dark:text-zinc-300 mt-2">
                      For each year, the same rule was applied using only the years before it (as if the budget were made the year before), then compared with what was actually spent.
                    </p>
                    <table className="mt-2 w-full max-w-lg text-sm tabular-nums">
                      <thead>
                        <tr className="text-left text-slate-700 dark:text-zinc-300">
                          <th className="font-semibold py-1 pr-3">Year</th>
                          <th className="font-semibold py-1 pr-3 text-right">Estimate</th>
                          <th className="font-semibold py-1 pr-3 text-right">Actual</th>
                          <th className="font-semibold py-1 text-right">Off by</th>
                        </tr>
                      </thead>
                      <tbody className="text-slate-900 dark:text-white">
                        {m.accuracy.years.map((y) => (
                          <tr key={y.year} className="border-t border-slate-200 dark:border-zinc-800">
                            <td className="py-1 pr-3">{y.year}</td>
                            <td className="py-1 pr-3 text-right" title={pesoExact(y.estimate)}>{pesoWords(y.estimate)}</td>
                            <td className="py-1 pr-3 text-right" title={pesoExact(y.actual)}>{pesoWords(y.actual)}</td>
                            <td className="py-1 text-right">{Math.abs(y.errorPercent)}% {y.errorPercent > 0 ? 'too high' : y.errorPercent < 0 ? 'too low' : ''}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </details>
                )}
                <div className="flex flex-col sm:flex-row sm:items-center gap-3 px-5 py-4 border-t border-slate-200 dark:border-zinc-800">
                  <p className="flex-1 text-base text-slate-800 dark:text-zinc-200">
                    {m.byCategory[0] ? <>Costs most to keep running: <span className="font-semibold">{m.byCategory[0].category}</span>. </> : null}
                    The estimate is the average of the last 3 years at next year's prices.
                    {m.limitedHistory && ' There is little repair history yet, so treat it as a rough guide.'}
                  </p>
                  <Link to="/reports?report=maintenanceforecast"
                    className="shrink-0 inline-flex items-center justify-center rounded-lg border border-slate-300 dark:border-zinc-600 bg-white dark:bg-zinc-900 text-slate-800 dark:text-zinc-100 text-base font-semibold px-5 py-2.5 min-h-[44px] hover:bg-slate-100 dark:hover:bg-zinc-800 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-zinc-900">
                    See by type of property
                  </Link>
                </div>
              </section>
            )}

            {/* 3b. Repair risk: the machine-learning model's assets likely to need work in the next 12 months */}
            {risk && (
              <section aria-labelledby="bp-risk" className="rounded-lg border border-slate-300 dark:border-zinc-700 overflow-hidden">
                <div className="px-5 py-3 bg-slate-50 dark:bg-zinc-800/50 border-b border-slate-300 dark:border-zinc-700">
                  <h3 id="bp-risk" className="text-base font-semibold text-slate-900 dark:text-white">Likely to need repair in the next 12 months</h3>
                </div>
                <dl className="grid grid-cols-1 sm:grid-cols-2 divide-y sm:divide-y-0 sm:divide-x divide-slate-200 dark:divide-zinc-800">
                  <BigFigure label="Assets expected to need work" value={`About ${fmtNum(risk.expectedAssets)}`} />
                  <BigFigure label="High risk (50% chance or more)" value={fmtNum(risk.high)} />
                </dl>
                {risk.check?.foundPercent != null && (
                  <details className="px-5 py-3 border-t border-slate-200 dark:border-zinc-800">
                    <summary className="cursor-pointer text-base text-slate-800 dark:text-zinc-200">
                      Tested on {risk.check.year}: it picked out <span className="font-semibold">{risk.check.foundPercent}%</span> of the assets that needed work, against {risk.check.randomPercent}% by chance.
                    </summary>
                    <p className="text-sm text-slate-700 dark:text-zinc-300 mt-2">
                      A machine-learning model (logistic regression) learns from the system's own repair records which assets needed work in past years.
                      To test it, it was trained without {risk.check.year} and asked to rank the {fmtNum(risk.check.assets)} assets on hand at the start of that year.
                      Of the {fmtNum(risk.check.needed)} that really needed repair or maintenance, {fmtNum(risk.check.found)} were among its top {fmtNum(risk.check.needed)}.
                      It expected about {fmtNum(risk.check.expected)}.
                    </p>
                    {risk.factors?.length > 0 && (
                      <ul className="mt-2 text-sm text-slate-800 dark:text-zinc-200 space-y-0.5">
                        {risk.factors.filter((f) => Math.abs(f.weight) >= 0.05).map((f) => (
                          <li key={f.factor}>{f.factor}: {f.weight > 0 ? 'more likely' : 'less likely'} to need work</li>
                        ))}
                      </ul>
                    )}
                  </details>
                )}
                <div className="flex flex-col sm:flex-row sm:items-center gap-3 px-5 py-4 border-t border-slate-200 dark:border-zinc-800">
                  <p className="flex-1 text-base text-slate-800 dark:text-zinc-200">
                    {fmtNum(risk.medium)} more {risk.medium === 1 ? 'has' : 'have'} a medium risk (20 to 49%). Checking these first can prevent breakdowns.
                  </p>
                  <Link to="/reports?report=repairrisk"
                    className="shrink-0 inline-flex items-center justify-center rounded-lg border border-slate-300 dark:border-zinc-600 bg-white dark:bg-zinc-900 text-slate-800 dark:text-zinc-100 text-base font-semibold px-5 py-2.5 min-h-[44px] hover:bg-slate-100 dark:hover:bg-zinc-800 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-zinc-900">
                    See the assets at risk
                  </Link>
                </div>
              </section>
            )}

            {missingLife.length > 0 && (
              <p className="text-base text-amber-900 dark:text-amber-200">
                Not counted yet: {missingLife.join(', ')}. {missingLife.length === 1 ? 'This type has' : 'These types have'} no expected years of use.{' '}
                {canEditCategories
                  ? <><Link to="/categories" className="font-semibold underline">Set it on the Categories page</Link>.</>
                  : 'An administrator can set it on the Categories page.'}
              </p>
            )}

            <PriceIncreaseRow percent={data.priceIncreasePercent ?? r?.priceIncreasePercent ?? 3} canEdit={canEditCategories} onSaved={onChange} />

            {/* 4. Summary (AI) */}
            <section aria-label="Summary" className="rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-950/50 px-5 py-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <h3 className="text-base font-semibold text-slate-900 dark:text-white">Summary</h3>
                <button onClick={generate} disabled={generating}
                  className="rounded-lg border border-slate-300 dark:border-zinc-600 bg-white dark:bg-zinc-900 px-4 py-2 min-h-[40px] text-sm font-semibold text-slate-800 dark:text-zinc-100 hover:bg-slate-100 dark:hover:bg-zinc-800 disabled:opacity-50 transition-colors">
                  {generating ? 'Writing…' : data.summary ? 'Write again' : 'Write summary'}
                </button>
              </div>
              {aiError ? (
                <p className="text-base text-red-700 dark:text-red-300 mt-2">{aiError}</p>
              ) : data.summary ? (
                <p className="text-base text-slate-800 dark:text-zinc-200 leading-relaxed mt-2">{data.summary}</p>
              ) : generating ? (
                <p className="text-base text-slate-700 dark:text-zinc-300 mt-2" role="status">Writing the summary…</p>
              ) : (
                <p className="text-base text-slate-700 dark:text-zinc-300 mt-2">Press "Write summary" and the AI will explain these numbers in a few sentences.</p>
              )}
            </section>

            <p className="text-base text-slate-800 dark:text-zinc-200">
              More detail:{' '}
              <Link to="/reports?report=replacement" className={link}>Replacement Forecast</Link>
              {', '}
              <Link to="/reports?report=maintenanceforecast" className={link}>Repairs &amp; Maintenance Forecast</Link>
              {' and '}
              <Link to="/reports?report=depreciation" className={link}>Depreciation Schedule</Link>
            </p>
          </>
        )}
      </div>
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
  // the admin-only parts of the page (offices, unassigned staff) are hidden for them.
  const dispatch = useDispatch()
  const user     = useSelector((s) => s.auth.user)
  const isAdmin  = user?.role === 'ADMIN'
  const isAdminStaff = user?.role === 'ADMIN_STAFF'   // sees all offices, but files requests like staff
  // Admin-Staff sees the entire inventory, so its Home is the admin's: offices chart, book value,
  // Budget & Planning. (Only Categories, an admin page, isn't linked for it.)
  const adminHome = isAdmin || isAdminStaff
  const cachedAssetCount = useSelector((s) => s.assets.items.length)

  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState(false)
  const [summary, setSummary]   = useState(null)   // asset numbers worked out by the server
  const [insightToken, setInsightToken] = useState(0)   // bumps on every quiet reload so Budget & Planning refetches

  const load = useCallback(({ silent = false } = {}) => {
    if (!silent) { setLoading(true); setError(false) }
    // Requests, unassigned staff and asset problems are notifications: they live in the
    // header's bell (useNotifications), not on the dashboard.
    getDashboardSummary().catch(() => null).then((sumRes) => {
      if (!sumRes) {
        if (!silent) { setError(true); setLoading(false) }
        return
      }
      setSummary(sumRes.data)
      if (silent) setInsightToken((t) => t + 1)  // Budget & Planning loads itself on first open
      if (!silent) setLoading(false)
    })
  }, [])

  // Budget & Planning (admins and Admin-Staff), loaded after the main numbers so it doesn't slow them down.
  // Also feeds the Book Value tile.
  const [planning, setPlanning]               = useState(null)
  const [planningLoading, setPlanningLoading] = useState(true)
  useEffect(() => {
    if (!adminHome || loading) return
    let alive = true
    getPlanning()
      .then(({ data }) => { if (alive) setPlanning(data) })
      .catch(() => { if (alive) setPlanning(null) })
      .finally(() => { if (alive) setPlanningLoading(false) })
    return () => { alive = false }
  }, [adminHome, loading, insightToken])

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

  const animAssets = useCountUp(totalAssets, !loading)
  const animValue  = useCountUp(Math.round(totalValue), !loading)
  const animRepair = useCountUp(underRepair, !loading)
  const animDisp   = useCountUp(forDisposal, !loading)
  const bookValue  = planning?.depreciation?.total?.bookValue
  const animBook   = useCountUp(Math.round(Number(bookValue ?? 0)), bookValue != null)
  // Admins and Admin-Staff see the book value (from Budget & Planning); staff, or when that failed to load, the cost.
  const showBook   = adminHome && (planningLoading || bookValue != null)

  const stats = [
    {
      label: 'Assets in use', value: fmtNum(animAssets),
      sub: adminHome ? 'All offices' : (user?.officeName || 'Your office'), delta: newThisMonth, href: '/assets', icon: ICONS.assets,
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

        {adminHome && <BudgetPlanning data={planning} loading={loading || planningLoading} onChange={setPlanning} canEditCategories={isAdmin} />}

        <div className={`grid grid-cols-1 ${adminHome ? 'lg:grid-cols-3' : 'lg:grid-cols-2'} gap-5`}>
          <ConditionDistribution condDist={condDist} total={totalAssets} loading={loading}
            onSelect={(cond) => navigate(`/assets?condition=${cond}`)} />
          {adminHome && (
            <OfficeDistribution offices={officeDist.slice(0, TOP_OFFICES)} officeCount={officeDist.length} loading={loading}
              onSelect={(officeId) => navigate(`/assets?office=${officeId}`)} />
          )}
          <CategoryBreakdown breakdown={categoryBreakdown} total={totalAssets} loading={loading}
            onSelect={(categoryId) => navigate(`/assets?category=${categoryId}`)} />
        </div>
      </div>
    </MainLayout>
  )
}

export default Dashboard
