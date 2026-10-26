// Badge text is dark on light / light on dark so it stays readable (WCAG AA) in both themes.
export const CONDITION_BADGE = {
  NEW:           { label: 'New',           cls: 'bg-sky-500/10 text-sky-800 dark:text-sky-300 ring-1 ring-sky-500/30' },
  SERVICEABLE:   { label: 'Serviceable',   cls: 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 ring-1 ring-emerald-500/30' },
  REPAIRABLE:    { label: 'Repairable',    cls: 'bg-amber-500/10 text-amber-800 dark:text-amber-300 ring-1 ring-amber-500/30' },
  UNSERVICEABLE: { label: 'Unserviceable', cls: 'bg-red-500/10 text-red-700 dark:text-red-300 ring-1 ring-red-500/30' },
}
export const LIFECYCLE_BADGE = {
  REGISTERED:        { label: 'Registered',        cls: 'bg-blue-500/10 text-blue-700 dark:text-blue-300 ring-1 ring-blue-500/30' },
  ASSIGNED:          { label: 'Assigned',          cls: 'bg-slate-500/10 text-slate-700 dark:text-zinc-300 ring-1 ring-slate-500/30' },
  TRANSFERRED:       { label: 'Transferred',       cls: 'bg-violet-500/10 text-violet-700 dark:text-violet-300 ring-1 ring-violet-500/30' },
  UNDER_MAINTENANCE: { label: 'Under maintenance', cls: 'bg-amber-500/10 text-amber-800 dark:text-amber-300 ring-1 ring-amber-500/30' },
  DISPOSED:          { label: 'Disposed',          cls: 'bg-red-500/10 text-red-700 dark:text-red-300 ring-1 ring-red-500/30' },
  ARCHIVED:          { label: 'Archived',          cls: 'bg-zinc-500/10 text-zinc-700 dark:text-zinc-300 ring-1 ring-zinc-500/30' },
}

export function Badge({ map, value }) {
  const b = map[value]
  if (!b) return value ? <span className="text-xs text-slate-600 dark:text-zinc-400">{value}</span> : null
  return <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-semibold whitespace-nowrap ${b.cls}`}>{b.label}</span>
}

