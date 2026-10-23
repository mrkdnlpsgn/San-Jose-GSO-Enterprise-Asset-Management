import { createContext, useContext, useState, useCallback, useMemo } from 'react'

const ToastContext = createContext({ show: () => {} })

// ── Icons ─────────────────────────────────────────────────────────────────────
const ICONS = {
  success: (
    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
    </svg>
  ),
  error: (
    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
    </svg>
  ),
  warning: (
    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
      <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
    </svg>
  ),
  info: (
    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
    </svg>
  ),
}

const STYLES = {
  success: { wrap: 'border-emerald-700/50 bg-emerald-950/60', icon: 'text-emerald-400' },
  error:   { wrap: 'border-red-700/50   bg-red-950/60',     icon: 'text-red-400'     },
  warning: { wrap: 'border-amber-700/50  bg-amber-950/60',   icon: 'text-amber-400'   },
  info:    { wrap: 'border-blue-700/50   bg-blue-950/60',    icon: 'text-blue-400'    },
}

// ── Single toast item ─────────────────────────────────────────────────────────
function ToastItem({ toast, onDismiss }) {
  const s = STYLES[toast.type] ?? STYLES.info
  const visible = toast.phase !== 'entering' && toast.phase !== 'exiting'

  return (
    <div
      className={`
        flex items-start gap-3 px-4 py-3.5 rounded-xl border
        ${s.wrap}
        bg-zinc-900/90 backdrop-blur-md
        shadow-2xl shadow-black/60
        w-[340px] max-w-[calc(100vw-2rem)]
        transition-[opacity,transform] duration-200 ease-[cubic-bezier(0.25,1,0.5,1)]
        ${visible ? 'opacity-100 translate-x-0' : 'opacity-0 translate-x-7'}
        pointer-events-auto
      `}
    >
      <span className={`mt-px ${s.icon}`}>{ICONS[toast.type]}</span>

      <div className="flex-1 min-w-0">
        {toast.title && (
          <p className="text-sm font-semibold text-white leading-tight">{toast.title}</p>
        )}
        <p className={`text-sm leading-snug ${toast.title ? 'text-zinc-400 mt-0.5' : 'text-white font-medium'}`}>
          {toast.message}
        </p>
      </div>

      <button
        onClick={() => onDismiss(toast.id)}
        className="flex-shrink-0 mt-px text-zinc-600 hover:text-zinc-300 transition-colors duration-150"
      >
        <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
        </svg>
      </button>
    </div>
  )
}

// ── Provider ──────────────────────────────────────────────────────────────────
export function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([])

  const dismiss = useCallback((id) => {
    setToasts((prev) => prev.map((t) => t.id === id ? { ...t, phase: 'exiting' } : t))
    setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id))
    }, 210)
  }, [])

  const show = useCallback((message, type = 'success', options = {}) => {
    const id       = crypto.randomUUID()
    const duration = options.duration ?? (type === 'error' ? 5000 : type === 'warning' ? 4000 : 3500)

    setToasts((prev) => [...prev, { id, message, type, title: options.title, phase: 'entering' }])
    requestAnimationFrame(() => requestAnimationFrame(() => {
      setToasts((prev) => prev.map((t) => t.id === id ? { ...t, phase: 'idle' } : t))
    }))
    setTimeout(() => dismiss(id), duration)
  }, [dismiss])

  const value = useMemo(() => ({ show }), [show])

  return (
    <ToastContext.Provider value={value}>
      {children}

      {/* Toast container - fixed top-right, stacked */}
      <div className="fixed top-4 right-4 z-[200] flex flex-col gap-2.5 pointer-events-none">
        {toasts.map((t) => (
          <ToastItem key={t.id} toast={t} onDismiss={dismiss} />
        ))}
      </div>
    </ToastContext.Provider>
  )
}

export const useToast = () => useContext(ToastContext)
