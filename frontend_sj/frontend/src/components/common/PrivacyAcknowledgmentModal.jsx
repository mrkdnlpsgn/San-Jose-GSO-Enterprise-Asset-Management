import { useState, useEffect, useRef, useCallback } from 'react'
import { Link } from 'react-router-dom'
import Button from './Button'

const SECTIONS = [
  {
    term: 'What this system collects',
    desc: 'Asset records, accountable-person names, your account activity, and audit-trail details (including IP address and timestamps) for every action taken in the system.',
  },
  {
    term: 'Why we collect it',
    desc: 'Republic Act No. 10173 (Data Privacy Act of 2012) requires you be informed of this, since you are both a data subject — your own account and activity are logged — and, in daily use, a handler of other people\'s data (accountable persons, other staff).',
  },
  {
    term: 'Your responsibilities',
    desc: 'Enter only accurate information, never share your login credentials, and report any suspected data breach or misuse to the ICT Division immediately.',
  },
  {
    term: 'Retention',
    desc: 'Records are retained in accordance with Commission on Audit (COA) rules on government property and accountability records.',
  },
]

function PrivacyAcknowledgmentModal({ onAcknowledge, loading = false }) {
  const listRef = useRef(null)
  const [reachedBottom, setReachedBottom] = useState(false)

  const checkBottom = useCallback(() => {
    const el = listRef.current
    if (!el) return
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 8) setReachedBottom(true)
  }, [])

  useEffect(() => { checkBottom() }, [checkBottom])

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="privacy-ack-title"
    >
      <div className="absolute inset-0 bg-zinc-950/80" />

      <div className="relative bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 rounded-xl shadow-2xl shadow-black/50 w-full max-w-lg animate-scale-in flex flex-col max-h-[calc(100vh-4rem)]">
        {/* Header */}
        <div className="px-7 pt-7 pb-5 border-b border-slate-200 dark:border-zinc-800">
          <p className="text-2xs font-semibold text-brand-500 uppercase tracking-widest mb-1.5">Required · Republic Act 10173</p>
          <h2 id="privacy-ack-title" className="text-lg font-bold text-slate-900 dark:text-white leading-snug">
            Privacy, Terms &amp; Conditions
          </h2>
          <p className="text-sm text-slate-500 dark:text-zinc-400 mt-1">
            This is a private, internal government system for authorized GSO/ICT staff only. Please review before continuing.
          </p>
        </div>

        {/* Sections */}
        <ol ref={listRef} onScroll={checkBottom} className="px-7 py-5 space-y-5 overflow-y-auto flex-1">
          {SECTIONS.map((s, i) => (
            <li key={i} className="flex items-start gap-4">
              <span className="w-6 h-6 rounded-full bg-brand-500/10 text-brand-400 text-xs font-bold flex items-center justify-center flex-shrink-0 mt-px select-none">
                {i + 1}
              </span>
              <div className="min-w-0">
                <p className="text-sm font-semibold text-slate-800 dark:text-zinc-100 leading-snug">{s.term}</p>
                <p className="text-xs text-slate-500 dark:text-zinc-400 mt-1 leading-relaxed">{s.desc}</p>
              </div>
            </li>
          ))}
          <li className="pl-10">
            <Link to="/privacy" target="_blank" rel="noopener noreferrer" className="text-xs font-medium text-brand-500 hover:text-brand-400 transition-colors duration-150">
              Read the full Privacy, Terms &amp; Conditions →
            </Link>
          </li>
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
            onClick={onAcknowledge}
            disabled={!reachedBottom || loading}
          >
            {loading ? 'Saving…' : 'I Understand and Acknowledge'}
          </Button>
        </div>
      </div>
    </div>
  )
}

export default PrivacyAcknowledgmentModal
