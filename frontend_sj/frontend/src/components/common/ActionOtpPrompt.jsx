import { useCallback, useEffect, useRef, useState } from 'react'
import api, { setActionOtpPrompt } from '../../services/api'

// Emailed code before a status change or a decision on a staff request. The server answers such a
// request with 428 ACTION_OTP_REQUIRED (and emails a code); api.js hands it here, this asks for the
// code and repeats the same request with it. Mounted once in App, so every page gets it.
const RESEND_COOLDOWN_SECONDS = 60
const HEADER = 'X-Action-Otp'

const withHeaders = (config, extra) => ({
  ...config,
  headers: { ...(config.headers?.toJSON ? config.headers.toJSON() : config.headers), ...extra },
  _otpRetry: true,
})

// Rejection for Cancel, shaped like an API error so callers show it the way they show any other.
const cancelled = () => Object.assign(new Error('Cancelled'), {
  response: { status: 499, data: { message: 'Cancelled. Nothing was changed.' } },
})

function ActionOtpPrompt() {
  const [pending, setPending]   = useState(null) // { config, message, resolve, reject }
  const [otp, setOtp]           = useState('')
  const [error, setError]       = useState('')
  const [busy, setBusy]         = useState(false)
  const [cooldown, setCooldown] = useState(0)
  const timerRef = useRef(null)
  const openRef  = useRef(false)

  const startCooldown = () => {
    setCooldown(RESEND_COOLDOWN_SECONDS)
    clearInterval(timerRef.current)
    timerRef.current = setInterval(() => {
      setCooldown((c) => {
        if (c <= 1) { clearInterval(timerRef.current); return 0 }
        return c - 1
      })
    }, 1000)
  }

  const open = useCallback(({ info, config }) => new Promise((resolve, reject) => {
    if (openRef.current) {
      reject(Object.assign(new Error('Busy'), { response: { data: { message: 'Finish the open confirmation first.' } } }))
      return
    }
    openRef.current = true
    setOtp('')
    setError('')
    setBusy(false)
    setPending({ config, message: info?.message || 'Enter the 6-digit code we emailed you.', resolve, reject })
    startCooldown()
  }), [])

  useEffect(() => {
    setActionOtpPrompt(open)
    return () => { setActionOtpPrompt(null); clearInterval(timerRef.current) }
  }, [open])

  const close = () => {
    openRef.current = false
    clearInterval(timerRef.current)
    setPending(null)
  }

  const handleCancel = () => {
    pending?.reject(cancelled())
    close()
  }

  const handleConfirm = async () => {
    if (otp.trim().length !== 6) { setError('Enter the 6-digit code from your email.'); return }
    setBusy(true)
    setError('')
    try {
      const res = await api.request(withHeaders(pending.config, { [HEADER]: otp.trim() }))
      pending.resolve(res)
      close()
    } catch (err) {
      if (err.response?.data?.code === 'ACTION_OTP_INVALID') {
        setError(err.response.data.message || 'Invalid or expired code.')
        setBusy(false)
        return
      }
      // the code was fine but the change itself failed: hand that error to the page
      pending.reject(err)
      close()
    }
  }

  // The same request without a code makes the server email a new one.
  const handleResend = async () => {
    setError('')
    try {
      await api.request(withHeaders(pending.config, {}))
    } catch (err) {
      if (err.response?.status === 428) {
        setPending((p) => ({ ...p, message: err.response.data?.message || p.message }))
        startCooldown()
      } else {
        setError(err.response?.data?.message || 'Could not send a new code.')
      }
    }
  }

  if (!pending) return null

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center p-4 animate-fade-slide" role="alertdialog" aria-modal="true" aria-labelledby="action-otp-title">
      <div className="absolute inset-0 bg-black/30 dark:bg-zinc-950/80" onClick={busy ? undefined : handleCancel} />
      <div className="relative bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-700 rounded-xl shadow-2xl shadow-black/10 dark:shadow-black/60 w-full max-w-sm p-6">
        <div className="w-11 h-11 rounded-full bg-brand-50 dark:bg-brand-500/10 flex items-center justify-center mx-auto mb-4">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-brand-600 dark:text-brand-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path fillRule="evenodd" d="M10 1a4.5 4.5 0 00-4.5 4.5V9H5a2 2 0 00-2 2v6a2 2 0 002 2h10a2 2 0 002-2v-6a2 2 0 00-2-2h-.5V5.5A4.5 4.5 0 0010 1zm3 8V5.5a3 3 0 10-6 0V9h6z" clipRule="evenodd" />
          </svg>
        </div>

        <h2 id="action-otp-title" className="text-sm font-semibold text-gov-700 dark:text-white text-center">Confirm with your code</h2>
        <p className="text-xs text-slate-500 dark:text-zinc-400 text-center mt-2 leading-relaxed">{pending.message}</p>

        <div className="mt-4">
          <input
            type="text"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            autoFocus
            placeholder="6-digit code"
            aria-label="6-digit code"
            value={otp}
            onChange={(e) => { setOtp(e.target.value.replace(/\D/g, '')); setError('') }}
            onKeyDown={(e) => { if (e.key === 'Enter') handleConfirm() }}
            className="w-full text-center tracking-[0.5em] font-mono text-lg rounded-md border border-slate-200 dark:border-zinc-700 px-3.5 py-2.5 bg-white dark:bg-zinc-800 text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 transition-all"
          />
          <div className="flex justify-center mt-2">
            <button
              type="button"
              onClick={handleResend}
              disabled={cooldown > 0 || busy}
              className="text-xs font-medium text-brand-600 dark:text-brand-400 hover:underline disabled:opacity-40 disabled:no-underline disabled:cursor-not-allowed"
            >
              {cooldown > 0 ? `Resend code in ${cooldown}s` : 'Resend code'}
            </button>
          </div>
        </div>

        {error && <p className="text-xs text-red-500 text-center mt-3" role="alert">{error}</p>}

        <div className="flex gap-3 mt-6">
          <button
            type="button"
            onClick={handleCancel}
            disabled={busy}
            className="flex-1 py-2.5 text-sm font-semibold rounded-md bg-slate-100 dark:bg-zinc-800 text-slate-700 dark:text-zinc-300 border border-slate-200 dark:border-zinc-700 hover:bg-slate-200 dark:hover:bg-zinc-700 transition-all duration-150 active:scale-[0.97] disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleConfirm}
            disabled={busy || otp.trim().length !== 6}
            className="flex-1 py-2.5 text-sm font-semibold rounded-md bg-brand-600 text-white hover:bg-brand-700 transition-all duration-150 active:scale-[0.97] disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {busy ? 'Confirming…' : 'Confirm'}
          </button>
        </div>
      </div>
    </div>
  )
}

export default ActionOtpPrompt
