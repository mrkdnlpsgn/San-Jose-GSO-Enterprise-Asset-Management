import { forwardRef, useId } from 'react'

// Without an explicit `id`, one is generated so the label is always tied to its input
// (clicking the label focuses the field; screen readers announce the label). The hint /
// error text is linked with aria-describedby, and an error sets aria-invalid.
// startIcon: a small decorative icon drawn inside the left edge of the field.
const Input = forwardRef(function Input({ label, error, hint, startIcon, endAdornment, adornmentClassName = 'w-10', className = '', id, ...props }, ref) {
  const autoId = useId()
  const inputId = id || autoId
  const noteId = `${inputId}-note`
  const note = error || hint

  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <label htmlFor={inputId} className="text-sm font-medium text-slate-700 dark:text-zinc-300">
          {label}
        </label>
      )}
      <div className="relative">
        {startIcon && (
          <div className={`pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5 ${error ? 'text-red-500' : 'text-slate-400 dark:text-zinc-500'}`} aria-hidden="true">
            {startIcon}
          </div>
        )}
        <input
          ref={ref}
          id={inputId}
          aria-invalid={error ? true : undefined}
          aria-describedby={note ? noteId : undefined}
          className={`
            w-full rounded-md border px-3.5 py-2.5 text-sm
            bg-white dark:bg-zinc-800 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-zinc-500
            focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500
            transition-all duration-150
            ${endAdornment ? 'pr-10' : ''}
            ${startIcon ? 'pl-11' : ''}
            ${error
              ? 'border-red-500 focus:ring-red-400'
              : 'border-slate-300 dark:border-zinc-700 hover:border-slate-400 dark:hover:border-zinc-600'
            }
            ${className}
          `}
          {...props}
        />
        {endAdornment && (
          <div className={`absolute inset-y-0 right-0 flex items-center justify-center ${adornmentClassName}`}>
            {endAdornment}
          </div>
        )}
      </div>
      {hint && !error && <p id={noteId} className="text-sm text-slate-600 dark:text-zinc-400">{hint}</p>}
      {error && <p id={noteId} className="text-sm font-medium text-red-600 dark:text-red-400">{error}</p>}
    </div>
  )
})

export default Input
