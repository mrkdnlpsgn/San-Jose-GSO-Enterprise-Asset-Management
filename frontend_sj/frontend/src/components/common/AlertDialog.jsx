import { useEffect } from 'react'

// Single-button, informational counterpart to ConfirmDialog — for telling the
// user an action can't proceed (e.g. "this category has assets assigned to
// it"), not asking them to confirm one.
function AlertDialog({ title = 'Heads up', message, closeLabel = 'OK', onClose }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])

  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center p-4 animate-fade-slide"
      role="alertdialog"
      aria-modal="true"
      aria-label={title}
    >
      <div className="absolute inset-0 bg-black/30 dark:bg-zinc-950/80" onClick={onClose} />

      <div className="relative bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 rounded-xl shadow-2xl shadow-black/10 dark:shadow-black/60 w-full max-w-sm p-6">
        <div className="w-11 h-11 rounded-full bg-amber-50 dark:bg-amber-950 flex items-center justify-center mx-auto mb-4">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-amber-500 dark:text-amber-400" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
        </div>

        <h2 className="text-sm font-semibold text-slate-900 dark:text-white text-center">{title}</h2>
        {message && (
          <p className="text-xs text-slate-500 dark:text-zinc-400 text-center mt-2 leading-relaxed">{message}</p>
        )}

        <div className="mt-6">
          <button
            onClick={onClose}
            className="w-full py-2.5 text-sm font-semibold rounded-md bg-brand-700 text-white hover:bg-brand-800 active:bg-brand-900 transition-all duration-150 active:scale-[0.97]"
          >
            {closeLabel}
          </button>
        </div>
      </div>
    </div>
  )
}

export default AlertDialog
