// Unsaved form drafts (see useFormDraft / useDraftList) shown at the top of a module's
// table, laid out in the table's own columns so a half-filled form can be picked up
// from the list instead of reopening it.
//
//   columns:  one { className, render(record) } per data column (the actions column is added here)
//   toRecord: draft -> a record shaped like the table's rows (draft fields over the saved record)
function DraftRows({ drafts, columns, toRecord, onContinue, onDiscard }) {
  if (!drafts?.length) return null
  return drafts.map((d) => {
    const record = toRecord(d)
    const when = new Date(d.savedAt).toLocaleString('en-PH', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
    return (
      <tr key={d.key} onClick={() => onContinue(d)} title="Continue this draft"
        className="bg-sky-50/70 dark:bg-sky-950/25 hover:bg-sky-100/70 dark:hover:bg-sky-950/40 transition-colors duration-100 cursor-pointer">
        {columns.map((col, i) => (
          <td key={i} className={col.className}>
            {i === 0 && (
              <p className="mb-1 flex items-center gap-1.5 whitespace-nowrap">
                <span className="inline-flex items-center rounded-full border border-sky-300 dark:border-sky-800 bg-white dark:bg-sky-950 px-2 py-0.5 text-2xs font-semibold uppercase tracking-wider text-sky-800 dark:text-sky-300">
                  {d.id === 'new' ? 'New draft' : 'Unsaved changes'}
                </span>
                <span className="text-2xs text-slate-500 dark:text-zinc-400">{when}</span>
              </p>
            )}
            {col.render(record)}
          </td>
        ))}
        <td className="px-5 py-3.5" onClick={(e) => e.stopPropagation()}>
          <div className="flex items-center justify-end gap-1">
            <button type="button" onClick={() => onContinue(d)}
              className="px-2.5 py-1 rounded-md text-xs font-semibold bg-brand-700 text-white hover:bg-brand-800 transition-colors duration-150 whitespace-nowrap">
              Continue
            </button>
            <button type="button" onClick={() => onDiscard(d.key)} title="Discard draft" aria-label="Discard draft"
              className="p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-950/40 transition-all duration-150">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
            </button>
          </div>
        </td>
      </tr>
    )
  })
}

export default DraftRows
