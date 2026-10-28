import { useState } from 'react'
import Button from './Button'
import { printReturnSlip, printPar, PAPERS_OFFICER_DEFAULTS } from '../../utils/returnPapersPrint'

// An asset's Property Return Slips and PARs (see ReturnSlipService), one row per end-user change:
// the old end user's return slip and the new one's PAR, each with its own Print button. The
// asset's original PAR (kept when it was first reissued) is a row of its own, under the changes.

const INPUT = 'w-full rounded-md border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3 py-2 text-sm text-slate-800 dark:text-zinc-100 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500'

// Who signs the papers for the GSO, remembered in this browser.
const OFFICER_KEY = 'return-papers-officer'
const readOfficer = () => {
  try { return { ...PAPERS_OFFICER_DEFAULTS, ...JSON.parse(localStorage.getItem(OFFICER_KEY) || '{}') } } catch { return { ...PAPERS_OFFICER_DEFAULTS } }
}
const saveOfficer = (o) => { try { localStorage.setItem(OFFICER_KEY, JSON.stringify(o)) } catch { /* not remembered */ } }

const fmt = (d) => (d ? new Date(`${String(d).slice(0, 10)}T00:00:00`).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' }) : 'N/A')

export const hasReturnPapers = (papers) => !!papers && (papers.returnSlips.length > 0 || papers.pars.length > 0)

export default function ReturnPapers({ papers }) {
  const [officer, setOfficer] = useState(readOfficer)
  const setOfficerField = (key) => (e) => {
    const next = { ...officer, [key]: e.target.value }
    setOfficer(next)
    saveOfficer(next)
  }

  const byTransfer = new Map()
  const rowFor = (transferId, at) => {
    if (!byTransfer.has(transferId)) byTransfer.set(transferId, { key: `t${transferId}`, at })
    return byTransfer.get(transferId)
  }
  papers.returnSlips.forEach((s) => { rowFor(s.transferId ?? `s${s.id}`, s.createdAt).slip = s })
  const originals = []
  papers.pars.forEach((p) => {
    if (p.original || p.transferId == null) originals.push({ key: `p${p.id}`, at: p.createdAt, par: p, original: true })
    else rowFor(p.transferId, p.createdAt).par = p
  })
  const rows = [
    ...[...byTransfer.values()].sort((x, y) => String(y.at).localeCompare(String(x.at))),
    ...originals.sort((x, y) => String(y.at).localeCompare(String(x.at))),
  ]

  return (
    <div className="space-y-3">
      <p className="text-sm text-slate-600 dark:text-zinc-400">
        Made each time this asset changed end user: the old one returns it on a Property Return Slip and the new one gets a new PAR. Print them for signing.
      </p>
      <ul className="space-y-2">
        {rows.map((r) => (
          <li key={r.key} className="px-3.5 py-3 rounded-lg border border-slate-200 dark:border-zinc-800 bg-slate-50 dark:bg-zinc-900 space-y-2">
            <div className="min-w-0">
              <p className="text-sm font-semibold text-slate-800 dark:text-zinc-100">
                {r.original
                  ? `Original PAR, issued to ${r.par.personnelName || 'no end user'}`
                  : <>{r.slip?.returnedByName || 'No end user'} <span aria-hidden="true">→</span><span className="sr-only">to</span> {r.par?.personnelName || 'no end user'}</>}
              </p>
              <p className="text-xs text-slate-500 dark:text-zinc-400 mt-0.5">
                {fmt(r.original ? r.par.issueDate : (r.slip?.returnDate || r.par?.issueDate))}
                {r.slip && ` · Return Slip ${r.slip.slipNumber}`}
                {r.par && ` · PAR ${r.par.parNumber}`}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              {r.slip && <Button variant="secondary" size="sm" onClick={() => printReturnSlip(r.slip, officer)}>Print Return Slip</Button>}
              {r.par && <Button variant="secondary" size="sm" onClick={() => printPar(r.par, officer)}>Print PAR</Button>}
            </div>
          </li>
        ))}
      </ul>
      <details className="rounded-lg border border-slate-200 dark:border-zinc-800">
        <summary className="px-3.5 py-2.5 text-xs font-semibold text-slate-500 dark:text-zinc-400 cursor-pointer select-none">Signed for the GSO by {officer.name || 'N/A'}</summary>
        <div className="px-3.5 pb-3.5 grid grid-cols-1 sm:grid-cols-2 gap-3">
          <label className="block">
            <span className="block text-xs font-medium text-slate-600 dark:text-zinc-400 mb-1">Name</span>
            <input value={officer.name} onChange={setOfficerField('name')} className={INPUT} />
          </label>
          <label className="block">
            <span className="block text-xs font-medium text-slate-600 dark:text-zinc-400 mb-1">Position</span>
            <input value={officer.position} onChange={setOfficerField('position')} className={INPUT} />
          </label>
        </div>
      </details>
    </div>
  )
}
