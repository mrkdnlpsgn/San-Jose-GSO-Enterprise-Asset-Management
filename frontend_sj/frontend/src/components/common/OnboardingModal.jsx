import { useState, useEffect, useRef, useCallback } from 'react'
import Button from './Button'

const STORAGE_KEY = 'ict-inv-onboarded'

const CONCEPTS = [
  {
    term: 'Equipment Records and Devices',
    desc: 'An Equipment Record is one category item, such as "HP Laptop 14-inch". Individual units — each with their own serial number and acquisition value — are registered as Devices under that record.',
  },
  {
    term: 'Accountable Person',
    desc: 'The staff member physically responsible for the device. Update this field whenever a device is transferred to someone new so the system always reflects actual custody.',
  },
  {
    term: 'Tracking Logs',
    desc: 'All device activity is logged in the Tracking module. Use Add Log to record what happened: Checked Out, Checked In, Transferred, Maintenance / Repaired, Decommissioned / Disposed, or Reported Missing. The last log entry determines the device\'s current status.',
  },
  {
    term: 'Smart Suggestions',
    desc: 'The Dashboard automatically flags items that need attention — overdue returns, aging equipment, high-value missing assets, devices with no maintenance record, and equipment that has never been tracked. Click any suggestion to log an action directly.',
  },
  {
    term: 'Item Code and QR Scanner',
    desc: 'Each record gets a unique item code assigned automatically. Print the QR code and attach it to the device. Use the QR Scanner to look up any record instantly by scanning.',
  },
]

function OnboardingModal({ onDismiss }) {
  const listRef = useRef(null)
  const [reachedBottom, setReachedBottom] = useState(false)

  const checkBottom = useCallback(() => {
    const el = listRef.current
    if (!el) return
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 8) setReachedBottom(true)
  }, [])

  // Check on mount in case content fits without scrolling
  useEffect(() => { checkBottom() }, [checkBottom])

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onDismiss() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onDismiss])

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="onboarding-title"
    >
      <div className="absolute inset-0 bg-zinc-950/80" />

      <div className="relative bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 rounded-xl shadow-2xl shadow-black/50 w-full max-w-lg animate-scale-in flex flex-col max-h-[calc(100vh-4rem)]">
        {/* Header */}
        <div className="px-7 pt-7 pb-5 border-b border-slate-200 dark:border-zinc-800">
          <p className="text-2xs font-semibold text-brand-500 uppercase tracking-widest mb-1.5">Getting started</p>
          <h2 id="onboarding-title" className="text-lg font-bold text-slate-900 dark:text-white leading-snug">
            Before you start
          </h2>
          <p className="text-sm text-slate-500 dark:text-zinc-400 mt-1">
            Five things every GSO staff member should know.
          </p>
        </div>

        {/* Concepts — numbered list */}
        <ol ref={listRef} onScroll={checkBottom} className="px-7 py-5 space-y-5 overflow-y-auto flex-1">
          {CONCEPTS.map((c, i) => (
            <li key={i} className="flex items-start gap-4">
              <span className="w-6 h-6 rounded-full bg-brand-500/10 text-brand-400 text-xs font-bold flex items-center justify-center flex-shrink-0 mt-px select-none">
                {i + 1}
              </span>
              <div className="min-w-0">
                <p className="text-sm font-semibold text-slate-800 dark:text-zinc-100 leading-snug">{c.term}</p>
                <p className="text-xs text-slate-500 dark:text-zinc-400 mt-1 leading-relaxed">{c.desc}</p>
              </div>
            </li>
          ))}
        </ol>

        {/* Footer */}
        <div className="px-7 pb-7 pt-4 flex items-center justify-end border-t border-slate-200 dark:border-zinc-800">
          {!reachedBottom && (
            <p className="text-xs text-slate-400 dark:text-zinc-500 mr-auto">Scroll down to continue ↓</p>
          )}
          <Button
            autoFocus
            variant="primary"
            size="lg"
            onClick={onDismiss}
            disabled={!reachedBottom}
          >
            Got it, take me in
          </Button>
        </div>
      </div>
    </div>
  )
}

export function useOnboarding() {
  const [show, setShow] = useState(false)

  useEffect(() => {
    if (!localStorage.getItem(STORAGE_KEY)) {
      setShow(true)
    }
  }, [])

  const dismiss = () => {
    localStorage.setItem(STORAGE_KEY, '1')
    setShow(false)
  }

  const reset = () => {
    localStorage.removeItem(STORAGE_KEY)
    setShow(true)
  }

  return { show, dismiss, reset }
}

export default OnboardingModal
