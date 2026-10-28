// A maintenance record's parts and labor lines (see MaintenanceItemService), read-only: parts with
// unit, quantity, unit cost and total, then the labor, then the cost of repair.

const money = (v) => '₱' + Number(v ?? 0).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const qty = (v) => (v == null ? '' : Number(v).toLocaleString('en-PH', { maximumFractionDigits: 2 }))

export default function MaintenanceLines({ items = [], cost }) {
  if (!items.length) return null
  const parts = items.filter((i) => i.kind !== 'LABOR')
  const labor = items.filter((i) => i.kind === 'LABOR')
  const th = 'px-2 py-1.5 text-left text-xs font-semibold text-slate-500 dark:text-zinc-400'
  const td = 'px-2 py-1.5 text-sm text-slate-700 dark:text-zinc-200'
  return (
    <div className="overflow-x-auto rounded-lg border border-slate-200 dark:border-zinc-800">
      <table className="w-full min-w-[30rem]">
        <thead className="bg-slate-50 dark:bg-zinc-900">
          <tr><th className={th}>Particular</th><th className={th}>Unit</th><th className={`${th} text-right`}>Qty</th><th className={`${th} text-right`}>Unit cost</th><th className={`${th} text-right`}>Total</th></tr>
        </thead>
        <tbody className="divide-y divide-slate-100 dark:divide-zinc-800">
          {parts.map((p, i) => (
            <tr key={`p${i}`}>
              <td className={td}>{p.particular}</td><td className={td}>{p.unit || ''}</td>
              <td className={`${td} text-right tabular-nums`}>{qty(p.quantity)}</td>
              <td className={`${td} text-right tabular-nums`}>{money(p.unitCost)}</td>
              <td className={`${td} text-right tabular-nums`}>{money(p.totalCost)}</td>
            </tr>
          ))}
          {labor.length > 0 && (
            <tr><td colSpan={5} className={`${td} italic text-slate-500 dark:text-zinc-400`}>Labor</td></tr>
          )}
          {labor.map((l, i) => (
            <tr key={`l${i}`}>
              <td className={td} colSpan={4}>{l.particular}</td>
              <td className={`${td} text-right tabular-nums`}>{money(l.totalCost)}</td>
            </tr>
          ))}
          <tr className="bg-slate-50 dark:bg-zinc-900">
            <td colSpan={4} className={`${td} font-semibold`}>Cost of repair</td>
            <td className={`${td} text-right font-semibold tabular-nums`}>{money(cost)}</td>
          </tr>
        </tbody>
      </table>
    </div>
  )
}
