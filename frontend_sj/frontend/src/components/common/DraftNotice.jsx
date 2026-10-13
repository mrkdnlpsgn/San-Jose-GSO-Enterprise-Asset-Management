// Shown at the top of a form when useFormDraft brought back unsaved input.
function DraftNotice({ draft }) {
  if (!draft?.restoredAt) return null
  const when = new Date(draft.restoredAt).toLocaleString('en-PH', {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  })

  return (
    <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-sky-200 dark:border-sky-900 bg-sky-50 dark:bg-sky-950/40 px-4 py-2.5" role="status">
      <p className="text-sm text-sky-900 dark:text-sky-200">
        <span className="font-semibold">Draft restored.</span> These are your unsaved entries from {when}.
      </p>
      <button
        type="button"
        onClick={draft.discard}
        className="text-sm font-semibold text-sky-800 dark:text-sky-300 underline underline-offset-2 hover:text-sky-950 dark:hover:text-sky-100"
      >
        Discard draft
      </button>
    </div>
  )
}

export default DraftNotice
