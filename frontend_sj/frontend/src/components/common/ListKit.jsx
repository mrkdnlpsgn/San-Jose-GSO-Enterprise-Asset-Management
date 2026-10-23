import { useId } from 'react'

// Shared pieces for every module's list page, so they all look and behave the same:
//   SearchBox + FilterSelect / FilterBar  - one search box, a few plainly labelled filters,
//                                           extra ones behind "More filters", and "Clear all"
//   ListCard + ListAction + Pager          - the card around the table: title, count, the
//                                           list's own actions (Excel, Import, Refresh), paging
//   DataTable                              - never scrolls sideways: columns drop away on narrow
//                                           screens; a row opens its details by click or keyboard
//   StatusBadge / AssetCell                - readable badges and the usual "asset" cell
// Colours are dark-on-light / light-on-dark so text passes WCAG AA in both themes.

export const TONE = {
  green:  'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 ring-1 ring-emerald-500/30',
  amber:  'bg-amber-500/10 text-amber-800 dark:text-amber-300 ring-1 ring-amber-500/30',
  red:    'bg-red-500/10 text-red-700 dark:text-red-300 ring-1 ring-red-500/30',
  blue:   'bg-blue-500/10 text-blue-700 dark:text-blue-300 ring-1 ring-blue-500/30',
  violet: 'bg-violet-500/10 text-violet-700 dark:text-violet-300 ring-1 ring-violet-500/30',
  slate:  'bg-slate-500/10 text-slate-700 dark:text-zinc-300 ring-1 ring-slate-500/30',
}

export function StatusBadge({ tone = 'slate', children }) {
  if (!children) return null
  return <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold whitespace-nowrap ${TONE[tone] || TONE.slate}`}>{children}</span>
}

// value → { label, tone } lookups, e.g. STATUS = { ONGOING: { label: 'Ongoing', tone: 'amber' } }
// A value mapped to null shows nothing (e.g. APPROVED, the normal state, needs no badge).
export function MappedBadge({ map, value }) {
  if (value in map && map[value] == null) return null
  const b = map[value]
  if (!b) return value ? <StatusBadge>{String(value).replace(/_/g, ' ').toLowerCase()}</StatusBadge> : null
  return <StatusBadge tone={b.tone}>{b.label}</StatusBadge>
}

const MUTED = 'text-slate-600 dark:text-zinc-400'

export function SearchBox({ value, onChange, placeholder, label = 'Search' }) {
  return (
    <div className="relative flex-1 min-w-0">
      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 dark:text-zinc-400 pointer-events-none" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
      </svg>
      <input type="search" aria-label={label} value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder}
        className="w-full pl-9 pr-3 py-2.5 text-sm rounded-lg border border-slate-300 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-slate-900 dark:text-zinc-100 placeholder:text-slate-500 dark:placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-all" />
    </div>
  )
}

// A dropdown that always shows what it filters ("Status: Any"); tinted while something other
// than Any is picked. options: [[value, label], …]
export function FilterSelect({ label, value, onChange, options, anyLabel = 'Any' }) {
  const id = useId()
  return (
    <div className={`relative flex items-center rounded-lg border focus-within:ring-2 focus-within:ring-brand-500 transition-colors ${
      value ? 'border-brand-600 bg-brand-50 dark:bg-brand-500/10' : 'border-slate-300 dark:border-zinc-700 bg-white dark:bg-zinc-900'}`}>
      <label htmlFor={id} className={`pl-3 text-sm ${MUTED} whitespace-nowrap`}>{label}:</label>
      <select id={id} value={value} onChange={(e) => onChange(e.target.value)}
        className="appearance-none bg-transparent pl-1.5 pr-8 py-1.5 text-sm font-medium text-slate-900 dark:text-zinc-100 max-w-[13rem] truncate focus:outline-none cursor-pointer">
        <option value="">{anyLabel}</option>
        {options.map(([val, text]) => <option key={val} value={val}>{text}</option>)}
      </select>
      <div className={`pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 ${MUTED}`}>
        <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
      </div>
    </div>
  )
}

// An on/off filter shown as a button, e.g. "Awaiting approval (3)".
export function FilterToggle({ on, onChange, children }) {
  return (
    <button type="button" aria-pressed={on} onClick={() => onChange(!on)}
      className={`px-3 py-1.5 rounded-lg border text-sm font-medium transition-colors ${
        on ? 'border-amber-600 bg-amber-500/15 text-amber-900 dark:text-amber-200' : 'border-slate-300 dark:border-zinc-700 text-slate-700 dark:text-zinc-300 hover:bg-slate-50 dark:hover:bg-zinc-800'}`}>
      {children}
    </button>
  )
}

// The filter row. `more` (optional) holds filters hidden behind "More filters".
export function FilterBar({ children, more, moreOpen, onMoreToggle, activeCount = 0, onClear }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {children}
      {more && moreOpen && more}
      {more && (
        <button type="button" onClick={() => onMoreToggle(!moreOpen)} aria-expanded={moreOpen}
          className="px-2.5 py-1.5 rounded-lg text-sm font-medium text-brand-700 dark:text-brand-300 hover:bg-brand-500/10 transition-colors">
          {moreOpen ? 'Fewer filters' : 'More filters'}
        </button>
      )}
      {activeCount > 0 && (
        <button type="button" onClick={onClear}
          className="px-2.5 py-1.5 rounded-lg text-sm font-medium text-slate-700 dark:text-zinc-300 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-colors">
          Clear all ({activeCount})
        </button>
      )}
    </div>
  )
}

// A notice above the list when it was opened already narrowed (e.g. to one asset).
export function ScopeNotice({ children, onClear, clearLabel = 'Show all' }) {
  return (
    <div className="mb-3 flex items-center gap-3 px-4 py-2.5 rounded-lg bg-blue-500/10 border border-blue-500/30">
      <p className="text-sm text-blue-800 dark:text-blue-200">{children}</p>
      <button type="button" onClick={onClear} className="ml-auto text-sm font-medium text-blue-800 dark:text-blue-200 hover:underline">{clearLabel}</button>
    </div>
  )
}

export const ICON = {
  download: <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />,
  upload:   <path fillRule="evenodd" d="M3 3a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm4.293 8.707a1 1 0 011.414-1.414L9 10.586V17a1 1 0 102 0v-6.414l1.293 1.293a1 1 0 001.414-1.414l-3-3a1 1 0 00-1.414 0l-3 3z" clipRule="evenodd" />,
  refresh:  <path fillRule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clipRule="evenodd" />,
  plus:     <path fillRule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clipRule="evenodd" />,
  edit:     <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />,
  trash:    <path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" />,
  camera:   <path fillRule="evenodd" d="M4 5a2 2 0 00-2 2v8a2 2 0 002 2h12a2 2 0 002-2V7a2 2 0 00-2-2h-1.586a1 1 0 01-.707-.293l-1.121-1.121A2 2 0 0011.172 3H8.828a2 2 0 00-1.414.586L6.293 4.707A1 1 0 015.586 5H4zm6 9a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />,
  check:    <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />,
  x:        <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />,
  restore:  <path fillRule="evenodd" d="M7.707 3.293a1 1 0 010 1.414L5.414 7H11a7 7 0 017 7v2a1 1 0 11-2 0v-2a5 5 0 00-5-5H5.414l2.293 2.293a1 1 0 11-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clipRule="evenodd" />,
}

export function Icon({ children, className = 'h-4 w-4' }) {
  return <svg xmlns="http://www.w3.org/2000/svg" className={className} viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">{children}</svg>
}

// A labelled button in the list card's header (Download Excel, Import, …).
export function ListAction({ onClick, icon, children, label }) {
  return (
    <button type="button" onClick={onClick} aria-label={label}
      className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-md text-sm font-medium text-slate-700 dark:text-zinc-300 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-colors">
      {icon && <Icon>{icon}</Icon>}
      {children}
    </button>
  )
}

export function RefreshButton({ onClick }) {
  return (
    <button type="button" onClick={onClick} aria-label="Refresh the list" title="Refresh"
      className={`p-1.5 rounded-md ${MUTED} hover:text-slate-900 dark:hover:text-zinc-100 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-colors`}>
      <Icon>{ICON.refresh}</Icon>
    </button>
  )
}

// record → records, entry → entries, category → categories
const plural = (noun) => (/[^aeiou]y$/.test(noun) ? `${noun.slice(0, -1)}ies` : `${noun}s`)

// The card around a list. `count`/`total`: shown "549 of 2,423 records" when filtered.
export function ListCard({ title, filtered = false, count, total, noun = 'record', loading, actions, children, footer }) {
  const n = (v) => Number(v).toLocaleString('en-PH')
  return (
    <div className="bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800">
      <div className="px-5 py-3 border-b border-slate-200 dark:border-zinc-800 flex flex-wrap items-center gap-x-3 gap-y-2">
        <p className="text-sm font-semibold text-slate-700 dark:text-zinc-300">{title}</p>
        {!loading && count != null && (
          <span className={`text-xs font-medium ${MUTED} bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700 px-2 py-0.5 rounded-full`}>
            {n(count)}{filtered && total != null && total !== count ? ` of ${n(total)}` : ''} {count === 1 ? noun : plural(noun)}
          </span>
        )}
        {actions && <div className="ml-auto flex items-center gap-1">{actions}</div>}
      </div>
      {children}
      {footer}
    </div>
  )
}

export function Pager({ page, pageSize, total, onPage }) {
  const pages = Math.max(1, Math.ceil(total / pageSize))
  if (total <= pageSize) return null
  const btn = 'px-3 py-1.5 text-sm rounded-md border border-slate-300 dark:border-zinc-700 text-slate-700 dark:text-zinc-300 hover:bg-slate-50 dark:hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors'
  return (
    <div className="px-5 py-3 border-t border-slate-200 dark:border-zinc-800 flex items-center justify-between gap-3">
      <p className={`text-sm ${MUTED}`}>
        {((page - 1) * pageSize + 1).toLocaleString('en-PH')}–{Math.min(page * pageSize, total).toLocaleString('en-PH')} of {total.toLocaleString('en-PH')}
      </p>
      <div className="flex items-center gap-1.5">
        <button onClick={() => onPage(Math.max(1, page - 1))} disabled={page === 1} className={btn}>Previous</button>
        <span className={`text-sm ${MUTED} px-1`}>Page {page} of {pages}</span>
        <button onClick={() => onPage(Math.min(pages, page + 1))} disabled={page === pages} className={btn}>Next</button>
      </div>
    </div>
  )
}

export function ListSkeleton({ rows = 6 }) {
  return (
    <div className="divide-y divide-slate-100 dark:divide-zinc-800" aria-busy="true">
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="flex items-center gap-4 px-5 py-3.5">
          <div className="animate-pulse h-3 w-32 rounded bg-slate-200 dark:bg-zinc-800" />
          <div className="animate-pulse h-5 w-20 rounded-full bg-slate-200 dark:bg-zinc-800" />
          <div className="animate-pulse h-3 w-40 rounded bg-slate-200 dark:bg-zinc-800 ml-auto" />
        </div>
      ))}
    </div>
  )
}

export function ListEmpty({ children }) {
  return <p className={`py-16 text-center text-sm ${MUTED}`}>{children}</p>
}

export const TD = 'px-4 py-3 align-top'

// columns: [{ key, label, className (width / responsive visibility, applied to th and td),
//             cell: (row, open) => node }]. The first column's cell gets `open`, so it can render
// a button - the keyboard way into a row. `leading` renders before the rows (e.g. DraftRows);
// `wideEnd` makes the last column wide enough for DraftRows' Continue/Discard buttons.
export function DataTable({ columns, rows, rowKey, onOpen, caption, leading, wideEnd = false, selectedKey }) {
  return (
    <table className="w-full table-fixed text-sm divide-y divide-slate-100 dark:divide-zinc-800">
      {caption && <caption className="sr-only">{caption}</caption>}
      <thead>
        <tr>
          {columns.map((c) => (
            <th key={c.key} scope="col" className={`px-4 py-3 text-left text-xs font-semibold ${MUTED} uppercase tracking-wide ${c.className || ''}`}>{c.label}</th>
          ))}
          <th scope="col" className={wideEnd ? 'w-[8.5rem]' : 'w-10'}><span className="sr-only">Open</span></th>
        </tr>
      </thead>
      <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
        {leading}
        {rows.map((row) => {
          const key = rowKey(row)
          const open = onOpen ? () => onOpen(row) : undefined
          return (
            <tr key={key} onClick={open}
              className={`${open ? 'cursor-pointer' : ''} hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100 ${selectedKey === key ? 'bg-slate-50 dark:bg-zinc-800/40' : ''}`}>
              {columns.map((c, i) => (
                <td key={c.key} className={`${TD} ${c.className || ''}`}>{c.cell(row, i === 0 ? open : undefined)}</td>
              ))}
              <td className={`${TD} text-right ${MUTED}`} aria-hidden="true">
                {open && <Icon className="h-4 w-4 inline-block mt-1"><path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" /></Icon>}
              </td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

// The usual first cell: a small mono line (e.g. property number) over a bold title that is a
// button opening the row; `extra` adds a muted line, e.g. what the hidden columns would show.
export function PrimaryCell({ code, title, extra, open }) {
  return (
    <div className="min-w-0">
      {code && <p className={`font-mono text-xs ${MUTED} truncate`}>{code}</p>}
      {open ? (
        <button type="button" onClick={(e) => { e.stopPropagation(); open() }}
          className="block max-w-full text-left text-sm font-medium text-slate-900 dark:text-white truncate hover:underline rounded">
          {title || 'N/A'}
        </button>
      ) : (
        <p className="text-sm font-medium text-slate-900 dark:text-white truncate">{title || 'N/A'}</p>
      )}
      {extra}
    </div>
  )
}

export function MutedCell({ children, sub }) {
  return (
    <div className="min-w-0">
      <p className="text-sm text-slate-700 dark:text-zinc-200 truncate">{children || 'N/A'}</p>
      {sub && <p className={`text-xs ${MUTED} truncate mt-0.5`}>{sub}</p>}
    </div>
  )
}

export function fmtDate(dt) {
  if (!dt) return 'N/A'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}

export function fmtPeso(v) {
  if (v == null || v === '') return 'N/A'
  return '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 })
}

// A person field may come back as a name string or as a user object.
export const personName = (p) => (typeof p === 'string' ? p : p?.fullName || p?.username) || ''
