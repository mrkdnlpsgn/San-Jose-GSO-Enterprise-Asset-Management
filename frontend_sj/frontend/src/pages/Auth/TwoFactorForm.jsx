import { useState } from 'react'

const INPUT_CLASS =
  'w-full rounded-lg border border-slate-300 dark:border-zinc-700 bg-white dark:bg-zinc-800/60 ' +
  'px-3.5 py-2.5 text-sm text-slate-900 dark:text-white placeholder:text-slate-400 ' +
  'dark:placeholder:text-zinc-600 hover:border-slate-400 dark:hover:border-zinc-600 ' +
  'focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all duration-150'

// Shown in place of the login form when the backend reports requiresTwoFactor —
// correct credentials, but this account needs the emailed code before a session
// is issued. onResend re-submits the original password so the backend can email
// a fresh code (subject to its own resend cooldown); it's a no-op from this
// screen's point of view either way, so failures are swallowed silently.
function TwoFactorForm({ identifier, onSubmit, onResend, onBack }) {
  const [otp, setOtp]         = useState('')
  const [error, setError]     = useState('')
  const [loading, setLoading] = useState(false)
  const [resending, setResending] = useState(false)
  const [resent, setResent]   = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    if (!/^\d{6}$/.test(otp.trim())) { setError('Enter the 6-digit code from your email.'); return }
    setLoading(true)
    try {
      await onSubmit({ identifier, otp: otp.trim() })
    } catch (err) {
      setError(err?.response?.data?.message || 'Invalid or expired code. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  const handleResend = async () => {
    setResending(true)
    setResent(false)
    try {
      await onResend()
      setResent(true)
    } catch {
      // Same-shape failure either way — the account may already have a valid
      // code within its resend cooldown, which isn't an error from here.
      setResent(true)
    } finally {
      setResending(false)
    }
  }

  return (
    <div className="w-full max-w-sm animate-fade-slide">
      <div className="mb-7">
        <h1 className="text-2xl font-bold text-slate-900 dark:text-white tracking-tight">Enter verification code</h1>
        <p className="text-sm text-slate-500 dark:text-zinc-400 mt-1">
          We emailed a 6-digit code to the address on file for <span className="font-semibold text-slate-700 dark:text-zinc-300">{identifier}</span>.
        </p>
      </div>

      {error && (
        <div
          role="alert"
          className="flex items-start gap-2.5 bg-red-50 dark:bg-red-950/50 border border-red-200 dark:border-red-900/60 text-red-600 dark:text-red-400 rounded-lg px-4 py-3 mb-5 text-sm"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mt-0.5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit} noValidate>
        <div className="mb-6">
          <label htmlFor="login-otp" className="text-sm font-medium text-slate-700 dark:text-zinc-300 mb-1.5 block">
            Verification code
          </label>
          <input
            id="login-otp"
            type="text"
            inputMode="numeric"
            autoComplete="one-time-code"
            autoFocus
            maxLength={6}
            placeholder="000000"
            value={otp}
            onChange={(e) => { setOtp(e.target.value.replace(/\D/g, '').slice(0, 6)); setError('') }}
            className={INPUT_CLASS + ' tracking-[0.3em] text-center font-mono'}
          />
          <p className="text-xs text-slate-400 dark:text-zinc-500 mt-1.5">Code expires 10 minutes after it's sent.</p>
        </div>

        <button
          type="submit"
          disabled={loading}
          className="w-full py-2.5 px-5 text-sm font-semibold rounded-lg bg-brand-700 text-white hover:bg-brand-800 active:scale-[0.98] transition-all duration-150 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-zinc-950 disabled:opacity-40 disabled:cursor-not-allowed disabled:active:scale-100"
        >
          {loading ? (
            <span className="flex items-center justify-center gap-2">
              <svg className="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
              </svg>
              Verifying...
            </span>
          ) : 'Verify & Sign In'}
        </button>
      </form>

      <div className="flex items-center justify-between mt-5 text-xs">
        <button
          type="button"
          onClick={onBack}
          className="text-slate-500 dark:text-zinc-400 hover:text-slate-700 dark:hover:text-zinc-200 transition-colors duration-150"
        >
          Back to sign in
        </button>
        <button
          type="button"
          onClick={handleResend}
          disabled={resending}
          className="font-medium text-brand-600 dark:text-brand-400 hover:text-brand-700 dark:hover:text-brand-300 transition-colors duration-150 disabled:opacity-50"
        >
          {resending ? 'Sending...' : resent ? 'Code sent' : "Didn't get it? Resend code"}
        </button>
      </div>
    </div>
  )
}

export default TwoFactorForm
