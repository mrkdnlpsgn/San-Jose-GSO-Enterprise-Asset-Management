import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'

const EXIT_MS = 180

function Modal({ title, subtitle, children, onClose, size = 'lg' }) {
  const widths = { md: 'max-w-lg', lg: 'max-w-2xl', xl: 'max-w-4xl' }
  const [entered, setEntered] = useState(false)
  const [closing, setClosing] = useState(false)

  const requestClose = () => {
    if (closing) return
    setClosing(true)
    setTimeout(onClose, EXIT_MS)
  }

  useEffect(() => {
    const raf = requestAnimationFrame(() => requestAnimationFrame(() => setEntered(true)))
    return () => cancelAnimationFrame(raf)
  }, [])

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') requestClose() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      aria-label={title}
    >
      {/* Backdrop */}
      <div
        className={`absolute inset-0 bg-black/30 dark:bg-zinc-950/80 transition-opacity duration-[180ms] ease-[cubic-bezier(0.25,1,0.5,1)] ${!entered || closing ? 'opacity-0' : 'opacity-100'}`}
        onClick={requestClose}
      />

      {/* Panel */}
      <div className={`
        relative bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700
        rounded-xl shadow-2xl shadow-black/10 dark:shadow-black/60
        w-full ${widths[size]} flex flex-col max-h-[90vh]
        transition-[opacity,transform] duration-[220ms] ease-[cubic-bezier(0.16,1,0.3,1)]
        ${!entered || closing ? 'opacity-0 scale-95 translate-y-2' : 'opacity-100 scale-100 translate-y-0'}
      `}>
        {/* Header */}
        <div className="flex items-start justify-between px-6 py-4 border-b border-slate-200 dark:border-zinc-800">
          <div>
            <h2 className="text-sm font-semibold text-gov-700 dark:text-white">{title}</h2>
            {subtitle && (
              <p className="text-xs text-slate-400 dark:text-zinc-500 mt-0.5">{subtitle}</p>
            )}
          </div>
          <button
            onClick={requestClose}
            className="ml-4 p-1.5 rounded-md text-slate-400 dark:text-zinc-500 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150 active:scale-95"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
            </svg>
          </button>
        </div>

        {/* Body */}
        <div className="px-6 py-4 overflow-y-auto">
          {children}
        </div>
      </div>
    </div>,
    document.body
  )
}

export default Modal
