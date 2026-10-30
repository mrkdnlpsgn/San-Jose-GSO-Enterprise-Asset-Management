import { useState } from 'react'

// Eye button for a password field. Hidden password: the eye has a slash through it; showing it
// draws the slash away while the eye blinks open (and the reverse). Reduced motion turns the
// movement off (index.css), leaving the icon change.
function PasswordToggle({ shown, onToggle, controls }) {
  const [blink, setBlink] = useState(0) // remounts the eye so its blink replays on every press

  return (
    <button
      type="button"
      onClick={() => { setBlink((n) => n + 1); onToggle() }}
      aria-pressed={shown}
      aria-controls={controls}
      aria-label={shown ? 'Hide password' : 'Show password'}
      title={shown ? 'Hide password' : 'Show password'}
      className="h-9 w-9 inline-flex items-center justify-center rounded-md text-slate-500 dark:text-zinc-400 hover:text-slate-800 dark:hover:text-zinc-100 hover:bg-slate-100 dark:hover:bg-zinc-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 transition-colors duration-150 active:scale-95"
    >
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor"
        strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <g key={blink} className={blink ? 'animate-eye-blink' : ''} style={{ transformOrigin: '12px 12px', transformBox: 'view-box' }}>
          <path d="M2.1 12.3a1 1 0 010-.6C3.6 7.4 7.5 4.5 12 4.5s8.4 2.9 9.9 7.2a1 1 0 010 .6c-1.5 4.3-5.4 7.2-9.9 7.2s-8.4-2.9-9.9-7.2z" />
          <circle cx="12" cy="12" r="3"
            className="transition-transform duration-200 ease-out"
            style={{ transformOrigin: '12px 12px', transformBox: 'view-box', transform: shown ? 'scale(1)' : 'scale(0.75)' }} />
        </g>
        {/* the slash: drawn in when the password is hidden, drawn away when it is shown */}
        <path d="M3.5 3.5l17 17" pathLength="1" strokeDasharray="1"
          className="transition-[stroke-dashoffset] duration-200 ease-out"
          style={{ strokeDashoffset: shown ? 1 : 0 }} />
      </svg>
    </button>
  )
}

export default PasswordToggle
