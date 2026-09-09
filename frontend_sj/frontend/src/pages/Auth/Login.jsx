import { useState } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import { useTheme } from '../../context/ThemeContext'
import Input from '../../components/common/Input'
import ForgotPasswordModal from './ForgotPasswordModal'
import ForceChangePasswordForm from './ForceChangePasswordForm'
import TwoFactorForm from './TwoFactorForm'

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
  const { isDark, toggle } = useTheme()
  const [form, setForm]               = useState({ identifier: '', password: '' })
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError]             = useState('')
  const [loading, setLoading]         = useState(false)
  const [showForgotPassword, setShowForgotPassword] = useState(false)
  const [forcedChange, setForcedChange] = useState(null)
  const [twoFactorPending, setTwoFactorPending] = useState(null)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
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
      const msg = err?.response?.data?.message
      setError(msg || 'Incorrect username or password. Please try again.')
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

  // Re-submits the original credentials so the backend can email a fresh code
  // (subject to its own resend cooldown) — the password never left this screen.
  const handleOtpResend = () => login(form)

  return (
    <div className="min-h-screen flex bg-white dark:bg-zinc-950 relative">
      <button
        onClick={toggle}
        title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
        aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
        className="absolute top-4 right-4 z-10 p-3.5 rounded-md text-slate-500 dark:text-zinc-400 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150"
      >
        {isDark ? (
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path fillRule="evenodd" d="M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z" clipRule="evenodd" />
          </svg>
        ) : (
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z" />
          </svg>
        )}
      </button>

      {/* Left panel */}
      <div className="hidden lg:flex lg:w-5/12 xl:w-[440px] flex-col justify-between flex-shrink-0 border-r border-slate-100 dark:border-zinc-800 bg-gradient-to-b from-brand-500/5 via-white to-white dark:from-brand-500/8 dark:via-zinc-900 dark:to-zinc-900 p-12">
        {/* Brand block */}
        <div className="flex flex-col items-center text-center gap-7">
          {/* Logo with glow */}
          <div className="relative mt-4">
            <div className="absolute inset-0 rounded-full bg-brand-500/25 blur-2xl scale-150" />
            <img
              src="/logo.jpg"
              alt="San Jose Municipal Hall seal"
              className="relative w-28 h-28 rounded-full object-cover ring-4 ring-brand-500/30 shadow-2xl shadow-brand-500/20"
            />
          </div>

          <div>
            <p className="text-xs font-bold text-brand-500 uppercase tracking-[0.2em] mb-3">
              San Jose Municipal Hall
            </p>
            <p className="text-3xl font-extrabold text-slate-900 dark:text-white tracking-tight leading-tight">
              San Jose GSO<br />Inventory Management System
            </p>
            <p className="text-sm text-slate-500 dark:text-zinc-400 mt-3">
              Batangas · Republic of the Philippines
            </p>
          </div>

          {/* Feature list */}
          <div className="w-full pt-4 border-t border-slate-100 dark:border-zinc-800 space-y-3">
            {FEATURES.map(({ text, icon }) => (
              <div key={text} className="flex items-center gap-3 text-sm text-slate-500 dark:text-zinc-400">
                <span className="w-7 h-7 rounded-lg bg-brand-500/10 text-brand-500 flex items-center justify-center flex-shrink-0">
                  {icon}
                </span>
                {text}
              </div>
            ))}
          </div>
        </div>

        {/* Bottom */}
        <p className="text-xs text-center text-slate-500 dark:text-zinc-400">
          © {new Date().getFullYear()} San Jose Municipal Hall
          {' · '}
          <Link to="/privacy" className="hover:text-brand-500 dark:hover:text-brand-400 transition-colors duration-150">Privacy Notice</Link>
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
              <div className="absolute inset-0 rounded-full bg-brand-500/20 blur-xl scale-150" />
              <img
                src="/logo.jpg"
                alt="San Jose Municipal Hall seal"
                className="relative w-20 h-20 rounded-full object-cover ring-4 ring-brand-500/30 shadow-xl shadow-brand-500/10"
              />
            </div>
            <div>
              <p className="text-xs font-bold text-brand-500 uppercase tracking-[0.15em]">San Jose Municipal Hall</p>
              <p className="text-lg font-extrabold text-slate-900 dark:text-white mt-1 leading-tight">GSO Inventory Management System</p>
              <p className="text-xs text-slate-500 dark:text-zinc-400 mt-0.5">Batangas · Philippines</p>
            </div>
          </div>

          <div className="mb-7">
            <h1 className="text-2xl font-bold text-slate-900 dark:text-white tracking-tight">Sign in</h1>
            <p className="text-sm text-slate-500 dark:text-zinc-400 mt-1">Access your account to continue.</p>
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
            {/* Username */}
            <div className="mb-4">
              <Input
                id="identifier"
                label="Username"
                type="text"
                autoComplete="username"
                placeholder="Enter your username"
                value={form.identifier}
                onChange={(e) => setForm({ ...form, identifier: e.target.value })}
                required
              />
            </div>

            {/* Password */}
            <div className="mb-6">
              <div className="flex items-center justify-between mb-1.5">
                <label htmlFor="password" className="text-sm font-medium text-slate-700 dark:text-zinc-300">
                  Password
                </label>
                <button
                  type="button"
                  onClick={() => setShowForgotPassword(true)}
                  className="text-xs font-medium text-brand-600 dark:text-brand-400 hover:text-brand-700 dark:hover:text-brand-300 transition-colors duration-150"
                >
                  Forgot password?
                </button>
              </div>
              <Input
                id="password"
                type={showPassword ? 'text' : 'password'}
                autoComplete="current-password"
                placeholder="••••••••"
                value={form.password}
                onChange={(e) => setForm({ ...form, password: e.target.value })}
                required
                endAdornment={
                  <button
                    type="button"
                    onClick={() => setShowPassword((v) => !v)}
                    className="text-slate-500 dark:text-zinc-400 hover:text-slate-600 dark:hover:text-zinc-300 transition-colors duration-150"
                    aria-label={showPassword ? 'Hide password' : 'Show password'}
                  >
                    {showPassword ? (
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                        <path fillRule="evenodd" d="M3.707 2.293a1 1 0 00-1.414 1.414l14 14a1 1 0 001.414-1.414l-1.473-1.473A10.014 10.014 0 0019.542 10C18.268 5.943 14.478 3 10 3a9.958 9.958 0 00-4.512 1.074l-1.78-1.781zm4.261 4.26l1.514 1.515a2.003 2.003 0 012.45 2.45l1.514 1.514a4 4 0 00-5.478-5.478z" clipRule="evenodd" />
                        <path d="M12.454 16.697L9.75 13.992a4 4 0 01-3.742-3.741L2.335 6.578A9.98 9.98 0 00.458 10c1.274 4.057 5.065 7 9.542 7 .847 0 1.669-.105 2.454-.303z" />
                      </svg>
                    ) : (
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                        <path d="M10 12a2 2 0 100-4 2 2 0 000 4z" />
                        <path fillRule="evenodd" d="M.458 10C1.732 5.943 5.522 3 10 3s8.268 2.943 9.542 7c-1.274 4.057-5.064 7-9.542 7S1.732 14.057.458 10zM14 10a4 4 0 11-8 0 4 4 0 018 0z" clipRule="evenodd" />
                      </svg>
                    )}
                  </button>
                }
              />
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
                  Signing in...
                </span>
              ) : 'Sign In'}
            </button>
          </form>

          <p className="text-xs text-slate-500 dark:text-zinc-400 text-center mt-6">
            For access issues, contact the ICT Division.
          </p>
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
  )
}

export default Login
