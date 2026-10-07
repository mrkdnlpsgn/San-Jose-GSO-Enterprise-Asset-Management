import { useState, useRef, useEffect } from 'react'
import { useNavigate, useLocation, Link } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import Input from '../../components/common/Input'
import ForgotPasswordForm from './ForgotPasswordForm'
import ForceChangePasswordForm from './ForceChangePasswordForm'
import TwoFactorForm from './TwoFactorForm'
import SettingsMenu from '../../components/common/SettingsMenu'

// Must match the backend's auth.max-failed-attempts / auth.lockout-minutes (application.properties).
const MAX_ATTEMPTS = 3
const LOCKOUT_MINUTES = 15

// Backend messages are terse ("Invalid credentials") — say what happened in plain words.
// Returns { message, lockedUntil? } (lockedUntil: ms timestamp when the account unlocks).
function describeLoginError(err) {
  const res = err?.response
  if (!res) {
    return { message: "Can't reach the server. Check that this computer is connected to the network, then try again. If it keeps happening, contact the ICT Division." }
  }
  const data = res.data || {}
  if (data.retryAfterSeconds) {
    return {
      message: 'This account is locked after too many incorrect tries, to keep it safe.',
      lockedUntil: Date.now() + data.retryAfterSeconds * 1000,
    }
  }
  if (res.status >= 500) {
    return { message: 'Something went wrong on the server. Please try again in a moment, or contact the ICT Division.' }
  }
  const msg = data.message
  if (!msg || /invalid (credentials|email or password|username or password)|bad credentials/i.test(msg)) {
    const left = data.attemptsRemaining
    if (left > 0) {
      return { message: `The username or password is incorrect. You have ${left} ${left === 1 ? 'try' : 'tries'} left before this account is locked for ${LOCKOUT_MINUTES} minutes.` }
    }
    return { message: `The username or password is incorrect. Please check and try again. After ${MAX_ATTEMPTS} incorrect tries, the account is locked for ${LOCKOUT_MINUTES} minutes.` }
  }
  if (/deactivated/i.test(msg)) return { message: 'This account has been deactivated. Please contact the ICT Division.' }
  return { message: msg }
}

// "14 minutes" / "1 minute" / "45 seconds" — rounded up so it never says 0 too early.
function timeLeft(ms) {
  const secs = Math.max(1, Math.ceil(ms / 1000))
  if (secs < 60) return `${secs} second${secs === 1 ? '' : 's'}`
  const mins = Math.ceil(secs / 60)
  return `${mins} minute${mins === 1 ? '' : 's'}`
}

// Philippine Standard Time, as government portals show it. Ticks every second on its own so
// the rest of the login page doesn't re-render.
function PhilippineTime({ className = '' }) {
  const [now, setNow] = useState(() => new Date())
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 1000)
    return () => clearInterval(timer)
  }, [])
  const time = now.toLocaleTimeString('en-PH', { timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit', second: '2-digit' })
  const date = now.toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })
  return (
    // Never hidden: on a short panel (large text) it gets more compact instead — tighter padding
    // and a smaller time first, then the label goes, then the date.
    <div className={`w-full max-w-[17rem] rounded-xl border border-slate-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 px-5 py-4 [@container(max-height:44rem)]:py-2.5 ${className}`}>
      <p className="text-2xs font-semibold uppercase tracking-wider text-slate-500 dark:text-zinc-400 [@container(max-height:33.5rem)]:hidden">Philippine Standard Time</p>
      <p className="mt-1 [@container(max-height:33.5rem)]:mt-0 text-2xl [@container(max-height:44rem)]:text-xl font-bold text-gov-700 dark:text-white tabular-nums" aria-live="off">{time}</p>
      <p className="mt-0.5 text-sm [@container(max-height:44rem)]:text-xs text-slate-600 dark:text-zinc-300 [@container(max-height:29rem)]:hidden">{date}</p>
    </div>
  )
}

function Login() {
  const { login, completeForcedPasswordChange, completeLoginOtp } = useAuth()
  const navigate   = useNavigate()
  const location   = useLocation()
  // set by useAuth().signOut({ reason: 'idle' }) after the inactivity timeout
  const signedOutIdle = location.state?.reason === 'idle'
  const passwordChanged = location.state?.reason === 'password-changed'   // set by My Account
  const signedOutEverywhere = location.state?.reason === 'signed-out-everywhere'   // My Account → Forget remembered computers
  const usernameRef = useRef(null)
  const passwordRef = useRef(null)
  const [fieldErrors, setFieldErrors] = useState({})
  const [capsLock, setCapsLock]     = useState(false)
  const [form, setForm]             = useState({ identifier: '', password: '' })
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError]             = useState('')
  const [loading, setLoading]         = useState(false)
  const [showForgotPassword, setShowForgotPassword] = useState(false)
  const [forcedChange, setForcedChange] = useState(null)
  const [twoFactorPending, setTwoFactorPending] = useState(null)
  // Set while the account is locked out; the countdown ticks once a second until it unlocks.
  const [lockedUntil, setLockedUntil] = useState(null)
  const [now, setNow]                 = useState(Date.now())
  const locked = lockedUntil != null && now < lockedUntil

  useEffect(() => {
    if (lockedUntil == null) return undefined
    const timer = setInterval(() => {
      const t = Date.now()
      setNow(t)
      if (t >= lockedUntil) {
        setLockedUntil(null)
        setError('')
      }
    }, 1000)
    return () => clearInterval(timer)
  }, [lockedUntil])

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (locked) return
    setError('')
    // check for empty fields here instead of sending a request that can only fail
    const missing = {}
    if (!form.identifier.trim()) missing.identifier = 'Enter your username.'
    if (!form.password) missing.password = 'Enter your password.'
    setFieldErrors(missing)
    if (missing.identifier) { usernameRef.current?.focus(); return }
    if (missing.password) { passwordRef.current?.focus(); return }
    setLoading(true)
    try {
      const result = await login(form)
      if (result?.mustChangePassword) {
        setForcedChange({ identifier: form.identifier, currentPassword: form.password })
      } else if (result?.requiresTwoFactor) {
        setTwoFactorPending({ identifier: form.identifier })
      } else {
        navigate('/dashboard')
      }
    } catch (err) {
      const { message, lockedUntil: until } = describeLoginError(err)
      setError(message)
      if (until) { setNow(Date.now()); setLockedUntil(until) }
    } finally {
      setLoading(false)
    }
  }

  const handleForcedChangeSubmit = async (payload) => {
    await completeForcedPasswordChange(payload)
    navigate('/dashboard')
  }

  const handleOtpSubmit = async (payload) => {
    await completeLoginOtp(payload)
    navigate('/dashboard')
  }

  // Typing again clears the old error — it no longer describes what's on screen. A lockout
  // belongs to one account, so it stays until the countdown ends or the username changes.
  const setField = (key) => (e) => {
    setForm((f) => ({ ...f, [key]: e.target.value }))
    if (key === 'identifier' && lockedUntil != null) { setLockedUntil(null); setError('') }
    else if (error && !locked) setError('')
    if (fieldErrors[key]) setFieldErrors((fe) => ({ ...fe, [key]: undefined }))
  }
  const checkCapsLock = (e) => {
    if (typeof e.getModifierState === 'function') setCapsLock(e.getModifierState('CapsLock'))
  }

  // Re-submits the original credentials so the backend can email a fresh code
  // (subject to its own resend cooldown) — the password never left this screen.
  const handleOtpResend = () => login(form)

  return (
    // Exactly the window's height, never taller: the side panel's height-based steps (clock, seal
    // size) must not depend on content, or showing the clock can add a page scrollbar that rewraps
    // the form, changes the height and hides the clock again — a loop that restarted its animation
    // every tick. If the form ever needs more room, only the form side scrolls.
    <div className="h-dvh flex flex-col overflow-hidden bg-white dark:bg-zinc-950">
      <div className="flex-1 min-h-0 flex relative">
      <SettingsMenu className="absolute top-4 right-4 z-10" />

      {/* Left panel. With larger text (Settings → Text size scales the whole UI) it would grow
          taller than the screen, so it is a size container: it takes the window's height, and its
          contents step down as the room shrinks — a smaller seal, tighter spacing and a compact
          clock, then the divider and secondary lines go. The clock itself always stays. The
          thresholds are in rem, so they scale with the text size too. */}
      <div className="hidden lg:flex lg:w-5/12 xl:w-[27.5rem] flex-col flex-shrink-0 relative overflow-hidden [container-type:size] border-r border-slate-100 dark:border-zinc-800 bg-gradient-to-b from-brand-500/5 via-white to-white dark:from-brand-500/8 dark:via-zinc-900 dark:to-zinc-900">
        {/* Philippine flag stripe, as on official government sites */}
        <div className="flex h-1.5 w-full origin-left animate-draw-x" aria-hidden="true">
          <span className="flex-1 bg-[#0038A8]" />
          <span className="flex-1 bg-[#CE1126]" />
          <span className="flex-1 bg-[#FCD116]" />
        </div>

        <div className="flex-1 flex flex-col items-center justify-center text-center px-12 py-10 [@container(max-height:44rem)]:py-6">
          <img
            src="/logo.jpg"
            alt="San Jose Municipal Hall seal"
            className="w-32 h-32 [@container(max-height:44rem)]:w-20 [@container(max-height:44rem)]:h-20 rounded-full object-cover ring-4 ring-white dark:ring-zinc-800 shadow-[0_0_0_1px_rgba(15,23,42,0.08),0_8px_24px_-8px_rgba(15,23,42,0.25)] animate-seal-in"
          />

          <p className="mt-8 [@container(max-height:44rem)]:mt-5 text-sm font-bold text-brand-700 dark:text-brand-400 uppercase tracking-[0.15em] animate-rise-in [animation-delay:120ms]">
            San Jose Municipal Hall
          </p>
          <p className="mt-3 text-3xl font-extrabold text-gov-700 dark:text-white tracking-tight leading-tight animate-rise-in [animation-delay:200ms]">
            San Jose GSO<br />Inventory Management System
          </p>
          <span className="mt-5 [@container(max-height:33.5rem)]:hidden block h-1 w-14 rounded-full bg-brand-500 origin-center animate-draw-x [animation-delay:380ms]" aria-hidden="true" />
          <p className="mt-5 [@container(max-height:44rem)]:mt-3 text-base text-slate-600 dark:text-zinc-300 animate-rise-in [animation-delay:300ms]">
            General Services Office
            <span className="block [@container(max-height:33.5rem)]:hidden text-sm text-slate-500 dark:text-zinc-400 mt-0.5">Batangas · Republic of the Philippines</span>
          </p>

          <PhilippineTime className="mt-10 [@container(max-height:44rem)]:mt-5 animate-rise-in [animation-delay:440ms]" />
        </div>

        <p className="px-12 pb-8 [@container(max-height:44rem)]:pb-5 text-sm text-center text-slate-600 dark:text-zinc-400 animate-rise-in [animation-delay:500ms]">
          © {new Date().getFullYear()} San Jose Municipal Hall
          {' · '}
          <Link to="/privacy" className="underline underline-offset-2 hover:text-brand-700 dark:hover:text-brand-400 transition-colors duration-150">Privacy Notice</Link>
        </p>
      </div>

      {/* Right panel — form */}
      <div className="flex-1 min-w-0 flex overflow-y-auto px-6 py-6 [&>*]:m-auto">
        {forcedChange ? (
          <ForceChangePasswordForm
            identifier={forcedChange.identifier}
            currentPassword={forcedChange.currentPassword}
            onSubmit={handleForcedChangeSubmit}
          />
        ) : twoFactorPending ? (
          <TwoFactorForm
            identifier={twoFactorPending.identifier}
            onSubmit={handleOtpSubmit}
            onResend={handleOtpResend}
            onBack={() => setTwoFactorPending(null)}
          />
        ) : showForgotPassword ? (
          <div className="w-full max-w-sm">
            <ForgotPasswordForm
              initialIdentifier={form.identifier}
              onBack={(username) => {
                // back to the sign-in fields, keeping the username that was just used
                setForm({ identifier: username || form.identifier, password: '' })
                setError('')
                setFieldErrors({})
                setShowForgotPassword(false)
              }}
            />
          </div>
        ) : (
        <div className="w-full max-w-sm">

          {/* Mobile brand */}
          <div className="flex flex-col items-center text-center gap-3 mb-8 lg:hidden animate-rise-in">
            <div className="relative">
              <img
                src="/logo.jpg"
                alt="San Jose Municipal Hall seal"
                className="w-20 h-20 rounded-full object-cover ring-1 ring-slate-200 dark:ring-zinc-700"
              />
            </div>
            <div>
              <p className="text-sm font-bold text-brand-700 dark:text-brand-400 uppercase tracking-[0.12em]">San Jose Municipal Hall</p>
              <p className="text-lg font-extrabold text-gov-700 dark:text-white mt-1 leading-tight">GSO Inventory Management System</p>
              <p className="text-sm text-slate-600 dark:text-zinc-300 mt-0.5">Batangas · Philippines</p>
            </div>
          </div>

          <div className="animate-rise-in [animation-delay:150ms]">
          <div className="mb-6">
            <h1 className="text-2xl font-bold text-gov-700 dark:text-white tracking-tight">Sign in</h1>
            <p className="text-base text-slate-600 dark:text-zinc-300 mt-1">
              Enter the username and password given to you by the system administrator.
            </p>
          </div>

          {signedOutIdle && !error && (
            <div role="status"
              className="flex items-start gap-2.5 bg-blue-50 dark:bg-blue-950/40 border border-blue-200 dark:border-blue-900/60 text-blue-800 dark:text-blue-300 rounded-lg px-4 py-3 mb-5 text-sm">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clipRule="evenodd" />
              </svg>
              You were signed out after 15 minutes of inactivity, to keep the account safe. Please sign in again.
            </div>
          )}

          {passwordChanged && !error && (
            <div role="status"
              className="flex items-start gap-2.5 bg-emerald-50 dark:bg-emerald-950/40 border border-emerald-200 dark:border-emerald-900/60 text-emerald-800 dark:text-emerald-300 rounded-lg px-4 py-3 mb-5 text-sm">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
              </svg>
              Your password was changed. Please sign in with your new password.
            </div>
          )}

          {signedOutEverywhere && !error && (
            <div role="status"
              className="flex items-start gap-2.5 bg-blue-50 dark:bg-blue-950/40 border border-blue-200 dark:border-blue-900/60 text-blue-800 dark:text-blue-300 rounded-lg px-4 py-3 mb-5 text-sm">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
              Remembered computers were forgotten and you were signed out everywhere. Sign in again — you'll be asked for a code.
            </div>
          )}

          {error && (
            <div
              key={error}
              role="alert"
              className="animate-shake flex items-start gap-2.5 bg-red-50 dark:bg-red-950/50 border border-red-200 dark:border-red-900/60 text-red-700 dark:text-red-400 rounded-lg px-4 py-3 mb-5 text-sm"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mt-0.5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
              </svg>
              <div>
                {error}
                {locked && (
                  <p className="mt-1 font-semibold" aria-live="off">
                    You can try again in {timeLeft(lockedUntil - now)}.
                  </p>
                )}
              </div>
            </div>
          )}

          <form onSubmit={handleSubmit} noValidate>
            {/* Username */}
            <div className="mb-5">
              <Input
                id="login-username"
                ref={usernameRef}
                label="Username"
                type="text"
                autoComplete="username"
                autoFocus
                placeholder="Enter your username"
                value={form.identifier}
                onChange={setField('identifier')}
                error={fieldErrors.identifier}
                startIcon={
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z" clipRule="evenodd" />
                  </svg>
                }
                className="!text-base py-3"
                required
              />
            </div>

            {/* Password */}
            <div className="mb-5">
              <div className="flex items-center justify-between mb-1.5">
                <label htmlFor="login-password" className="text-sm font-medium text-slate-700 dark:text-zinc-300">
                  Password
                </label>
                <button
                  type="button"
                  onClick={() => setShowForgotPassword(true)}
                  className="text-sm font-medium text-brand-700 dark:text-brand-400 hover:text-brand-800 dark:hover:text-brand-300 hover:underline underline-offset-2 transition-colors duration-150"
                >
                  Forgot password?
                </button>
              </div>
              <Input
                id="login-password"
                ref={passwordRef}
                type={showPassword ? 'text' : 'password'}
                autoComplete="current-password"
                placeholder="Enter your password"
                value={form.password}
                onChange={setField('password')}
                startIcon={
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clipRule="evenodd" />
                  </svg>
                }
                onKeyDown={checkCapsLock}
                onKeyUp={checkCapsLock}
                onBlur={() => setCapsLock(false)}
                error={fieldErrors.password}
                className="!text-base py-3 pr-20"
                required
                adornmentClassName="pr-1.5"
                endAdornment={
                  <button
                    type="button"
                    onClick={() => setShowPassword((v) => !v)}
                    aria-pressed={showPassword}
                    aria-controls="login-password"
                    className="h-9 px-3 rounded-md text-sm font-semibold text-slate-700 dark:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 transition-colors duration-150"
                  >
                    {showPassword ? 'Hide' : 'Show'}
                  </button>
                }
              />
              {capsLock && (
                <p role="status" className="mt-2 flex items-center gap-2 text-sm font-medium text-amber-800 dark:text-amber-300 bg-amber-50 dark:bg-amber-500/10 border border-amber-200 dark:border-amber-500/30 rounded-md px-3 py-2">
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                    <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                  </svg>
                  Caps Lock is on — passwords are case-sensitive.
                </p>
              )}
            </div>

            <button
              type="submit"
              disabled={loading || locked}
              className="w-full h-12 px-5 text-base font-semibold rounded-lg bg-brand-700 text-white hover:bg-brand-800 active:scale-[0.98] transition-all duration-150 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:opacity-70 disabled:cursor-not-allowed"
            >
              {loading ? (
                <span className="flex items-center justify-center gap-2">
                  <svg className="animate-spin h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                  </svg>
                  Signing in…
                </span>
              ) : locked ? `Locked — try again in ${timeLeft(lockedUntil - now)}` : 'Sign In'}
            </button>
          </form>
          </div>

          <p className="mt-6 pt-4 border-t border-slate-200 dark:border-zinc-800 flex items-start gap-2.5 text-sm text-slate-600 dark:text-zinc-400 animate-rise-in [animation-delay:300ms]">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 flex-shrink-0 text-slate-500 dark:text-zinc-500" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path fillRule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clipRule="evenodd" />
            </svg>
            <span>For authorized San Jose Municipal Hall personnel only. Sign-ins and activity in this system are recorded.</span>
          </p>

        </div>
        )}
      </div>

      </div>
    </div>
  )
}

export default Login
