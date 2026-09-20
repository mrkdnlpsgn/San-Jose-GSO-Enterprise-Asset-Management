// A plain (read-only) asset row with the same columns as the main Assets table — used where a
// group's devices are shown outside the Assets page (e.g. from the Maintenance / Disposal
// group drawer). `onOpen` opens the device on the Assets page.

const CONDITION_BADGE = {
  SERVICEABLE:   'bg-emerald-500/10 text-emerald-400 ring-1 ring-emerald-500/20',
  REPAIRABLE:    'bg-amber-500/10 text-amber-400 ring-1 ring-amber-500/20',
  UNSERVICEABLE: 'bg-red-500/10 text-red-400 ring-1 ring-red-500/20',
}

function fmt(dt) {
  if (!dt) return '—'
  return new Date(dt).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })
}
function php(v) {
  if (v == null) return '—'
  return '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 })
}

const dash = <span className="text-slate-400 dark:text-zinc-600">—</span>

export default function DeviceRow({ asset: a, onOpen }) {
  const diff = a.physicalCount != null ? a.physicalCount - (a.quantity ?? 0) : null
  const val = diff != null ? diff * Number(a.unitValue ?? 0) : null
  const color = diff == null ? '' : diff < 0 ? 'text-red-400' : diff > 0 ? 'text-emerald-400' : 'text-slate-400 dark:text-zinc-500'
  return (
    <tr className="hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-colors duration-100 cursor-pointer" onClick={() => onOpen(a)}>
      <td className="px-5 py-3.5 whitespace-nowrap"><span className="font-mono text-xs text-slate-600 dark:text-zinc-300">{a.propertyNumber}</span></td>
      <td className="px-5 py-3.5 whitespace-nowrap"><span className="font-mono text-xs text-slate-600 dark:text-zinc-300">{a.parNumber || dash}</span></td>
      <td className="px-5 py-3.5">
        <p className="text-sm font-medium text-slate-900 dark:text-white truncate max-w-[180px]">{a.description}</p>
        <div className="mt-0.5 space-y-0.5 text-2xs text-slate-400 dark:text-zinc-500">
          {a.serialNumber && <p className="font-mono">S/N {a.serialNumber}</p>}
          {a.accountablePerson?.fullName && <p>Accountable: {a.accountablePerson.fullName}</p>}
          {a.currentUser?.fullName && <p>Using: {a.currentUser.fullName}</p>}
        </div>
      </td>
      <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{a.category?.categoryName || '—'}</td>
      <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap text-center">{a.quantity ?? '—'}</td>
      <td className="px-5 py-3.5 text-xs whitespace-nowrap text-center">{a.physicalCount != null ? a.physicalCount : dash}</td>
      <td className={`px-5 py-3.5 text-xs whitespace-nowrap text-center font-medium ${color}`}>{diff == null ? dash : diff > 0 ? `+${diff}` : diff}</td>
      <td className={`px-5 py-3.5 text-xs whitespace-nowrap text-center font-medium ${color}`}>
        {val == null ? dash : (val > 0 ? '+' : '') + '₱' + Math.abs(val).toLocaleString('en-PH', { minimumFractionDigits: 2 })}
      </td>
      <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{a.office?.officeName || '—'}</td>
      <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{php(a.unitValue)}</td>
      <td className="px-5 py-3.5 text-slate-500 dark:text-zinc-400 text-xs whitespace-nowrap">{fmt(a.acquisitionDate)}</td>
      <td className="px-5 py-3.5 text-xs max-w-[200px]">
        <div className="flex flex-col gap-1">
          <span className={`inline-flex items-center self-start px-2 py-0.5 rounded-full text-xs font-semibold ${CONDITION_BADGE[a.condition] || ''}`}>{a.condition}</span>
          {a.remarks && <span className="text-slate-500 dark:text-zinc-400 truncate" title={a.remarks}>{a.remarks}</span>}
        </div>
      </td>
      <td className="px-5 py-3.5 text-right">
        <span className="text-xs font-semibold text-brand-400">Open</span>
      </td>
    </tr>
  )
}
