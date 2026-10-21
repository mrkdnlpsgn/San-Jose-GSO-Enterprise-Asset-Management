import { useEffect } from 'react'

// tone "danger" (default): red warning, for deleting and signing out.
// tone "primary": brand green with a download icon, for a harmless confirm like downloading a file.
function ConfirmDialog({
  title   = 'Are you sure?',
  message,
  confirmLabel = 'Delete',
  tone = 'danger',
  onConfirm,
  onCancel,
}) {
  const primary = tone === 'primary'
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onCancel() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onCancel])

  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center p-4 animate-fade-slide"
      role="alertdialog"
      aria-modal="true"
      aria-label={title}
    >
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/30 dark:bg-zinc-950/80"
        onClick={onCancel}
      />

      {/* Panel */}
      <div className="relative bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 rounded-xl shadow-2xl shadow-black/10 dark:shadow-black/60 w-full max-w-sm p-6">
        {/* Icon */}
        <div className={`w-11 h-11 rounded-full flex items-center justify-center mx-auto mb-4 ${primary ? 'bg-brand-50 dark:bg-brand-500/15' : 'bg-red-50 dark:bg-red-950'}`}>
          {primary ? (
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-brand-700 dark:text-brand-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
            </svg>
          ) : (
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-red-500 dark:text-red-400" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
            </svg>
          )}
        </div>

        {/* Text */}
        <h2 className="text-sm font-semibold text-gov-700 dark:text-white text-center">{title}</h2>
        {message && (
          <p className="text-xs text-slate-500 dark:text-zinc-400 text-center mt-2 leading-relaxed">{message}</p>
        )}

        {/* Actions */}
        <div className="flex gap-3 mt-6">
          <button
            onClick={onCancel}
            className="flex-1 py-2.5 text-sm font-semibold rounded-md bg-slate-100 dark:bg-zinc-800 text-slate-700 dark:text-zinc-300 border border-slate-200 dark:border-zinc-700 hover:bg-slate-200 dark:hover:bg-zinc-700 transition-all duration-150 active:scale-[0.97]"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className={`flex-1 py-2.5 text-sm font-semibold rounded-md text-white transition-all duration-150 active:scale-[0.97] ${primary ? 'bg-brand-700 hover:bg-brand-800' : 'bg-red-600 hover:bg-red-500 active:bg-red-700'}`}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}

export default ConfirmDialog
