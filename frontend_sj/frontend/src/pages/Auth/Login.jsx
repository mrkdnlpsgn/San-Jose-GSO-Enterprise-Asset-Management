import { useState, useRef } from 'react'
import { useNavigate, useLocation, Link } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import Input from '../../components/common/Input'
import ForgotPasswordModal from './ForgotPasswordModal'
import ForceChangePasswordForm from './ForceChangePasswordForm'
import TwoFactorForm from './TwoFactorForm'
import SettingsMenu from '../../components/common/SettingsMenu'

// Must match the backend's auth.max-failed-attempts / auth.lockout-minutes (application.properties).
const MAX_ATTEMPTS = 3
const LOCKOUT_MINUTES = 15

// Backend messages are terse ("Invalid credentials") — say what happened in plain words.
function friendlyError(msg) {
  if (!msg || /invalid (credentials|email or password|username or password)|bad credentials/i.test(msg)) {
    return `The username or password is incorrect. Please check and try again. After ${MAX_ATTEMPTS} incorrect tries, the account is locked for ${LOCKOUT_MINUTES} minutes.`
  }
  if (/deactivated/i.test(msg)) return `This account has been deactivated. Please contact the ICT Division.`
  if (/locked/i.test(msg)) return msg.replace(/^Account is temporarily locked\./i, 'This account is temporarily locked after too many incorrect tries.')
  return msg
}

const FEATURES = [
  {
    text: 'Centralized ICT asset management',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path d="M11 17a1 1 0 001.447.894l4-2A1 1 0 0017 15V9.236a1 1 0 00-1.447-.894l-4 2a1 1 0 00-.553.894V17zM15.211 6.276a1 1 0 000-1.788l-4.764-2.382a1 1 0 00-.894 0L4.789 4.488a1 1 0 000 1.788l4.764 2.382a1 1 0 00.894 0l4.764-2.382zM4.447 8.342A1 1 0 003 9.236V15a1 1 0 00.553.894l4 2A1 1 0 009 17v-5.764a1 1 0 00-.553-.894l-4-2z" />
      </svg>
    ),
  },
  {
    text: 'Maintenance and disposal ledgers',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
      </svg>
    ),
  },
  {
    text: 'Asset history tracking and audit logs',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path d="M2 11a1 1 0 011-1h2a1 1 0 011 1v5a1 1 0 01-1 1H3a1 1 0 01-1-1v-5zM8 7a1 1 0 011-1h2a1 1 0 011 1v9a1 1 0 01-1 1H9a1 1 0 01-1-1V7zM14 4a1 1 0 011-1h2a1 1 0 011 1v12a1 1 0 01-1 1h-2a1 1 0 01-1-1V4z" />
      </svg>
    ),
  },
]

function Login() {
  const { login, completeForcedPasswordChange, completeLoginOtp } = useAuth()
  const navigate   = useNavigate()
  const location   = useLocation()
  // set by useAuth().signOut({ reason: 'idle' }) after the inactivity timeout
  const signedOutIdle = location.state?.reason === 'idle'
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

  const handleSubmit = async (e) => {
    e.preventDefault()
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
      setError(friendlyError(err?.response?.data?.message))
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

  // Typing again clears the old error — it no longer describes what's on screen.
  const setField = (key) => (e) => {
    setForm((f) => ({ ...f, [key]: e.target.value }))
    if (error) setError('')
    if (fieldErrors[key]) setFieldErrors((fe) => ({ ...fe, [key]: undefined }))
  }
  const checkCapsLock = (e) => {
    if (typeof e.getModifierState === 'function') setCapsLock(e.getModifierState('CapsLock'))
  }

  // Re-submits the original credentials so the backend can email a fresh code
  // (subject to its own resend cooldown) — the password never left this screen.
  const handleOtpResend = () => login(form)

  return (
    <div className="min-h-screen flex flex-col bg-white dark:bg-zinc-950">
      <div className="flex-1 flex relative">
      <SettingsMenu className="absolute top-4 right-4 z-10" />

      {/* Left panel */}
      <div className="hidden lg:flex lg:w-5/12 xl:w-[440px] flex-col justify-between flex-shrink-0 border-r border-slate-100 dark:border-zinc-800 bg-gradient-to-b from-brand-500/5 via-white to-white dark:from-brand-500/8 dark:via-zinc-900 dark:to-zinc-900 p-12">
        {/* Brand block */}
        <div className="flex flex-col items-center text-center gap-7">
          {/* Logo with glow */}
          <div className="relative mt-4">
            <img
              src="/logo.jpg"
              alt="San Jose Municipal Hall seal"
              className="w-28 h-28 rounded-full object-cover ring-1 ring-slate-200 dark:ring-zinc-700"
            />
          </div>

          <div>
            <p className="text-sm font-bold text-brand-700 dark:text-brand-400 uppercase tracking-[0.15em] mb-3">
              San Jose Municipal Hall
            </p>
            <p className="text-3xl font-extrabold text-gov-700 dark:text-white tracking-tight leading-tight">
              San Jose GSO<br />Inventory Management System
            </p>
            <p className="text-base text-slate-600 dark:text-zinc-300 mt-3">
              Batangas · Republic of the Philippines
            </p>
          </div>

          {/* Feature list */}
          <div className="w-full pt-4 border-t border-slate-100 dark:border-zinc-800 space-y-3">
            {FEATURES.map(({ text, icon }) => (
              <div key={text} className="flex items-center gap-3 text-base text-slate-700 dark:text-zinc-300">
                <span className="w-8 h-8 rounded-lg bg-brand-500/10 text-brand-700 dark:text-brand-400 flex items-center justify-center flex-shrink-0">
                  {icon}
                </span>
                {text}
              </div>
            ))}
          </div>
        </div>

        {/* Bottom */}
        <p className="text-sm text-center text-slate-600 dark:text-zinc-400">
          © {new Date().getFullYear()} San Jose Municipal Hall
          {' · '}
          <Link to="/privacy" className="underline underline-offset-2 hover:text-brand-700 dark:hover:text-brand-400 transition-colors duration-150">Privacy Notice</Link>
        </p>
      </div>

      {/* Right panel — form */}
      <div className="flex-1 flex items-center justify-center px-6 py-12">
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
        ) : (
        <div className="w-full max-w-sm animate-fade-slide">

          {/* Mobile brand */}
          <div className="flex flex-col items-center text-center gap-3 mb-8 lg:hidden">
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

          <div className="mb-7">
            <h1 className="text-2xl font-bold text-gov-700 dark:text-white tracking-tight">Sign in</h1>
            <p className="text-base text-slate-600 dark:text-zinc-300 mt-1">Access your account to continue.</p>
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

          {error && (
            <div
              role="alert"
              className="flex items-start gap-2.5 bg-red-50 dark:bg-red-950/50 border border-red-200 dark:border-red-900/60 text-red-700 dark:text-red-400 rounded-lg px-4 py-3 mb-5 text-sm"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mt-0.5 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
              </svg>
              {error}
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
                className="!text-base py-3"
                required
              />
            </div>

            {/* Password */}
            <div className="mb-6">
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
              disabled={loading}
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
              ) : 'Sign In'}
            </button>
          </form>

        </div>
        )}
      </div>

      {showForgotPassword && (
        <ForgotPasswordModal
          initialIdentifier={form.identifier}
          onClose={() => setShowForgotPassword(false)}
        />
      )}
      </div>
    </div>
  )
}

export default Login
