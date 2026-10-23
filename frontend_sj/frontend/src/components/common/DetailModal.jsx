import { useEffect } from 'react'
import { HEADER_OFFSET } from '../layout/layoutSizes'
import { Icon } from './ListKit'

// The centered window a list row opens to show the complete record (same look as the asset
// view). Header: title, a line under it (code, badges), labelled action buttons, close.
//   actions: [{ label, icon, onClick, tone: 'default' | 'danger' | 'primary' }]
//   escDisabled: true while a dialog of its own (photos, confirm) is open on top
export default function DetailModal({ title, subtitle, actions = [], onClose, escDisabled = false, label, children, footer }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape' && !escDisabled) onClose() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose, escDisabled])

  return (
    <>
      <div className="fixed inset-0 z-30 backdrop-blur-sm pointer-events-none" style={{ top: HEADER_OFFSET }} />
      <div className="fixed inset-0 z-30 bg-zinc-950/20 animate-fade-in" style={{ top: HEADER_OFFSET }} onClick={onClose} />
      <div className="fixed inset-x-0 bottom-0 z-40 flex items-center justify-center p-3 sm:p-6 pointer-events-none" style={{ top: HEADER_OFFSET }}>
        <div role="dialog" aria-modal="true" aria-label={label || (typeof title === 'string' ? title : 'Details')}
          className="pointer-events-auto w-full max-w-[56rem] max-h-full bg-white dark:bg-zinc-950 border border-slate-200 dark:border-zinc-800 rounded-xl flex flex-col shadow-2xl overflow-hidden animate-scale-in">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-2 px-5 sm:px-6 py-3 border-b border-slate-200 dark:border-zinc-800 flex-shrink-0">
            <div className="flex-1 min-w-[14rem]">
              <h2 className="text-lg font-semibold text-slate-900 dark:text-white leading-snug">{title}</h2>
              {subtitle && <div className="flex items-center gap-x-2 gap-y-1 mt-1 flex-wrap text-sm">{subtitle}</div>}
            </div>
            {actions.length > 0 && (
              <div className="order-last sm:order-none w-full sm:w-auto flex flex-wrap items-center gap-1.5">
                {actions.map((a) => <ModalAction key={a.label} {...a} />)}
              </div>
            )}
            <button onClick={onClose} aria-label="Close" title="Close (Esc)"
              className="p-1.5 rounded-md text-slate-600 dark:text-zinc-400 hover:text-slate-900 dark:hover:text-zinc-100 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all">
              <Icon><path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" /></Icon>
            </button>
          </div>
          <div className="flex-1 overflow-y-auto px-5 sm:px-6 py-4">{children}</div>
          {footer && <div className="px-5 sm:px-6 py-3 border-t border-slate-200 dark:border-zinc-800 flex flex-wrap items-center gap-2 flex-shrink-0">{footer}</div>}
        </div>
      </div>
    </>
  )
}

const ACTION_TONE = {
  default: 'border-slate-200 dark:border-zinc-700 text-slate-700 dark:text-zinc-200 hover:bg-slate-50 dark:hover:bg-zinc-800',
  primary: 'border-emerald-600/40 text-emerald-800 dark:text-emerald-300 hover:bg-emerald-500/10',
  danger:  'border-red-500/30 text-red-700 dark:text-red-300 hover:bg-red-500/10',
}

export function ModalAction({ label, icon, onClick, tone = 'default', disabled = false }) {
  return (
    <button type="button" onClick={onClick} disabled={disabled}
      className={`flex items-center justify-center gap-1.5 px-2.5 py-1.5 rounded-md whitespace-nowrap border text-sm font-medium transition-colors disabled:opacity-50 ${ACTION_TONE[tone]}`}>
      {icon && <Icon>{icon}</Icon>}
      {label}
    </button>
  )
}

// Sections laid out in two columns when there's room.
export function DetailGrid({ children }) {
  return <div className="grid grid-cols-1 md:grid-cols-2 gap-x-10 gap-y-3">{children}</div>
}

export function DetailSection({ title, children, wide = false }) {
  return (
    <section className={wide ? 'md:col-span-2' : ''}>
      <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-600 dark:text-zinc-400 mb-0.5">{title}</h3>
      {children}
    </section>
  )
}

export function DetailField({ label, value, mono = false }) {
  return (
    <div className="flex items-start gap-2 py-1.5 border-b border-slate-100 dark:border-zinc-800/60 last:border-0">
      <span className="text-xs text-slate-600 dark:text-zinc-400 w-36 flex-shrink-0 pt-0.5">{label}</span>
      <span className={`text-sm text-slate-900 dark:text-zinc-100 font-medium break-words min-w-0 whitespace-pre-line ${mono ? 'font-mono' : ''}`}>
        {value === '' || value == null ? 'N/A' : value}
      </span>
    </div>
  )
}
