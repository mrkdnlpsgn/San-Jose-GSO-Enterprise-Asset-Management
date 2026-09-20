import { useState } from 'react'

// Same columns as the main Assets table — used for the main table's header and for the
// devices of a group.
export const TABLE_HEADERS = ['Property No.', 'PAR No.', 'Description', 'Category', 'Qty (Property Card)', 'Qty (Physical Count)', 'Shortage/Overage Qty', 'Shortage/Overage Value', 'Location', 'Unit Value', 'Date', 'Remarks', '']
export const TH_CLASS = 'px-5 py-3 text-left text-2xs font-semibold text-slate-500 dark:text-zinc-500 uppercase tracking-wider whitespace-nowrap'

const includes = (v, q) => v && String(v).toLowerCase().includes(q)

// What the search box matches for an asset: the numbers that identify a device, its serial,
// and the people involved with it (accountable person / current user).
export const deviceMatches = (a, q) => [
  a.propertyNumber, a.parNumber, a.serialNumber, a.accountablePerson?.fullName, a.currentUser?.fullName,
].some((v) => includes(v, q))

// Same, for a maintenance / disposal / history record — the device is the record's nested `asset`.
export const recordMatches = (r, q) => deviceMatches(r.asset || {}, q)

// Groups a list of records (or assets) by group id. Items that share a group id become one
// `group` entry (when at least `min` of them are present); everything else stays a plain row.
export function groupEntries(list, groupIdOf, min = 2) {
  const groups = new Map()
  const out = []
  for (const item of list) {
    const gid = groupIdOf(item)
    if (gid) {
      let g = groups.get(gid)
      if (!g) { g = { type: 'group', key: `g:${gid}`, groupId: gid, members: [] }; groups.set(gid, g); out.push(g) }
      g.members.push(item)
    } else {
      out.push({ type: 'item', key: `i:${out.length}:${item.id}`, item })
    }
  }
  return out.map((e) => (e.type === 'group' && e.members.length < min ? { type: 'item', key: `i:${e.members[0].id}`, item: e.members[0] } : e))
}

// A group's members as a table, with a search bar. `renderRow(item)` supplies each <tr> so the
// rows look and behave exactly like the page's main table. Defaults are the Assets page's:
// asset columns, asset search, "devices".
export default function GroupDevicesTable({
  members, renderRow,
  headers = TABLE_HEADERS, matches = deviceMatches, noun = 'devices',
  placeholder = 'Search property no., PAR no., serial no. or person…',
}) {
  const [raw, setRaw] = useState('')
  const q = raw.trim().toLowerCase()
  const shown = q ? members.filter((m) => matches(m, q)) : members

  return (
    <div className="rounded-lg border border-slate-200 dark:border-zinc-800 overflow-hidden bg-white dark:bg-zinc-950" onClick={(e) => e.stopPropagation()}>
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 px-4 py-3 border-b border-slate-200 dark:border-zinc-800">
        <div className="relative w-full sm:max-w-sm">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-500 pointer-events-none" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
          </svg>
          <input
            value={raw}
            onChange={(e) => setRaw(e.target.value)}
            placeholder={placeholder}
            className="w-full rounded-md border border-slate-200 dark:border-zinc-700 pl-9 pr-3 py-2 text-sm bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          />
        </div>
        <p className="text-xs text-slate-400 dark:text-zinc-500 whitespace-nowrap">
          {q ? `${shown.length} of ${members.length} ${noun}` : `${members.length} ${noun}`}
        </p>
      </div>
      <div className="overflow-x-auto">
        <table className="min-w-full text-sm divide-y divide-slate-100 dark:divide-zinc-800">
          <thead>
            <tr>{headers.map((h, i) => <th key={`${h}${i}`} className={TH_CLASS}>{h}</th>)}</tr>
          </thead>
          <tbody className="divide-y divide-slate-100 dark:divide-zinc-800/60">
            {shown.length === 0 ? (
              <tr><td colSpan={headers.length} className="px-5 py-6 text-center text-sm text-zinc-500">No {noun} match "{raw}".</td></tr>
            ) : shown.map((m) => renderRow(m))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
