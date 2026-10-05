import { useEffect, useRef, useState } from 'react'
import { TEXT_SIZES, useTheme } from '../../context/ThemeContext'

// Display settings (theme + text size) behind one gear button. Text size is there for
// employees with weaker eyesight; each option is previewed at its own size.
function SettingsMenu({ className = '' }) {
  const { isDark, toggle, textSize, setTextSize } = useTheme()
  const [open, setOpen] = useState(false)
  const ref = useRef(null)

  useEffect(() => {
    if (!open) return
    const onClick = (e) => { if (!ref.current?.contains(e.target)) setOpen(false) }
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', onClick)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onClick)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const optionClass = (active) =>
    `flex items-center justify-between gap-3 px-2.5 py-2 rounded-md text-left transition-colors duration-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 ${
      active
        ? 'bg-brand-500/10 text-brand-700 dark:text-brand-400 font-semibold'
        : 'text-slate-700 dark:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800'
    }`

  const check = (
    <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
    </svg>
  )

  return (
    // `className` may position it (e.g. absolute) — either way it anchors the menu
    <div ref={ref} className={className || 'relative'}>
      <button
        type="button"
        onClick={() => setOpen((p) => !p)}
        aria-haspopup="menu"
        aria-expanded={open}
        title="Display settings"
        className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-md text-sm font-medium text-slate-600 dark:text-zinc-300 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-zinc-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 transition-colors duration-150"
      >
        <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
        </svg>
        <span className="hidden sm:inline">Settings</span>
        <svg xmlns="http://www.w3.org/2000/svg" className={`h-4 w-4 transition-transform duration-150 ${open ? 'rotate-180' : ''}`} viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
        </svg>
      </button>

      {open && (
        <div role="menu" aria-label="Display settings"
          className="absolute right-0 mt-2 w-60 z-50 rounded-lg border border-slate-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 shadow-lg p-1.5">
          <p className="px-2.5 pt-1 pb-1.5 text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">Theme</p>
          <div className="grid grid-cols-2 gap-1">
            {[{ dark: false, label: 'Light' }, { dark: true, label: 'Dark' }].map((t) => (
              <button key={t.label} type="button" role="menuitemradio" aria-checked={isDark === t.dark}
                onClick={() => { if (isDark !== t.dark) toggle() }}
                className={optionClass(isDark === t.dark)}>
                <span className="text-sm">{t.label}</span>
                {isDark === t.dark && check}
              </button>
            ))}
          </div>

          <div className="my-1.5 h-px bg-slate-200 dark:bg-zinc-800" />

          <p className="px-2.5 pt-1 text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400">Text size</p>
          <p className="px-2.5 pb-1.5 text-xs text-slate-500 dark:text-zinc-400">Makes all text and buttons bigger on this computer.</p>
          {TEXT_SIZES.map((s) => (
            <button key={s.id} type="button" role="menuitemradio" aria-checked={s.id === textSize}
              onClick={() => setTextSize(s.id)}
              className={`w-full ${optionClass(s.id === textSize)}`}>
              {/* fixed px preview so each option shows its true relative size */}
              <span style={{ fontSize: `${14 * s.scale / 100}px` }}>{s.label}</span>
              {s.id === textSize && check}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

export default SettingsMenu
